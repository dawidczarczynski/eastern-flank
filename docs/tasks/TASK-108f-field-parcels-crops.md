# TASK-108f: Real-terrain look – regular field parcels with crop variety (rows in the terrain shader)

- **Status**: done
- **Layers**: presentation (new pure `FieldParcels` + `ParcelMap` baked parcel image, `LookPreset` farmland look data, `TerrainGround`, `assets/shaders/terrain.gdshader`, `GrassPlanner` thinning, `MapView` wiring) + docs (ARCHITECTURE, MANUAL)
- **Depends on**: TASK-108 (done), `MapScale` (exists since TASK-108e)
- **Model**: sonnet
- **Topic**: Two-layer game
- **Supersedes**: the field-strip part of TASK-108b (roads, verges, ribbons and farmyards stay there)

## Goal

Human feedback after TASK-108: "fields are not represented on the tactical map in any way. I want fields to have a regular shape – the kind of terrain need not be limited to a full hex, and a hex gets the type of terrain that occupies most of it. It should feel natural; fields can be varied (yellow grain, green corn, low plants like potatoes in rows)." So on imported real-terrain maps (`suwalki_battle`, the contact layer `suwalki_tactical`) farmland is drawn as a patchwork of straight-edged rectangular parcels, each with its own crop and visible rows, independent of the hex borders. The importer (majority rule per hex), the rules and the hex mechanics are untouched; the default battle (no FIELDS) looks pixel-identical.

## Design

- **Pure `FieldParcels`** (metres via `MapScale.metres_per_unit`, deterministic integer hash, never `GameState.rng`): 1.5 km regions with one orientation each (rows along x or z), parallel strips of 80-250 m (last strip takes the remainder), up to 1.5 km long, 20 % cut in two along the length (at 450-1050 m) – revised after the first playtest, which found 40-120 m parcels far too chopped up, a 5 m **balk** (hedgerow strip) along the first 5 m of every strip. One crop per parcel from the look shares.
- **Majority rule**: strips are judged in pieces of at most 200 m: a piece is farmland when at least half of its lattice samples (40 m) lie on FIELDS tiles, so a strip stops where the farmland does, so it spills over neighbouring plains / hills and a field hex partly under forest or village stays mostly field. Pixels whose own tile is FOREST, WATER, URBAN or MARSH are never painted (scanline-cleared per hex). Road / river links do **not** clear a tile (decision: a cleared whole hex would show the hex outline again; the road ribbon is drawn over the parcel and its verge fades into it). The shader also fades parcels out on ground steeper than the grass limit (`GrassPlanner.MAX_SLOPE`), on rock and on mud/shore.
- **Crops (look data in `LookPreset.FIELDS_DEFAULT`, a preset can override via `"fields"`)**: ripe wheat/rye (golden), maize (dark green, wide rows), potatoes/beet (mid green on dark ridges), young cereal / rapeseed (bright green), stubble (pale), ploughed (dark brown), meadow (mown-stripe green). Shares wheat 14, maize 14, potato / beet 14, young cereal 30, stubble 8, ploughed 10, meadow 10 % (mostly greens). Per crop: plant and furrow colour, row spacing in metres (7-10 m, exaggerated so rows read at the default zoom), plant width fraction, grass keep factor.
- **Baked image**: `FieldParcels.bake(grid, hex_size, rect_units)` -> `ParcelMap` (RG8, 5 m / pixel, map + backdrop margin): red = kind, green = parcel id * 2 + row orientation. Null (shader branch off, grass untouched) when the grid has no FIELDS tile. One nearest-filtered sample in the terrain shader.
- **Shader rows**: world-space stripes across the parcel's orientation; the stripe edge is filtered by `fwidth` and fades to the crop's average colour when one row spans 0.3-0.8 px (no moire when zoomed out); per-parcel brightness / hue variation and a soft patch noise.
- **Grass**: `GrassPlanner.plan_chunk(..., parcels)` multiplies the keep probability of a clump by the crop's `grass_keep` (0 on crops and ploughed soil, 0.25 on stubble, 1 on meadow and balk) after the candidate draws: RNG streams and positions elsewhere are unchanged.
- Not in this pass: 3D crop stalks near the camera (a `GrassField` kind) – the natural follow-up.

## Acceptance criteria (testable)

