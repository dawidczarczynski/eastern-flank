# TASK-192b: Satellite colour layer (B): terrain and canopy blend

- **Status**: ready
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

_Filled in by the agent when done._
