# TASK-192b: Satellite colour layer (B): terrain and canopy blend

- **Status**: done
- **Layers**: presentation (terrain shader, canopy shell, parcels, `LookPreset`)
- **Depends on**: TASK-192a, TASK-190, TASK-108g (soft: TASK-191 – all done except 192a)
- **Sections**: ARCHITECTURE "Terrain rendering" and its real-scale vegetation paragraphs; ADR 0026, 0028, 0031 (from 192a); look reference (TASK-190)
- **Model**: opus (shader blending, frame budget)
- **Tags**: battle-look

## Goal

Seen from above, the terrain reads like the reference: mottled meadows, distinct field parcels and forests in their real colours, because the far terrain and canopy take their colour from the satellite layer, while the near ground keeps its detail textures.

## Decisions (2026-11-22)

- Near: splat textures keep their detail plus a light, low-frequency, luminance-preserving tint from the layer (~25 %).
- Far: the layer takes over; blend runs from ~300 m to ~1.5 km. Distances are in metres via `MapScale` and tunable in `LookPreset`, not constants in code.
- The canopy shell takes the layer colour over forest but keeps its sun lighting / dark-canopy look (TASK-190/191).
- Fallback: no layer (older maps) or `balanced` preset gives the current look (uniform flag off), tested. The layer is used only under the `true` VisualScale preset.

## Acceptance criteria (testable)

- [ ] `LookPreset` holds near tint strength (default 0.25), blend start (300 m) and blend end (1500 m); values read in metres, none hard-coded in shaders/code.
- [ ] Terrain shader: at distance <= 300 m the layer weight is the near tint only (0.25); at >= 1500 m it is 1.0; at 900 m it is between (test of the weight function).
- [ ] Near tint preserves luminance: the tinted colour's luma differs from the splat colour's luma by <= 2 % (test of the tint function).
- [ ] Canopy shell (`ForestShell`, `BackdropCanopy`) over forest takes the layer's hue, and its lit/shadow brightness ratio stays within 2 % of the current value (test).
- [ ] `ParcelMap` / `FieldParcels` crops keep their colours near the camera; at the blend end distance the parcel colour and the layer colour differ by <= a recorded threshold (screenshot at 1.5 km, no jump).
- [ ] `balanced` preset, and a `true` map without a layer: uniform flag off, rendered output identical to before (test of the flag and the material parameters).
- [ ] Frame time in `true` Suwałki is within 0.5 ms of before (one more texture sample); measured numbers recorded.
- [ ] GPU memory of the layer(s) recorded in Implementation notes.
- [ ] The agent renders and Reads screenshots (widest zoom and near) and states what it saw.

## Playtest (for the human)

1. `true` preset, Suwałki, widest zoom: fields, meadows and forests look like the satellite view of the area; compare with the reference.
2. Zoom in: the satellite colour gives way to the ground textures with no visible seam.
3. Switch to `balanced`: the look is exactly as before.

## Player manual

None (look only).

## Out of scope

- Buildings, roads and villages from imagery; seasons / weather; operational maps; changing the imported data (TASK-192a).

## Implementation notes

- **Data path**: `BattleCover.colour_for_battle` (shares `battle_map` with `for_battle`) -> `SatelliteColour.for_map` (null unless the `true` VisualScale preset and a map with a layer) -> `MapView.satellite`. `SatelliteColour.from_imported` wraps the imported map's whole `ColourRaster` (10 m); `from_layer` cuts the tactical layer's 40 m raster under the region plus `BattleCover.MARGIN` (sampled pixel by pixel through `TacticalLayer.sample`). One mipmapped, anisotropic sRGB texture in world space.
- **Shaders**: `assets/shaders/satellite_colour.gdshaderinc` (uniforms `satellite_*`, `satellite_sample` / `_far` / `_weight` / `_hue` / `_ground`), included by `terrain.gdshader` (blend after the macro brightness, before the off-map factor, lake bed and cloud shadow) and `canopy.gdshader` (crown colour takes the layer hue at its own luminance before the dome shade, so `ForestShell` and `BackdropCanopy` keep their lighting). Both sample in uniform control flow behind `if (satellite_on)`; the default is off.
- **Values**: `LookPreset.SATELLITE_DEFAULT` / `satellite()`: near_tint 0.25, blend 300 -> 1500 m (smoothstep of view distance, MapScale to units), edge_m 150 (fade inside the raster edge), gain 1, saturation 1, canopy_hue 1. Measured before choosing gain 1: Suwalki layer mean linear luma 0.143 vs. grass splat 0.149.
- **Parcels**: near the camera the crops keep their colours with the 25 % luminance-preserving tint; at the blend end (1500 m) the shown colour is the layer's own (difference parcel-shown vs. layer = 0 by construction, the recorded threshold), and `test_the_blend_has_no_jump` bounds every 10 m step below 0.01 (linear RGB sum).
- **Tests**: `tests/unit/test_satellite_colour.gd` (12): preset values, weight at 0/300/900/1500/5000 m and monotonic, near luma within 2 %, far = layer, no coverage = splat, no jump, canopy hue + lit/shadow ratio within 2 %, flag off for balanced / null layer / plain map / generated map, true parameters in world units, imported texture and layer cut match `ImportedMap.sample` / `TacticalLayer.sample`, shaders include and guard the layer.
- **Frame time** (`true`, HIGH, 1280x720, RX 580, Suwalki battle, `SCREENSHOT_MEASURE_FRAMES=300`, camera on unit 2 yaw -40): distance 5 / 24 / 46 units: before 18.34 / 9.17 / 9.73 ms, after 18.41 / 9.25 / 9.86 ms (+0.07 / +0.08 / +0.13 ms, within 0.5 ms). The 18.3 ms at distance 5 is pre-existing (same before).
- **GPU memory**: Suwalki 763 x 527 px -> 2.14 MB (RGBA8 + mips); contact battle cut on the theatre layer 414 x 325 px -> 0.72 MB. Load cost: Suwalki 22 ms; the theatre cut 1.3-1.4 s (134 k `TacticalLayer.sample` calls) under `true` only. Need for gameplay-engineer: a pure `TacticalLayer.colour_image(pixel_rect) -> Image` that blits the decoded windows would cut this to milliseconds.
- **Screenshots** (`true`, Suwalki): widest zoom (46) shows a field mosaic of greens, olives and pale stubble with dark lakes and forests instead of the former large orange blotches; default zoom (24) reads like the satellite view with crowns on the forest shells; at 8 and 3 units the near ground keeps its textures and the satellite colour takes over towards the horizon with no visible line. The imported map's raster ends at the hex bounds: the backdrop ring beyond it keeps the textured look (faded over 150 m). Theatre composite seams / clouds (TASK-192a notes) were not inspected here (contact battle not rendered).
- README shot (generated map, balanced) re-rendered: unchanged, as expected.
