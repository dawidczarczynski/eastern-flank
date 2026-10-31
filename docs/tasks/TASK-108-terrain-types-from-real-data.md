# TASK-108: Terrain types from real data – fields, urban, marsh, roads (cost 1), rivers (+1 to enter): rules, importer, basic look

- **Status**: done
- **Layers**: core (terrain types, `HexGrid` step cost, `ImportedMap`, `Scenario`) + data (`data/terrain/*.tres`, regenerated `data/maps/suwalki.tres`) + tools (`tools/import_map.py`, Python, offline) + presentation (splat weights, scatter rules, flat road/river ribbons, terrain card) + docs (ADR, ARCHITECTURE, MANUAL)
- **Depends on**: TASK-087 (done)
- **Model**: opus (edge-dependent pathfinding, polyline → hex-link rasterisation, byte-deterministic re-import, many touch points)

## Goal

On a real-terrain map the player meets the ground as it is: villages are strongpoints, marshes slow and expose, roads speed columns through forest and hills, and rivers cost time to cross unless there is a bridge. The importer already stores the land cover per hex (ADR 0018, `cover_rows`) and has roads and waterways in its cache; this task turns them into rules, regenerates the Suwałki map and draws them simply. Replaces TASK-035. The random-map default battle is unchanged.

## Design

### New terrain types (data, `data/terrain/*.tres`)

| Terrain | Map char | Move cost | Defense bonus | `default_elevation` | Blocks sight (planned, TASK-007 – no field yet) |
|---|---|---|---|---|---|
| Plains (existing) | P | 1 | 0 | 0.2 | no |
| **Fields** | **A** | **1** | **0** | **0.2** | no |
| **Urban** | **U** | **1** | **+2** | **0.2** | yes |
| **Marsh** | **M** | **2** | **0** | **0.1** | no |
| Forest (existing) | F | 2 | +1 | 0.25 | yes |
| Hills (existing) | H | 2 | +2 | 0.9 | yes (from behind) |
| Water (existing) | W | impassable | – | −0.3 | no |

Rationale:
- **Fields** have the plains rules on purpose: open, cost 1, no cover. They differ in look and are the hook for later rules (concealment under fog of war, seasonal mud) – GDD Open questions. A "small defense bonus" (old GDD idea) would equal forest with the coarse integer bands (GDD "Stat derivation rules" principle 4).
- **Urban** = streets (cost 1) and buildings (+2, as hills). +3 would push most matchups to the minimum damage of 1 (GDD "Damage scale"); recorded as an open question.
- **Marsh** = slow (2) and exposed (0): the worst ground to fight on. Cost 3 was rejected because of the invariant below.
- **Invariant**: the most expensive passable step (cost 2 + river 1 = 3) never exceeds the smallest unit movement in `data/units/*.tres` (3: infantry, MLRS), so every passable hex can be entered by every unit from a full move.
- `Terrain.Type` gets `FIELDS, URBAN, MARSH` **appended** (`PLAINS, FOREST, HILLS, WATER, FIELDS, URBAN, MARSH`) so existing int values stay; `_PATHS` lists the three new files. Display names "Fields", "Urban", "Marsh" (pl: "Pola", "Zabudowa", "Bagno") in `assets/i18n/strings.csv`.
- `MapGenerator` never produces the new types and no generated map has roads or rivers: the default, objective and command-points battles are unchanged.

### Roads and rivers: links per hex side, roads apply per link, rivers per hex

