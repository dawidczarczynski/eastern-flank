# TASK-108b: Real-terrain look v2 – field and soil ground layers, real-size field strips, real-width roads with verges

- **Status**: ready
- **Layers**: presentation (new pure `MapScale`, new pure `FieldParcels` + baked parcel texture, `TerrainSplat`, `TerrainTextures`, `TerrainGround`, `assets/shaders/terrain.gdshader`, new road shader, `FeatureRibbonPlanner` widths + mesh attribute, `GrassPlanner` density) + assets (two CC0 ground sets, `credits.json`) + docs (ARCHITECTURE, MANUAL)
- **Depends on**: TASK-108 (done) (soft: TASK-110 – realistic scale; priority: after the operational core loop 092 → 094 → 095)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

On a real-terrain map, farmland and roads have their real sizes: fields are a patchwork of real 20–50 m strips (harvested stubble, ploughed soil, green crop), as in the Polish countryside, and roads are real 5 m carriageways with worn verges, not 14 m grey lines. This uses the two splat channels (`ARRAY_CUSTOM0.zw`) reserved since TASK-055. The default battle (no fields, no roads) looks exactly as before. First of four look tasks (108b ground and roads, 108c river and bridges, 108d village buildings, 108e reeds), each with its own frame budget.

## Scale (decided 2026-10-31: everything at real size)

- **Every dimension in 108b–108e is given in metres** and converted with one constant, **`MapScale.metres_per_unit`** (new pure static `src/presentation/map_scale.gd`, introduced by whichever of TASK-110 / 108b / 108d / 108e lands first, reused by the others): on an imported map it is `ImportedMap.metres_per_world_unit()` (`hex_spacing_m / √3` = **144.3 m** on Suwałki); on generated maps `MapScale.DEFAULT_METRES_PER_UNIT` = 250 / √3 (the same 250 m tactical hex – GDD Map, decided 2026-10-31). `MapView` sets it before building. No look constant of these tasks is a raw world-unit number any more.
- The rest of the presentation is **not** at real scale yet: unit models are ~12× too large (0.0858 units/m vs. 0.0069 units/m true), trees ~3.7× too tall, ground textures repeat as if 1 unit were 7.7 m (`TerrainGround.METRES_PER_UNIT`). Making those real is **TASK-110** (study) and its follow-ups, with **TASK-111** adding fixed-pixel unit markers and a much closer camera (decided 2026-10-31: real-size units, no enlarged-unit compromise), not this task. Until then the new features look small next to the units – expected. These tasks don't need TASK-110 / 111 to be correct, because they only read `MapScale` (recommended: do TASK-110 first, it is a soft dependency).
- **Smallest visible feature – two limits:**
  1. *Terrain mesh*: 4 vertices per world unit = one vertex every **36 m** on Suwałki, and `TerrainSplat.smooth` blurs over one more step, so per-vertex splat weights cannot show anything narrower than about **70 m**. So the 20–50 m strips and the 2–3 m verges cannot be splat weights: strips come from a **per-pixel parcel texture**, and verges are part of the **road ribbon mesh**.
  2. *Screen*: camera FOV 40°, 720 px high → about 989 / distance px per unit: **1 px ≈ 1.0 m** at the closest zoom (7), **3.5 m** at the default (24), **6.7 m** fully zoomed out (46). A 5 m road is ~1.4 px at the default zoom and less than a pixel zoomed out, so it shimmers. Ribbons therefore get a **minimum on-screen width of 1.5 px** (vertex shader widens the strip across, never narrower than the true width) – decided by the human 2026-10-31 (GDD Open questions "Realistic scale"). Once TASK-111 lets the camera go down to ~58 m, 1 px is ~0.1 m there and roads show their true width.

## Design

### Two new ground layers (assets)

- Layer **6 `stubble`** (harvested cereal field / dry crop) and layer **7 `soil`** (ploughed or bare farm soil): CC0 PBR sets from ambientCG or Poly Haven (albedo, normal_gl, roughness, ao, height; 1024² JPG like the other six) at `assets/third_party/textures/ground/stubble/` and `.../soil/`, manifest ids `ground_stubble` / `ground_soil` in `credits.json` (ADR 0011). Prefer sets without strong rows. Their repeat follows today's `TerrainGround.METRES_PER_UNIT` convention like the other six (TASK-110 changes all eight together).
- `TerrainTextures.LAYERS` gets `"stubble", "soil"` **appended** (0–5 unchanged); `SOURCE_METRES`, `TerrainGround.LAYER_TINTS` and the shader arrays grow to 8; `TerrainSplat.LAYER_COUNT` = 8, `STUBBLE := 6`, `SOIL := 7`.
- **Splat channels**: `CUSTOM0.z` = **field** weight (how much of the vertex is farmland – the shader splits it per pixel into stubble / soil / green crop by the parcel texture), `CUSTOM0.w` = **soil** weight (farmyards). So `weights()` keeps returning per-layer weights for tests, with the FIELDS share reported in layer `STUBBLE` before the per-pixel split; document the mapping in `TerrainGround.add_surface`.

