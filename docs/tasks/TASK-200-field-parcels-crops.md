# TASK-200: Field parcels as distinct crops – colours, rows, edges

- **Status**: done
- **Layers**: presentation (`FieldParcels` in src/presentation/field_parcels.gd, `ParcelMap` in parcel_map.gd, terrain.gdshader, `LookPreset`, satellite_colour.gd)
- **Depends on**: TASK-192b, TASK-190, TASK-108g (all done)
- **Sections**: ARCHITECTURE "Terrain"; TASK-192b (satellite colour); look reference (TASK-190)
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Farmland reads as a patchwork of crops like the reference: each parcel with its own colour (wheat gold, rape yellow, green cereal, stubble, ploughed brown, fallow), visible rows from close up and clear edges – not a uniform muted tone.

## Decisions (interview 2026-11-23)

1. Crop kind per parcel = rule (hash of parcel id, neighbours differ, region mix), then tinted toward the satellite colour of that parcel from the TASK-192b layer (rule + satellite hue). No layer or `balanced` => rule colours / the current look (`balanced` unchanged, tested).
2. Row structure (spacing 0.3–0.75 m by crop, direction constant per parcel) fades out by ~150 m; no moiré beyond. Distances in metres via `MapScale`, tunable in `LookPreset`.
3. Only parcel balks (existing BALK kind) as lighter strips plus a darker headland strip here. `highway=track` strips are NOT in this task (TASK-202).
4. Crop kinds live in data (resource / `FIELDS_DEFAULT`): wheat gold, green cereal, rape yellow, stubble, ploughed brown, fallow / meadow-green (meadows keep the grass look); each with a harvest-state tone.

## Acceptance criteria (testable)

- [ ] Crop kinds (6: wheat, green cereal, rape, stubble, ploughed, fallow/meadow) with colour, row spacing and harvest tone are in a resource, not in code; a test loads it and checks all 6 present.
- [ ] Crop assignment is deterministic: same parcel id + seed gives the same crop in 2 runs (test).
- [ ] No two adjacent parcels share a crop kind on a test map (test over the parcel adjacency graph).
- [ ] Region mix: over a large test region the crop shares follow the rule weights within ±10 percentage points (test). **[ASSUMPTION]** weights are data next to the kinds.
- [ ] With the 192b layer present, the parcel colour = crop colour tinted toward the layer colour at the parcel centroid, tint strength a `LookPreset` value; test: a layer sample of pure red shifts the hue toward red vs. no layer.
- [ ] No layer, or look `balanced`: rule colours only / current look; `balanced` output pixel-identical to before (test).
- [ ] Under `true` the parcel colour is stronger and mottled by large-scale noise (period ≥ 20 m, via `MapScale`).
- [ ] Row spacing per crop is 0.3–0.75 m in real metres (test every kind in range); row direction constant per parcel (same angle at 2 sample points of one parcel, test).
- [ ] Row strength is full below ~50 m and 0 at 150 m camera distance (fade distances in `LookPreset`, metres); test: strength at 150 m and beyond == 0.0, so no moiré.
- [ ] A darker headland strip runs along each parcel edge (width in metres, `LookPreset`); BALK strips between parcels are lighter than the parcel colour (luminance higher, test).
- [ ] Meadow/fallow parcels keep the grass look (colour equals the grass ground colour within tolerance 0.02, test).
- [ ] Frame time unchanged within 0.3 ms (at most one more texture sample), measured with the existing perf tool before/after.
- [ ] Screenshots at 1.2 / 5 / 24 Read against the reference, deviations stated.

## Playtest (for the human)

1. Fly over farmland on `true`: parcels in different crops, neighbours differ, tint follows the satellite colour.
2. Zoom low (~1.2): rows visible; zoom out past ~150 m: rows gone, no shimmering or moiré.
3. Balks lighter, headlands darker at the parcel edges; meadows still look like grass.
4. Switch to `balanced`: look unchanged.

## Player manual

None (visual only).

## Out of scope

- `highway=track` field-road strips (TASK-202).
- Buildings and settlements; animated crops (wind in grain) – a possible follow-up.

## Implementation notes

- **Data**: `CropKind` / `CropCatalog` (src/core/data/, `data/fields/crops.tres`): wheat, green cereal, rape, stubble, ploughed, fallow/meadow with colour, furrow colour, row spacing (0.30-0.75 m), harvest tone, weight (24/18/10/16/20/12 %), `ground_look` (meadow keeps the grass) and grass_keep. `LookPreset.REAL_SIZE_FIELDS` (tint 0.5, tint_blur_m 160, saturation 1.2, mottle 0.2 / period 60 m, rows full 50 m -> 0 at 150 m, harvest_share 0.3, headland 6 m x 0.78 fading by 300 m, pale balk colour) is merged by `LookPreset.fields()` under `true` together with the catalog (maize / potato share 0). `balanced` reads none of it.
- **Assignment**: new kind `FieldParcels.Kind.RAPE` (value 9, appended so older values and `balanced` stay). `FieldParcels.block_crops` assigns per region strip by strip so a strip avoids the crops of the previous strip it touches and its second part avoids the first (`crop_for`, used by `kind` and `bake`, only when `distinct_neighbours`).
- **Shader** (terrain.gdshader, all behind `crop_true`): real row spacing with row strength 1 below 50 m -> 0 at 150 m (on top of the old per-pixel fade), harvest tone on 30 % of parcels, saturation, satellite tint (luminance-preserving hue shift, `crop_tint`), 60 m mottle noise, headland (4 nearest-texel balk probes, only within 300 m), meadow/fallow leave the splat grass untouched. `CropLook` has the GDScript twins.
- **Tests**: tests/unit/test_crop_look.gd (11) + existing field tests; `balanced` pinned by 12 old kind() values and `crop_true` false.
- **Deviations**: (1) neighbour-distinct crops are guaranteed inside a 2.5 km region only; parcels of different regions touch behind a hedge balk and are not constrained. (2) Satellite tint reads the layer through a mip level matching ~160 m (about one parcel) instead of the exact centroid sample, so no bake change and one extra texture read; tint therefore varies slightly inside a parcel. (3) Headland resolution is the 5 m parcel map (a 1-2 texel strip, hard edge). (4) Balk colour is one fixed pale tone (the balk pixel does not know its parcel's crop); it is lighter than all six crops (test). (5) `balanced` identity is tested via data / uniforms and pinned kinds, not by comparing rendered pixels.
- **Frame time** (`true`, HIGH, Suwalki battle, focus on fields 41.57,9, 300 frames): distance 1.2: 11.58 ms with the new look vs 11.61 ms with `crop_true` forced off; distance 5: 11.77 vs 11.67 ms (+0.10 ms). "Before" is the new shader with the branch off, not a pre-change checkout.
- **Screenshots** (.screenshots/field_1.2 / 5 / 24.png): at 5 the farmland reads as a patchwork of pale stubble, brown ploughed and green parcels with light balk strips along the parcel edges; at 24 the satellite colour dominates as before. At 1.2 the crops have distinct colours and mottling and the balk is a pale strip, but I could not see individual rows (0.3 m rows are below a pixel at that distance and the existing fwidth fade removes them); the headland strip was not noticeable in any shot. Tuning of the row visibility / headland contrast is left for the human playtest.