Both are stored the same way: per tile a **6-bit link mask**, bit `i` = a link towards `tile + Hex.DIRECTIONS[i]` (the line runs from this tile's centre across that side into the neighbour). This is the simplest data that both draws continuous lines and gives roads a per-edge rule:

- **Road rule – per link**: a step from A to B costs `road_move_cost` (1) when A has a road link towards B, whatever B's terrain (impassable B stays impassable). Otherwise the normal cost. A per-hex "road hex" flag was rejected: two parallel roads in neighbouring hexes (common in villages at 250 m) would give a free sideways step between them, and the importer would lose which way a road leaves a hex.
- **River rule – per hex**: a tile with at least one river link is a **river hex**; entering it costs `river_extra_cost` (+1) on top of its terrain cost, unless the step follows a road link (a bridge). Leaving costs nothing extra. Per-edge rivers (Civ-style rivers along hex sides) were rejected: an OSM river is a line through hex interiors, and turning it into a chain of hex sides is ill-defined; "+1 to enter a river hex" is the GDD idea and works with the per-tile Dijkstra unchanged except for the step function.
- Numbers live in **`data/terrain/features.tres`** (new `TerrainFeatures` resource, `src/core/data/terrain_features.gd`): `road_move_cost = 1`, `river_extra_cost = 1`; loaded once and cached by `Terrain.features()` like the definitions.
- **Storage rule (symmetry)**: a link between two land tiles is stored on both; a link from a land tile towards a water tile or off the map is stored on the land side only (it is drawn to the shared side, has no rule effect); a water tile has no links. `ImportedMap.problem()` enforces this.
- **Encoding in `ImportedMap`**: `road_rows` and `river_rows` (`PackedStringArray`, one char per tile, like `terrain_rows`), char = `LINK_CHARS[mask]` with `LINK_CHARS = ".123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ#@"` (64 chars, `.` = no link). Both arrays may be empty (no roads / rivers – the existing sample fixture stays valid until regenerated).

### Core

- `HexGrid`: `set_road_links(c, mask)`, `road_links(c) -> int` (0 by default), `has_road(a, b) -> bool`, `set_river_links(c, mask)`, `river_links(c) -> int`, `is_river(c) -> bool`, and **`step_cost(from, to) -> int`**: `IMPASSABLE` if `to` is off the map or impassable; `road_move_cost` if `has_road(from, to)`; else `move_cost(to) + (river_extra_cost if is_river(to) else 0)`. `_search` (and so `reachable`, `path_to`, `MoveUnitCommand`, the AI, path preview and the terrain card path cost) uses `step_cost`. `move_cost(c)` stays the terrain cost (terrain card).
- `ImportedMap`: `TERRAIN_CHARS` gains `A`, `U`, `M`; `road_rows`, `river_rows`, `LINK_CHARS`; `problem()` checks row count/width, valid chars, symmetry and no links on water; `to_grid()` sets the masks.
- `Scenario._deployment_tiles`: free **plains or fields** tiles (both cost 1, defense 0) – plains alone may become scarce once fields are split off.
- AI: no code change needed beyond `step_cost` (it plans with `reachable`). No road-preference heuristic, no defensive-terrain seeking (out of scope).
- `docs/ARCHITECTURE.md`: `HexGrid.step_cost`, link masks, `TerrainFeatures`. No new events. ADR (next free number, e.g. 0019): per-link roads / per-hex rivers, link encoding, classification precedence – extends ADR 0018.

### Importer (`tools/import_map.py`)

- **Terrain per hex**, in this order (first match wins; shares = share of the hex's ~70 sample points):
  1. water group dominant → **W**; forest group dominant → **F** (rules of ADR 0018 unchanged);
  2. urban (`U`) share ≥ **0.20** (`--urban-share`) → **U** (a village core ≈ 1 ha of the 5.4 ha hex; the Suwałki sample has **no** hex where urban is the dominant class – villages are small);
  3. marsh (`M`) share ≥ **0.25** (`--marsh-share`) → **M**;
  4. relief ≥ `--hills-relief` (15 m) → **H**;
  5. dominant open class (`cover_rows` char) is `A` → **A** (fields);
  6. else **P** (grass, unmapped `.` – see Open questions).
  Precedence reasons: urban matters most for combat and its buildings distort the DSM relief anyway (relief already ignores urban points); marshes are flat by nature; a ploughed moraine hill is still a hill.
- **Road classes** (rule roads): `highway=motorway, trunk, primary, secondary, tertiary, unclassified, residential` (+ their `_link` variants if present in the cache). `track` is **not** a road (dense field/forest tracks would erase forest's cost; open question). **River classes**: `waterway=river, canal`, and `stream` only with a `name` tag; `ditch`/`drain` and unnamed streams ignored. Rivers mapped as areas are water already (unchanged).
- **Line → links**: each way (processed sorted by (kind, id)) is projected to UTM, densified every **10 m**, and each sample mapped to its tile (also off the map – a new unbounded `tile_at`). Consecutive tile runs give links between consecutive distinct tiles (always neighbours at 10 m steps). **Corner-clip smoothing**: a run shorter than **40 m** (`CLIP_M`) whose previous and next tiles are neighbours (or the same tile) is dropped, so a road that grazes a hex corner does not make a detour through it. Then the storage rule above (no bits on water tiles, land→water / land→off-map only on the land side). Bit order mirrors `Hex.DIRECTIONS` on the axial coordinates of `MapGenerator.offset_to_axial`.
- `write_tres` writes `road_rows` and `river_rows` after `cover_rows`; byte-deterministic as before.
- Overpass query unchanged (it already fetches `highway` and `waterway`). **Regenerate `data/maps/suwalki.tres` offline from the existing cache** (`--offline`, the rebuild command in `data/maps/CREDITS`); if the cache is missing, stop and ask the human – a re-download would give today's OSM. Update CREDITS (date of the re-import, same inputs), regenerate the synthetic fixtures (`--make-fixtures`) and the golden `tests/fixtures/maps/sample_map.tres`.

### Presentation (basic look – the realistic look is TASK-108b)

- **Splat** (`TerrainSplat.weights`, existing 6 layers, new named constants): FIELDS base = dry_grass 0.5, dirt 0.3, grass 0.2 (stubble); URBAN base = gravel 0.5, dirt 0.3, grass 0.2 (yards, lanes); MARSH base = grass 0.55, mud 0.45 (wet meadow). Slope rock and shore mud rules apply on top as for plains. The two free `ARRAY_CUSTOM0` channels stay free for TASK-108b.
- **Scatter / grass**: FIELDS like plains with grass density × 0.6 and no flower clusters; MARSH like plains, no rocks, no flower clusters; URBAN no trees, no rocks, grass density × 0.3. `MotionEffects.dust_color`: fields/urban → plains dust; marsh → the mud spatter colour with rate × 0.4 (as the shore). Every other `Terrain.Type` switch in `src/presentation/` handles the new values (default: plains look).
- **Road and river ribbons**: a pure planner (e.g. `FeatureRibbonPlanner`) turns the link masks into half-segments from each tile centre to the midpoint of the linked side (distance √3/2 · `HEX_SIZE` = 0.866), plus a small centre disc so junctions have no gaps. The view builds **one** `MeshInstance3D` per kind (2 draw calls in total), a flat strip draped on `TerrainSurface` height + 0.02: road width **0.10** units, colour `#8a7f6a`, roughness 1; river width **0.14** units, colour `#3d5a66`, slight specular. No mesh is created when the grid has no links (default battle). Look values are presentation constants (or `LookPreset`), not balance data.
- Trees, rocks and grass are not placed within ribbon half-width + **0.04** of a segment.
- **Terrain card** (`TerrainPanelModel` tags): `Road` when the tile has any road link, `River +1` on a river hex (pl: "Droga", "Rzeka +1"). Name, move cost and defense come from the definition as today.
- **Performance** (60 FPS budget, Suwałki 720 hexes): only two extra meshes and fewer scatter instances; record `MapView.build` time on `suwalki_battle` before/after (budget +0.2 s) and the time of `tools/simulate.sh 20 --scenario=suwalki_battle` before/after (budget +20 %).

## Acceptance criteria (testable)

Core – `tests/unit/test_terrain.gd`, `test_hex_grid.gd`, `test_move_path.gd`, `test_ai_player.gd`, `test_combat*` / forecast tests (hand-made grids):
- [x] `Terrain.definition()` loads all 7 types; fields 1 / 0, urban 1 / +2, marsh 2 / 0, none impassable; `Terrain.features()` has road 1, river +1. The old four are unchanged.
- [x] Invariant: for every passable type, `move_cost + river_extra_cost` ≤ the smallest `move` over `data/units/*.tres` (3 today).
- [x] `step_cost`: A plains – B forest neighbours: 2 without a link, **1** with a road link A→B; B urban: 1; B marsh: 2.
- [x] No leakage: A and C neighbours, both with road links to other tiles but not to each other, C forest → `step_cost(A, C)` = 2.
- [x] River: entering a plains river hex = 2, forest river hex = 3, marsh river hex = 3, a river hex along a road link = 1, leaving a river hex onto plains = 1, river hex → river hex (no road) = terrain + 1.
- [x] A road link towards a water tile or off the map does not make it passable (`IMPASSABLE`).
- [x] `path_to` takes the road: road around a forest (3 steps, cost 3) beats the straight way through 2 forest hexes (cost 4) for a budget of 5; `reachable` with budget 3 along a road through forest reaches 3 hexes (1 + 1 + 1) instead of 1.
- [x] `MoveUnitCommand` spends the road/river cost from `moves_left` (e.g. move 3 infantry: road through forest 3 hexes → 0 left; crossing a plains river hex then plains → 3).
- [x] AI: in a hand-made battle where a tank can reach 2 hexes nearer the enemy only via a road through forest, the AI's move ends on that hex.
- [x] Combat: Abrams (attack 7) vs. infantry (defense 3) – `compute_damage` = 2 on urban, 4 on fields, 4 on marsh; the forecast and the unit card show defense `5 (3+2)` on urban.
- [x] Generated maps: every tile of `MapGenerator` grids (seeds 1–20) has road and river mask 0; the default battle's `tools/simulate.sh 50 --seed=1` summary is identical before and after; existing replay tests pass.

`ImportedMap` / scenario – `test_imported_map.gd`, `test_real_map_battle.gd`, `test_scenario.gd`:
- [x] Rows with `A`, `U`, `M` load as FIELDS / URBAN / MARSH; `LINK_CHARS` has 64 unique chars, `.` = 0, `@` = 63.
- [x] `road_rows` / `river_rows` decode to the masks set on the grid (fixture with a known road and river); empty arrays → no links and `problem()` == "".
- [x] `problem()` non-empty for: wrong row count or width, unknown link char, a land–land link stored on one side only, any link bit on a water tile.
- [x] `suwalki.tres`: compared to the TASK-087 version (copy the old arrays into the test as a reference or compare counts): the positions of `F` and `W` tiles and the `elevation` / `elevation_m` arrays are identical; every former `P`/`H` is now one of `P`, `H`, `A`, `U`, `M`; the map has ≥ 1 road link and ≥ 1 river hex.
- [x] `suwalki_battle`: every company stands on a plains or fields tile, no two on one tile; the battle runs to the end in `tools/simulate.sh 5 --scenario=suwalki_battle`.

Importer – `tools/test_import_map.py` (run by `tools/check.sh`):
- [x] Classification from point counts (70 points): urban 20 % + fields 50 % → U; urban 19 % + fields 50 % → A; forest 60 % + urban 30 % → F; marsh 25 % → M; urban 20 % on a 20 m-relief hex → U; fields-dominant on a 20 m-relief hex → H; unmapped/grass-dominant flat → P.
- [x] A straight road through three tiles gives the links A–B and B–C stored on both sides; one test per direction checks the bit index against the `Hex.DIRECTIONS` order.
- [x] Corner clip: a line inside a tile for < 40 m between two neighbouring tiles creates no link to it; ≥ 40 m creates both links.
- [x] A line leaving the map sets the bit on the edge tile only; a line into a water tile sets the bit on the land side only.
- [x] `highway=track` and an unnamed `waterway=stream` give no links; a named stream does.
- [x] Same input → byte-identical `.tres` (fixtures); golden file regenerated; the real Suwałki re-import run twice offline is `cmp`-identical (record in the notes).

Presentation – `test_terrain_splat.gd`, `test_terrain_panel_model.gd`, scatter/grass planner tests, a ribbon planner test:
- [x] `weights()` for every `Terrain.Type` returns 6 values ≥ 0 summing to 1 (±1e-4); flat (slope 0, height 0.3, macro 0.5): fields dry_grass ≥ 0.4, urban gravel ≥ 0.4, marsh mud ≥ 0.35 and grass ≥ 0.3.
- [x] Terrain card: a tile with a road link has tag `Road`; a river hex `River +1`; urban shows `Urban`, move `1`, defense `+2`; marsh `2`, `+0`.
- [x] Ribbon planner: a tile with links in directions 0 and 3 gives 2 half-segments of length 0.866 from the centre; an off-map link gives a segment to the border side midpoint; a grid without links gives 0 segments, and `MapView` then creates no ribbon mesh.
- [x] Scatter: an urban tile gets 0 trees and 0 rocks; on a hand-made grid with a road no tree, rock or grass instance lies closer than ribbon half-width + 0.04 to a road segment.
- [x] `MotionEffects.dust_color` returns the plains dust for fields/urban and the mud colour for marsh.
- [x] Build time and simulation time before/after recorded in the notes; within budget or explained.
- [x] Screenshot `SCREENSHOT_SCENARIO=suwalki_battle tools/screenshot.sh` (Windows build) Read by the agent: roads and the river are visible as continuous lines, villages and fields read differently from meadows; `docs/images/suwalki_battle.png` re-rendered. `docs/images/gameplay.png` (default battle) re-rendered and unchanged in content.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle` (or the main-menu scenario select). Roads show as thin grey-brown lines, the river(s) as thin blue-grey lines, both continuous across hexes and to the map edge. Compare with a real map of Szurpiły: villages (Szurpiły, Jeleniewo side) are urban hexes, field patches look stubbly/khaki, the few marsh hexes look wet and dark.
2. Hover hexes: the terrain card shows Fields / Urban / Marsh with their cost and defense, and the tags `Road` / `River +1`.
3. Select a tank next to a road leading into forest or hills: the reach outline stretches along the road much farther than across the forest; the path dots follow the road; the path cost shows 1 per road hex.
4. Select infantry next to a river hex without a bridge: entering it shows cost 2 (plains) in the path row; where a road crosses the river the cost stays 1.
5. Attack a unit standing in a village: the target tag shows less damage than on open ground (same as on hills).
6. Watch the AI: its columns use roads when they get it closer.
7. Play the normal battle: nothing has changed (same map, same results).
8. Check the frame rate on HIGH on the Suwałki map (should stay at 60) and the start-up time.

## Player manual

- §5 "The map and terrain": extend the terrain table with Fields (1, +0), Urban (1, +2), Marsh (2, +0); add **Roads** (moving along a road from one hex to the next costs 1, whatever the terrain; only along the road – a road in the next hex does not help) and **Rivers** (entering a hex with a river costs 1 more; no extra cost where a road crosses it – a bridge; leaving is free; you can still move along a river, paying +1 each hex); note that the most expensive step is 3, so every unit can always enter any hex that is not water from a full move. Say that roads, rivers, villages, fields and marshes appear only on real-terrain maps; the normal battle has none.
- §5 "Maps from real terrain": replace "Villages, fields and marshes count as plains for now" with how a hex gets its type: water or forest when they cover most of it; otherwise urban when buildings cover at least a fifth of it, marsh when wetland covers at least a quarter, hills when the ground rises 15 m or more, fields when farmland is the largest open cover, else plains. Main roads and village streets count as roads (field and forest tracks do not); rivers, canals and named streams count as rivers.
- §6 "Movement": path cost includes roads and rivers (example: `3 / 3 MP` for three road hexes through forest).
- §10 "Screen" → Terrain panel: the `Road` and `River +1` tags; the lines drawn on the map.
- §13 "Not in the game yet": bridges over lakes / wide rivers, buildings in villages (until TASK-108b), forest tracks as roads.

## Out of scope

- **TASK-108b** (backlog idea, follows this task): the realistic look – field / road ground layers in the two free `ARRAY_CUSTOM0` splat channels (CC0 textures), river as a water-shaded ribbon with mud banks and curved centrelines, procedural village houses (MultiMesh, gable roofs, LOW fallback, instance budget), marsh reeds, bridges where roads cross rivers, FPS check on Suwałki.
- Movement types (tracked / wheeled / foot costs per terrain), mountains, line of sight and fog of war (TASK-007 – the "blocks sight" column is input for it only), elevation effects, supply along roads (TASK-096), named cities and city labels, river valley carving in the height field, tuning the random generator (it stays as it is).

## Implementation notes

Logic, importer and basic look implemented (gameplay-engineer, 2026-10-31). ADR: [0019](../adr/0019-roads-rivers-real-terrain-types.md).

**Core**
- `Terrain.Type` = `PLAINS, FOREST, HILLS, WATER, FIELDS, URBAN, MARSH` (appended); `data/terrain/fields|urban|marsh.tres`; `TerrainFeatures` (`src/core/data/terrain_features.gd`, `data/terrain/features.tres`, `Terrain.features()`, cached).
- `HexGrid`: `set_road_links` / `road_links` / `has_road`, `set_river_links` / `river_links` / `is_river`, `has_links()`, `links_version()` (for view caches), `step_cost(from, to)`; `_search` uses `step_cost`, so `reachable`, `path_to`, `MoveUnitCommand`, `AiPlayer`, the path preview and the panel path cost need no change. `step_cost` returns the plain terrain cost early on grids without links (generated maps: same numbers, same speed).
- `ImportedMap`: `A`/`U`/`M` terrain chars, `LINK_CHARS`, `road_rows` / `river_rows` (may be empty), `problem()` checks size, characters, no links on water and land–land symmetry; `to_grid()` sets the masks.
- `Scenario`: `_deployment_tiles` takes plains **or fields**; `from_setup` no longer forces a company's **fields** tile to plains (it keeps forcing every other non-plains tile, as before – generated maps never have fields, so the default battles are unchanged).

**Importer** (`tools/import_map.py`): `classify(counts, relief, …)` (water/forest dominance → urban ≥ 20 % → marsh ≥ 25 % → hills ≥ 15 m relief → fields → plains; `--urban-share`, `--marsh-share`), `line_kind` / `osm_lines` (rule roads incl. `_link`; river, canal, named stream), `line_links` (10 m densification, 40 m corner-clip smoothing, unbounded `HexLayout.axial_at`), `store_links` (storage rule), `road_rows` / `river_rows` written after `cover_rows`. Synthetic fixture OSM gained a named river (crossing the road), a `track` and an unnamed stream; fixtures and `tests/fixtures/maps/sample_map.tres` regenerated (`sample_dem.tif` byte-identical).

**Suwałki re-import** (offline from the existing cache, same command + `--offline`; run twice, `cmp`-identical): fields 101, forest 126, hills 129, marsh 9, plains 320, urban 11, water 24 (TASK-087: plains 439, hills 131, forest 126, water 24); 240 hexes with road links, 34 river hexes (one river in the north-west, running from the north edge to the west edge, crossed by several roads). All lines other than the `*_rows` are byte-identical to the TASK-087 file (elevations, scale, reference); F and W positions unchanged (test). Urban = 11 hexes of village cores (villages are small at 250 m; which villages they are was not checked against a map – playtest step 1). CREDITS updated.

**Presentation (basic look)**: `TerrainSplat` base layers per new type; `ScatterPlanner` (fields / marsh as plains, urban without trees and rocks), `GrassPlanner.density_of` (fields × 0.6, urban × 0.3, marsh × 1; flowers stay plains/hills only), `MotionEffects` (marsh → mud colour, rate × 0.4); `TerrainPanelModel` tags `Road` / `River +1` (strings + Polish in `assets/i18n/strings.csv`, also Fields / Urban / Marsh); `FeatureRibbonPlanner` (pure: half-segments, triangles, clearance index) + `FeatureRibbons.build` (one mesh per kind, `Roads` / `Rivers`, none without links). Scatter is filtered after planning (RNG streams unchanged); grass and flowers skip candidates on ribbons after their draws.

**Checks**
- Default battle, `tools/simulate.sh 50 --seed=1`: identical summary before/after (P0 17, P1 30, harness limit 3, average 10.5 / 12.9 turns); replay fixture test passes unchanged.
- `tools/simulate.sh 20 --scenario=suwalki_battle`: before P0 14 / P1 6, 16.9 turns, 10.9 s; after P0 13 / P1 7, 16.0 turns, 11.6 s (+6 %, budget +20 %).
- `MapView.build` on `suwalki_battle` (headless software renderer, median of 5 alternating builds in one process): 4.82 s for the map reduced to TASK-087 content (new types → plains, no links) vs. 4.97 s now (+0.15 s, budget +0.2 s). A first version of the ribbon clearance check cost +0.35 s; the per-grid segment index brought it down (scatter filter 410 → ~100 ms).
- Screenshots (Windows D3D12 build, RX 580, HIGH): `docs/images/suwalki_battle.png` re-rendered – roads are continuous thin grey-brown lines, the river a continuous blue-grey line crossed by roads, field patches read as khaki stubble against green meadows; urban hexes show only as gravelly patches (no houses yet, TASK-108b). `docs/images/gameplay.png` re-rendered and compared – identical content (pixel noise only), so the committed file was kept.

**Playtest follow-up: smooth ribbons + Suwałki frame time** (presentation-engineer, 2026-10-31; the human reported angular roads/rivers and ~30 FPS)
- Ribbons: `FeatureRibbonPlanner` rewritten – pieces per tile (through / spoke / dead end), chained into polylines across tiles, cubic Béziers with shared port tangents and control points clamped in the hex (lines stay in their hexes and cross the linked sides), river meander + width variation + narrowing at sources (hash noise, no RNG), round road junctions, gap-free strips; roads lie 0.004 above rivers. `is_clear` / new `edge_distance` use the new geometry. Tests: chain continuity, max turn angle (< 12° on a hex zigzag, < 20° on a 120° hex turn), lines only in linked tiles and across linked sides, determinism, meander bounds, junction spoke ends on the through line, strip vertices within the half width.
- Frame time probe fixed: `FramePacing` capped `SCREENSHOT_MEASURE_FRAMES` at 60 FPS (16.7 ms floor); the probe now lifts the cap and also prints GPU / render CPU time. Profiling (hiding parts): the main map-size costs were whole-map bush/rock MultiMeshes (never culled, 1600-triangle bushes: ~3.3 M tris, ~5 ms), tree draws (two surfaces per tree), scrub LOD1 (155 tris, as much as LOD0, ~6 400 plants) and LOD0 trees/shadows (content: Suwałki's view is mostly forest).
- Fixes: `ScatterChunks` (bushes/rocks per 8×8 chunk + far bush LOD beyond 28), one surface per tree mesh, coarse scrub LOD1 lobes without holes, tree LOD2 beyond 46 (helps zoomed-out views only). Tried and dropped because they changed the default-camera look: a separate opaque LOD1 shader and a bush LOD at 20. Default battle look compared crop by crop with the pre-change screenshot: no visible difference.
- Review fixes: spoke junctions built once and looked up per tile in the meander; clearance cache compared by grid id + version without allocating; ribbons are an indexed mesh with a crest lift (no dipping under convex terrain creases, tested on a sharp synthetic ridge); new tests in `tests/unit/test_feature_ribbon_shapes.gd` (closed loop, two crossing through pieces, crest, no scatter point inside a drawn ribbon triangle). Bush LOD fade margin 5.7 measured +0.3–0.5 ms, so it stays 3 (noted in ARCHITECTURE). Ribbon cost in the Suwałki build (headless): planning ~80 ms, meshes + draping ~200 ms (the old half-segments ~50 ms) – about +0.25 s on a ~7 s build on today's (slower) machine state.
- Measured (Windows D3D12, RX 580, HIGH, default camera, fixed probe, 150–240 frames): Suwałki 28.0 ms / 3820 draws / 11.07 M tris → 23.8 ms / 2406 / 8.52 M; default battle 18.0 ms / 2576 / 5.12 M → 17.3 ms / 1743 / 4.38 M. Zoomed views (distance 12 or 46) are ~10 ms on both maps. The goal (Suwałki ≤ default) is **not** reached: the rest is content – far more LOD0 forest within ~40 units of the default camera – and closing it needs a quality trade (options with measured gains in the report: MSAA 4x→2x ≈ −2 ms, LOD1 tree shadows off ≈ −0.7 ms, 2 shadow splits ≈ −1.5 ms, a shorter LOD0 range ≈ −0.5 ms).

**Known limitations**
- Hex-row zigzags are smoothed into gentle S-curves, not straight lines (the curve still passes every linked side midpoint region).
- Urban hexes barely differ from fields at a distance until houses come (TASK-108b); marsh hexes are few (9).
- The `River +1` tag is a fixed UI string; if `river_extra_cost` ever changes in data, the string must change too.
- FPS on the Suwałki map was not measured in the game window (the agent can't see it) – playtest step 8.