### Field parcels (pure `FieldParcels` + baked texture)

- `FieldParcels.kind(x_m: float, z_m: float) -> int` in **metres** (world position × `metres_per_unit`) returns `STUBBLE`, `SOIL` or `GREEN`; deterministic integer hash, no RNG object, never `GameState.rng`:
  - square **blocks of 300 × 300 m**, orientation per block by hash (strips along x or z, 50 / 50);
  - strips across the orientation, hashed width **20–50 m** (the last strip of a block takes the rest, ≥ 10 m);
  - kind per strip: **stubble 45 %, soil 30 %, green 25 %**.
- `FieldParcels.bake(rect_m: Rect2, metres_per_pixel := 5.0) -> Image` (R8, kind per pixel) covering the playable map plus the backdrop margin; Suwałki ≈ 1 600 × 1 100 px (~1.8 MB). The terrain shader samples it (nearest, with a 1-pixel blend at strip borders) and splits the per-vertex field weight per pixel: STUBBLE → stubble 0.8 + dry_grass 0.2; SOIL → soil 0.85 + dirt 0.15; GREEN → grass 0.6 + dry_grass 0.4. Not built (and the shader branch off) when the map has no FIELDS tile.
- `TerrainSplat` FIELDS base: field 1.0 (then slope / shore rules as today). **URBAN base**: gravel 0.40, soil 0.30, grass 0.30.
- **Grass on fields** (`GrassPlanner`, pure): density × 0.4 on STUBBLE, × 0.1 on SOIL, × 0.8 on GREEN of the plains density, by `FieldParcels.kind` at the clump position; thinning by hash after the candidate draws (RNG streams and non-field positions unchanged).

### Roads at real width (ribbon mesh with verges)

- One road look for all rule roads (no class data): **carriageway 5.0 m** + **verge 2.5 m** on each side = 10 m ribbon (Suwałki: 0.069 units instead of 0.10). Junction / dead-end discs scale the same. `FeatureRibbonPlanner` takes widths from `MapScale` (metres constants `ROAD_CARRIAGEWAY_M`, `ROAD_VERGE_M`); the scatter clearance becomes ribbon half width + **3 m**.
- `FeatureRibbonPlanner.mesh` additionally returns `across: PackedFloat32Array` per point (−1 / +1 on the outer verge edges, 0 on the centreline; discs 0 at the centre, 1 on the rim), stored in `ARRAY_TEX_UV.y` (`UV.x` is left for TASK-108c's flow coordinate). The across value at the carriageway edge is `carriageway / (carriageway + 2 · verge)` = 0.5.
- `assets/shaders/road.gdshader` (roads only; rivers keep their material until TASK-108c): world-space samples of the `TerrainTextures` arrays at the terrain's `layer_repeat`; carriageway (`|across|` ≤ 0.5) gravel (layer 4) with two darker **wheel ruts** (soil) at `|across|` ≈ 0.25; verge (0.5–1.0) soil + dry grass, alpha fading from 1 at 0.6 to 0 at 1.0 into the terrain. **Minimum on-screen width 1.5 px** (vertex shader pushes the strip vertices outwards along their across direction when the projected width is smaller; needs the across direction as a second attribute – implementer's choice, e.g. `CUSTOM0`). Roughness 1, no shadows. Must compile on the Compatibility renderer (LOW on WSLg).

### Quality and performance

- LOW: same layers at 512² (`terrain_texture_size`), same parcels, roads and min width. No new switch.
- The terrain shader now blends up to 8 layers plus the parcel lookup: skip layers below weight 0.004 (measured).
- Budget (Windows D3D12, HIGH, default camera, `SCREENSHOT_MEASURE_FRAMES=240`, median of 3, before → after): **Suwałki ≤ +0.5 ms** GPU, **default battle ≤ +0.3 ms**; draw calls unchanged. `MapView.build` on `suwalki_battle` ≤ +0.2 s (parcel bake), default battle ≤ +0.05 s.
- Reaching 60 FPS on Suwałki is **not** this task's job (decided 2026-10-31: "don't make it worse" budgets; GDD Open questions).

## Acceptance criteria (testable)

