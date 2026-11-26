# TASK-217d: Standing grain, maize and rapeseed on field parcels (GPU vegetation layer)

- **Status**: ready
- **Layers**: presentation (new `GpuVegetationLayer` crop layer, shader, `CropCatalog` data, `LookPreset`, `GraphicsQuality`)
- **Depends on**: TASK-217a, TASK-217c (crop rows and parcel masks), TASK-200; needs the human's pick of a design variant (`/design-ui`)
- **Sections**: ADR 0033 (GPU vegetation framework); code (grep CODEMAP): `GpuVegetationLayer`, `GpuGrassField`, `ShrubField`, `grass_rules.gdshaderinc`, `CropCatalog`, `CropKind`, `CropLook`, `ParcelMap`
- **Model**: sonnet
- **Tags**: battle-look

## Goal

On crop parcels, close to the camera, tall crops stand as real 3D plants instead of only shader rows: wheat / rye / barley (ears and stalks), maize (leaves, cobs), rapeseed (yellow flowers), maybe potatoes / sugar beet (low leaf rosettes). Placed by the GPU in the same framework as grass and shrubs: hash of the cell, no CPU plan, no instance data. `true` preset only; HIGH only (LOW keeps shader rows).

## Decisions

- Same technique as TASK-217b: an `instant` `GpuVegetationLayer` around the camera (**[ASSUMPTION]** ring 25-40 m, fading by thinning); beyond it TASK-217c's shader rows and plain colour stay (so there is no pop: the row texture and the plant cards share colour and row direction).
- Plants stand **in the rows** of the parcel (row direction and spacing from `CropKind` / `CropLook`, the shader already has them), height and harvest state per `CropKind` from `CropCatalog` data (new fields: plant height range in metres, mesh kind, density per m of row). Balance data lives in resources, not constants.
- Cards or small meshes: a 2-3 crossed-quad stalk cluster with an ear / leaf texture per kind; maize taller (2-2.5 m) with leaves, rapeseed with a flower tone. Mesh and look follow the variant picked from `/design-ui` (no mockup exists: run it first).
- The parcel interior comes from the existing crop mask (TASK-217c); the keep-off mask keeps plants off paths, headlands and balks.
- Tractor lanes (tramlines) every N rows are left empty - a cheap realism cue.
- GDScript reference of the hash for tests (CLAUDE.md rule). Wind: a vertex sway shared with the grass if one exists.
- Budget **[ASSUMPTION]**: <= 0.6 ms GPU on the RX 580 (HIGH, field at 5-30 m), total with grass and shrubs still 60 FPS; thinning by distance bounds the vertex count.

## Acceptance criteria (testable)

- [ ] 0 CPU plan ms and 0 per-instance data under `true` (test on `ChunkManager.stats()`).
- [ ] Reference / shader twin: fixed-value test for a set of cells (position inside a row, height in the kind's range, tramline cells empty).
- [ ] Per-kind data in `CropCatalog` (height range, mesh kind, density), every crop kind has it (test); rows spacing 0.3-0.75 m unchanged.
- [ ] Plants only inside parcel interiors: none on paths, balks, headlands, roads (test with the parcel fixture).
- [ ] 2 km jump onto fields: plants within the ring exist after the first frame.
- [ ] LOW: no plants, shader rows as in TASK-217c; `balanced` unchanged.
- [ ] Frame cost measured (`tools/perf.sh`) and written in Implementation notes.

## Playtest (for the human)

1. Over fields at 3-30 m: each crop looks like itself (wheat, maize, rapeseed), plants stand in rows, tramlines visible.
2. Walk the camera from 100 m down to 3 m: plants thin in smoothly, no pop; far fields keep their row colour.
3. A tank / infantry model standing in a field is not buried or floating.
4. FPS 60.

## Player manual

None (cosmetic).

## GDD

No change.

## Out of scope

- Animated harvest, seasons, units flattening crops (a possible follow-up), balanced preset, game rules.

## Implementation notes

(empty). First step: `/design-ui` for the plant look (2-3 variants), then implementation.