`test_field_parcels.gd`, `test_map_scale.gd`, `test_grass_planner.gd`:
- [x] `kind` is deterministic; crop shares over a lattice follow the look shares (± 0.09); strip median width 80-250 m, median length >= 700 m, one orientation per region; every block is tiled exactly by axis-aligned parcel rectangles; the balk is a thin strip (2-12 % of the area).
- [x] `bake`: pixel (i, j) equals `kind` at the pixel centre on an all-field map; size = rect / 5 m; null without FIELDS tiles.
- [x] Majority rule: on a half-field half-plains map the paint follows whole parcels, spills onto plains and stays mostly on the field half.
- [x] FOREST / WATER / URBAN / MARSH pixels are never painted.
- [x] Grass: no clump on crop / ploughed parcels, fewer on stubble, plain meadow parcels unchanged; maps without parcels give identical clumps.
- [x] Budget recorded in the notes.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle`. Open farmland shows as a patchwork of large straight strips, each one crop - mostly greens (young cereal, maize, potatoes), some golden grain, brown ploughed soil, pale stubble, meadow - with thin hedgerow lines between neighbours. Parcels run across hex borders (a field hex next to plains continues as a parcel), forests, villages and water stay unpainted.
2. Zoom in: rows show as stripes along each parcel, finer in detail; zoom out: rows fade into a flat colour without flicker.
3. Tall grass does not grow on crops / ploughed land; it still does on meadow parcels and between fields.
4. The default battle (no fields) looks exactly as before; also try `--quality=low`.

## Player manual

§10 "Screen": fields are drawn as a patchwork of rectangular parcels (ripe grain, maize, potatoes, young crops, stubble, ploughed soil, meadows) with rows and hedgerow strips, and do not have to follow hex borders; a hex counts as a field when most of it is. No rule changes.

## Out of scope

Roads, verges, ribbons, farmyards (TASK-108b); 3D crop stalks; real field boundaries from OSM; seasons.

## Implementation notes

Done 2026-11-09 (presentation-engineer).
- New: `src/presentation/field_parcels.gd` (pure), `parcel_map.gd` (baked RG8 image + lookup), farmland look data `LookPreset.FIELDS_DEFAULT` / `fields()`, `TerrainGround.set_parcels`, parcel branch in `assets/shaders/terrain.gdshader`, `GrassPlanner.plan_chunk(..., parcels)` thinning, `GrassField.setup(..., parcels)`, `MapView` bakes at build over the mesh + `PARCEL_MARGIN` (2 units) and wires material and grass. Tests: `test_field_parcels.gd` (10), `test_map_scale.gd`, grass test in `test_grass_planner.gd`.
- Deviations from the first brief: road / river links do not clear a tile (a cleared hex would bring the hex outline back; the ribbon covers the parcel); FIELDS splat base softened (dry grass 0.4 / dirt 0.15 / grass 0.45) so unpainted field hexes do not show a beige hex blob; the `FieldParcels` kinds are named crops, not stubble / soil / green of 108b.
- Performance (Windows D3D12, HIGH, RX 580, `SCREENSHOT_MEASURE_FRAMES=240`, 2 runs each, parcels off -> on): Suwalki default camera GPU 23.13 -> 23.21 ms (+0.08), with fields in view (`SCREENSHOT_FOCUS=41.6,9,30,24`) 17.34 -> 17.41 ms (+0.07), draw calls unchanged. Bake on `suwalki_battle` 222 ms for the first version with a 14-unit margin (Linux headless); the margin is now 2 units (smaller image), not re-measured separately. Default battle: no FIELDS tile, no image, shader branch off. LOW (Compatibility) was not verifiable: the `--linux` screenshot aborts in this environment even on the default battle ("Caller thread can't call this function"); the shader uses only fwidth / textureLod / mod, all GLES3.
- Revision 2 (human playtest: far too chopped up): regions 1.5 km, strips 80-250 m wide, per-200 m majority pieces so long strips still fit the small field clusters of Suwalki; shares rebalanced to greens; subtler row colours; brighter per-parcel tone variation. Seen in screenshots: large single-crop strips of different greens, ploughed brown and pale stubble, ending in straight cuts. Known limits: long straight edges where region orientations differ; rows are exaggerated (7-10 m) and fade to a flat colour from about 3.5 m / px; follow-up: 3D crop stalks near the camera (a `GrassField` kind).

- Revision 3 (human playtest round 3): greens muted (olive / grey-green, brightest tone darker) and shares moved to wheat 24 / maize 10 / potato 10 / young cereal 16 / stubble 15 / ploughed 16 / meadow 9 %; regions 2.5 km, strips 150-400 m x up to 2.5 km (10 % cut in two, parts >= 800 m); 150 m pieces with gaps of up to 2 pieces bridged; balk 10 m along the long edge and across both ends (region borders are hedges); no scatter on parcels: `ScatterPlanner.plan(..., parcels)` filters all kinds except on the balk, grass keep 0 on every crop (stubble too), flowers skip crop parcels, meadows keep short grass and flowers; `ScatterPlanner.plan_hedges` puts shrub / tree copses on the balk of ~50 % of strips by position hash. Tests: `test_field_scatter.gd`. Measured (HIGH, RX 580): Suwalki default camera GPU 23.02 / 23.31 ms (baseline 23.13), field view 17.11 / 17.00 ms (baseline 17.34, fewer instances); bake 102 ms on Suwalki (Linux headless, 2-unit margin). `BackdropCanopy` is not parcel-aware (it follows the border forest share).