`test_terrain_splat.gd`, new `test_map_scale.gd`, new `test_field_parcels.gd`, `test_feature_ribbon*.gd`, grass planner tests, `test_third_party_assets.gd`:
- [ ] `MapScale.metres_per_unit` = 144.34 (± 0.01) for the Suwałki scenario and 250 / √3 for generated maps; changing it rescales every 108b dimension (a test with 72.17 m / unit gets road ribbons twice as wide in world units).
- [ ] `TerrainSplat.LAYER_COUNT` = 8; `TerrainTextures.LAYERS` = `["grass", "dry_grass", "dirt", "mud", "gravel", "rock", "stubble", "soil"]`; both new sets exist and are credited.
- [ ] `weights()` for every `Terrain.Type` returns 8 values ≥ 0 summing to 1 (± 1e-4); flat FIELDS → field share ≥ 0.9; flat URBAN → gravel ≥ 0.35 and soil ≥ 0.25; PLAINS, FOREST, HILLS, WATER, MARSH → layers 6 and 7 exactly 0 and layers 0–5 equal to the TASK-108 values (± 1e-6).
- [ ] `FieldParcels.kind` is deterministic; over a 3 km × 3 km lattice sampled every 5 m the shares are stubble 0.35–0.55, soil 0.20–0.40, green 0.15–0.35; walking across strips, kind changes are never closer than 10 m apart and the median run is 20–50 m; walking 100 m along a strip keeps the kind in ≥ 90 % of samples.
- [ ] `FieldParcels.bake` of a 1 km × 0.5 km rect at 5 m / px is 200 × 100 px and pixel (i, j) equals `kind` at the pixel centre; no texture is built for a grid without FIELDS.
- [ ] `TerrainGround.add_surface` stores the field weight in `CUSTOM0.z` and soil in `.w` (± 1e-6); layers 4–5 still in `.x` / `.y`.
- [ ] Road ribbon on Suwałki scale: a straight road's strip is 10 m ± 0.1 m wide (0.0693 units); `across` has one value per point in [−1, 1], ±1 with opposite signs on the two edges of every cross-section, 0 on disc centres; the carriageway edge lies at |across| = 0.5.
- [ ] Scatter clearance: on a hand-made grid with a road, no tree, rock, bush or grass instance lies within ribbon half width + 3 m of a road centreline.
- [ ] Grass on fields: per parcel kind, accepted clump counts relative to plains: SOIL ≤ 0.15, STUBBLE 0.3–0.5, GREEN 0.7–0.9; positions on plains/forest chunks identical before and after.
- [ ] Before/after frame and build times (both maps) recorded in the notes; within budget or explained.
- [ ] Screenshots Read by the agent (`SCREENSHOT_SCENARIO=suwalki_battle tools/screenshot.sh --windows`, default view and a close-up at camera distance 7 with `SCREENSHOT_FOCUS`): field hexes show narrow strips of at least two tones; roads are thin continuous lines with no shimmer gaps at the default zoom, and at the close-up a gravel carriageway with ruts and soft verges; `docs/images/suwalki_battle.png` re-rendered; `tools/readme_screenshot.sh` (default battle) unchanged in content.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle`. Farmland should read as a patchwork of narrow strips – pale stubble, dark ploughed soil, some green – similar to an aerial photo of the Suwałki region.
2. Roads are now much thinner (real 5 m roads with verges): zoom in fully on one – gravel carriageway, two darker ruts, earthy verges fading into the grass. Zoom out: roads stay visible as continuous thin lines, no flicker.
3. Villages look like farmyards (gravel and bare soil mixed with grass).
4. The normal battle looks exactly as before.
5. Frame rate on HIGH on both maps: no visible drop; once on LOW (`--quality=low`): strips and roads still there.
6. Note how the units look next to the real-size roads and fields (they are still oversized until TASK-110).

## Player manual

§10 "Screen" → "Roads and rivers": fields appear as a patchwork of narrow strips (stubble, ploughed soil, green crops), villages as farmyards of gravel and soil, roads as narrow gravel roads with wheel ruts and grassy-earth verges, drawn at their real width (they never get thinner than about a pixel and a half, so they stay visible when zoomed out). Replace "Fields look stubbly and khaki, villages gravelly". Keep "(Houses, bridges and a proper river look come later.)" until 108c / 108d are done. No rule changes.

## Out of scope

- Real scale of units, trees, grass, textures and the camera (TASK-110).
- River look, banks and bridges (TASK-108c), village buildings (TASK-108d), reeds (TASK-108e).
- Road classes / surfaces and real field boundaries from OSM (procedural first – GDD Open questions, decided 2026-10-31); seasonal looks.
- Any rule change; generated maps' look.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
