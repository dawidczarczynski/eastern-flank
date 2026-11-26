# TASK-217c: Crops as shader-only rows, no CPU crop planning

- **Status**: ready
- **Layers**: presentation (terrain shader, `CropLook`, `GrassPlanner` / `ScatterPlanner` crop filters)
- **Depends on**: TASK-217a (masks / keep-off textures), TASK-200 (crops, done); soft: TASK-217b
- **Sections**: ARCHITECTURE "Terrain rendering"; the ADR written by 217a; TASK-200 implementation notes; code (grep CODEMAP): `CropLook`, `CropKind`, `CropCatalog`, `ParcelMap`, `FieldParcels`, `terrain.gdshader`, `GrassPlanner` (`grass_keep`), `ScatterPlanner` (crop parcel filter)
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Farmland is drawn entirely by the terrain shader (procedural rows in real metres per parcel, plain colour far away) with zero vegetation instances, and nothing CPU-plans plants on crop parcels any more. `true` preset only; `balanced` untouched.

## Decisions (2026-11-23)

- Rows are shader-only near the camera: pattern in real metres per parcel from `CropKind` row spacing and harvest-state data; far: plain colour; NO instances.
- Remove CPU crop planning where it exists under `true`. Audit result from CODEMAP / code (the implementer re-checks): TASK-200 already draws rows in `terrain.gdshader` (row strength 1 below 50 m, 0 at 150 m); what remains CPU-side is the per-crop `grass_keep` thinning in `GrassPlanner` and the crop-parcel filter in `ScatterPlanner` (nothing stands on crop parcels). Those are replaced by the parcel keep-off mask of 217a / 217b.
- Budget: crops <= 0.2 ms GPU on RX 580 HIGH **[ASSUMPTION]** (total 1.5 ms with 217a, 217b). LOW / MEDIUM: no crop tufts (none exist) and rows may stay as plain shader colour.
- Out of scope: units, buildings, trees, seasons, balanced, game rules, animated crops.

## Acceptance criteria (testable)

- [ ] Crop rendering adds 0 MultiMesh instances under `true` (test: count instances of all vegetation layers over a fixture parcel interior = 0).
- [ ] Row spacing per `CropKind` stays 0.3-0.75 m in real metres, via `MapScale` (test every kind; same metre spacing at two `MapScale` values); the shader parameter table comes from `CropCatalog` data, not code constants.
- [ ] Row direction constant inside a parcel and the harvest-state tone per kind present in data (existing `CropLook` twin tests green, plus one new test that every kind has both).
- [ ] Row fade values come from `LookPreset` (full below 50 m, zero at 150 m, tunable, metres via `MapScale`); beyond 150 m output equals the plain parcel colour (test on the `CropLook` twin: 0 row amplitude at 150 m and 600 m).
- [ ] CPU planning removed: under `true`, `GrassPlanner` no longer reads `grass_keep` and `ScatterPlanner` no longer filters crop parcels (the keep-off mask does it); test: planners called with `true` on a parcel fixture produce no clump / bush inside a parcel interior and make 0 `FieldParcels.kind` lookups per instance (spy / count).
- [ ] `balanced` unchanged: the 12 old `kind()` values and existing grass / scatter tests green.
- [ ] LOW / MEDIUM: shader rows off beyond 50 m or plain colour only (`GraphicsQuality` value, test per level); no instance created at any level.
- [ ] Frame cost: a benchmark scene note in Implementation notes with ms of crop shader term on vs off (TASK-200 measured +0.10 ms; must stay <= 0.2 ms).

## Playtest (for the human)

1. `true`, HIGH, over fields at 5-30 m: rows visible per crop with right spacing, harvest tones, parcel edges clear; no tufts or clumps inside parcels.
2. Raise the camera to 150 m and beyond: rows fade without moire; far fields plain colour; no pop.
3. Jump 2 km onto fields: they look right at once (no loading).
4. FPS 60; crops on vs off <= 0.2 ms on RX 580. LOW / MEDIUM: plain colour, faster. `balanced`: as before.

## Player manual

None (internal; appearance of fields unchanged except by TASK-200). A graphics-quality line, if 217a already added one, needs no edit.

## GDD

No change (cosmetic).

## Out of scope

- Shrubs (217a), grass (217b), animated crops, seasons, balanced preset, game rules.

## Implementation notes

_Filled in by the agent when done._
