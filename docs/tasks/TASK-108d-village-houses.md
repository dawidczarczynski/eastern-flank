# TASK-108d: Real-terrain look v2 – real-size village farmsteads on urban hexes (MultiMesh, LOW fallback)

- **Status**: ready
- **Layers**: presentation (`MapScale` if not there yet, new pure `VillagePlanner`, `HouseMeshes`, `VillageField` node built by `MapView`, scatter/grass exclusion, `GraphicsQuality` use) + docs (ARCHITECTURE, MANUAL)
- **Depends on**: TASK-108 (done) (soft: TASK-108b – `MapScale`, real road widths, farmyard soil; TASK-110 – realistic scale; priority: after the operational core loop 092 → 094 → 095)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Villages – the urban hexes that give +2 defense – look like real Polish street villages: farmsteads of a house, a barn and a shed at their **real size** (a house ~11 × 8 m), lined along the village road, so the player recognises a village, while units in the hex never drive through a wall. Cheap enough for thousands of buildings on large maps, and visible on LOW.

## Design

### Scale (decided 2026-10-31: real size)

- All dimensions in **metres**, converted with `MapScale.metres_per_unit` (TASK-108b "Scale"; Suwałki 144.3 m / unit; introduce `MapScale` here if 108b has not landed yet). A house 11 m long is 0.076 units on Suwałki – about 3 px at the default camera, ~11 px at the closest zoom (TASK-108b "Scale"). The unit models are still ~12× oversized until TASK-110's follow-up switches them to real size (decided 2026-10-31; TASK-111 adds the markers and the close camera – at its ~58 m minimum distance a house is ~200 px long), so buildings look small next to them – expected.
- **Unit clearance follows the unit scale, not the map scale**, so the "never through a wall" rule holds before and after TASK-110:
  - `CORRIDOR_HALF` = 1.9 m (half the widest vehicle, the Abrams) × unit world-units-per-metre (`VisualScale.unit_model_scale()` × the models' 0.078) + 2 m in map scale → **0.177 units today**, ≈ 0.027 after TASK-110 at true scale;
  - `CENTRE_CLEAR` = 5.5 m (half the longest model incl. gun) × the same + 3 m in map scale → **0.49 units today**, ≈ 0.059 at true scale.
  Today's oversized units leave the ring between the centre disc and the hex border minus six corridors (≈ 1.0 units² ≈ 2 ha per hex, mostly towards the corners) for buildings; real-size farmsteads fit there, so no building ever stands on a unit's path – but villages are sparser and set back from the road until TASK-110 shrinks the clearances.

### Where buildings stand (pure `VillagePlanner`, `src/presentation/village_planner.gd`)

- **Only URBAN tiles** get buildings (Suwałki: 11). Generated maps have no urban tiles.
- Deterministic from tile coordinates, the grid's links and `MapScale`: integer hash, no RNG object, never `GameState.rng`.
- **Farmstead lots** (a typical *zagroda*): house always, barn 70 %, shed 50 % (hash).
  - **Along roads** (the tile has road links): walk each road centreline piece inside the tile on both sides; lot frontage **25–40 m** (hash) along the road. The house stands **6–12 m** (hash) behind the road ribbon edge, long side parallel to the road (60 %) or gable to the road (40 %, the common Polish layout); the barn **20–35 m** behind the house across the yard, parallel to the road; the shed beside the barn (5–10 m gap). Roads run from side midpoint to side midpoint, i.e. inside the unit corridors: while `CORRIDOR_HALF` is today's 26 m, a house is pushed further back in 2 m steps until it clears the corridor, up to **40 m** from the road edge, else the lot is dropped. After TASK-110 (corridor ≈ 4 m) the 6–12 m setback holds as designed.
  - **No road in the tile**: one lot per corner wedge (between two corridors, pointing at a hex corner), 3–6 wedges occupied (hash); house towards the centre, barn behind it towards the corner, shed beside. (Today's centre disc of 71 m leaves about 54 m to the hex side and ~70 m towards a corner, so the barn is the first to be dropped.)
  - At most **10 lots** per tile.
- **Validity** for each building's footprint grown by **2 m** (a building that fails is dropped – first try ±10° less yaw jitter; a lot without its house is dropped whole):
  1. inside the tile's hex shrunk by **3 m**;
  2. at least `CORRIDOR_HALF` from each of the six corridors (tile centre → side midpoint);
  3. outside the `CENTRE_CLEAR` disc;
  4. at least **2 m** from every road and river ribbon edge (incl. verges / banks) and from bridge decks (TASK-108c, when present);
  5. no overlap with another building (grown footprints, i.e. ≥ 4 m apart).
- The notes list Suwałki tiles that end with fewer than 2 lots (tuning hint, not an error).
- Output per building: `position: Vector2`, `yaw: float`, `variant: int`, `size_m: Vector3` (length, width, eaves height), `custom: Color`. `VillagePlanner.footprints(grid)` (cached per grid id + `links_version`) is what scatter, grass and flowers test against.

### Real sizes (metres)

| Variant | Length | Width | Eaves | Roof | Extras |
|---|---|---|---|---|---|
| house | 10–12 | 7–9 | 3.0 (70 %) or 5.0 (30 %, 1.5 storeys) | gable 35–45°, overhang 0.5 | chimney 0.6 × 0.6, 1.0 above the ridge |
| barn | 15–24 | 9–12 | 4.5 | gable 30–40°, overhang 0.4 | – |
| shed | 4–7 | 3–5 | 2.4 | mono-pitch 15° | – |

### Meshes and colours (`HouseMeshes`, pure, cached)

- One `ArrayMesh` per variant, **one surface**, base at y = 0, unit length / width / eaves (the instance transform scales it to metres × `1 / metres_per_unit`), vertex colour r = part (0 wall, 1 roof, 0.5 chimney/trim), g = baked AO. Triangles: house ≤ **40**, barn ≤ 30, shed ≤ 20 (no bottom faces).
- `assets/shaders/house.gdshader` (or a vertex-colour `StandardMaterial3D` if enough): wall / roof colour per instance from `INSTANCE_CUSTOM` – walls plaster cream `#cfc6b0`, light grey `#aaa79e`, faded yellow `#c2b27f`, red brick `#8a5642` (barns: weathered wood `#5b4b3b`, grey block `#8f8d86`); roofs red-brown tile `#7a3d2c`, dark grey sheet `#55524d`, grey fibre-cement `#7c7b75`; value ± 8 % per instance. Roughness 0.85–0.95, no textures.
- Grounding: base at the lowest terrain height under the four corners (`MapView._drape`), walls extended 0.5 m below, so nothing floats on a slope.

### Nodes, LOW fallback, budget

- `VillageField` (a `Node3D` owned by `MapView`, built in `MapView.build`): one `MultiMeshInstance3D` per **8 × 8 `TreeField` chunk × variant** with buildings, named `Houses_<variant>_<x>_<z>` (frustum culled, no visibility range). None when the map has no urban tile.
- **HIGH**: shadows (`shadows` switch). **LOW** (decided 2026-10-31): the same buildings – they mark the +2 villages – without shadows and without chimneys; `foliage = false` does **not** remove them.
- Budget: **`VillagePlanner.INSTANCE_BUDGET` = 6000** buildings per map (sheds dropped first, then barns, `push_warning`). Suwałki: ≤ 11 × 10 × 3 = 330.
- Scatter: trees, bushes, rocks, scrub, grass and flowers are filtered out of grown footprints after planning (RNG streams unchanged).
- Frame budget (Windows D3D12, HIGH, default camera and a close-up at distance 7 on a village, `SCREENSHOT_MEASURE_FRAMES=240`, median of 3): **Suwałki ≤ +0.5 ms**, **≤ +30 draw calls** (incl. shadow passes); default battle identical draw count. `MapView.build` on `suwalki_battle` ≤ +0.1 s.

## Acceptance criteria (testable)

New `test_village_planner.gd`, `test_house_meshes.gd`, scatter / grass tests, a `MapView` test (shared via `before_all`):
- [ ] Sizes at Suwałki scale (`metres_per_unit` 144.34): every house's length × width lies in 10–12 × 7–9 m (in world units ÷ 144.34, ± 1e-4), barns 15–24 × 9–12, sheds 4–7 × 3–5; halving `metres_per_unit` doubles every world size.
- [ ] Clearances derive from the unit scale: with `unit_model_scale` 1.1, `CORRIDOR_HALF` = 0.177 (± 0.002) and `CENTRE_CLEAR` = 0.49 (± 0.005) units at 144.34 m / unit; with a test unit scale giving 0.00693 units / m they become 0.027 / 0.059 (± 0.002).
- [ ] Hand-made 3 × 3 grid, centre tile URBAN without links: 3–6 lots, at most one per corner wedge, each with a house; plains tiles: 0 buildings.
- [ ] Urban tile crossed by a road (links 0 and 3), today's unit scale: ≥ 2 lots; every house 6–40 m from the road ribbon edge; every barn farther from the road than its house. Same tile with a true-scale test unit scale (0.00693 units / m): ≥ 4 lots and every house 6–12 m from the road edge.
- [ ] For every building of those grids and of Suwałki: grown footprint inside the hex shrunk by 3 m; ≥ `CORRIDOR_HALF` from all six corridors; outside `CENTRE_CLEAR`; ≥ 2 m from every ribbon edge; no two grown footprints overlap (separating-axis test). (This is the testable form of "units never drive through a wall".)
- [ ] Determinism: same grid twice, and the same tile in two grids with the same links, give identical lists.
- [ ] Suwałki: every URBAN tile has ≥ 1 lot; non-urban tiles 0; total ≤ `INSTANCE_BUDGET`; tiles with < 2 lots listed in the notes.
- [ ] Budget: a synthetic all-urban 40 × 30 grid (planned > 6000) is cut to 6000, sheds dropped before barns before houses.
- [ ] `HouseMeshes`: triangles house ≤ 40, barn ≤ 30, shed ≤ 20; LOW house without chimney triangles; unit-size AABB 1 × 1 in x/z (± overhang); a 40° gable's ridge at eaves + 0.5 · width · tan 40° (± 1e-3).
- [ ] Grounding: on a hand-made slope each building's base y = lowest drape height of its corners (± 1e-4).
- [ ] Scatter / grass: no tree, bush, rock, scrub, grass clump or flower inside a grown footprint; other planned positions unchanged.
- [ ] `MapView` on the urban test grid: `Houses_*` nodes with instance counts summing to the planner's count; HIGH → shadows on; LOW → built, shadows off; a generated map → no `Houses_*` node.
- [ ] Frame and build times before/after recorded; within budget or explained.
- [ ] Screenshots Read by the agent: Suwałki default view and a village close-up at distance 7 (`SCREENSHOT_FOCUS`), HIGH and `--linux` (LOW): small gabled buildings in farmsteads along the village roads, none on roads, in forest or in the hex centre, none floating; `docs/images/suwalki_battle.png` re-rendered; `docs/images/gameplay.png` unchanged in content.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle`. Find a village (terrain panel: Urban). Zoom in fully: farmsteads of a house, a barn and sometimes a shed, lined along the road, roofs red-brown or grey; the middle of the hex and the ways to the six neighbours stay free.
2. Buildings sit on the ground on slopes; no grass or trees grow through them; none stands on a road.
3. Move a tank and an infantry squad into and through a village hex: never through a wall.
4. Note the scale: buildings are real size, so they look small next to the still-oversized units until TASK-110.
5. `--quality=low`: buildings still there (no shadows). Frame rate on HIGH on Suwałki: no visible drop.

## Player manual

§10 "Screen" → "Roads and rivers": villages (urban hexes) show real-size farmsteads – houses, barns and sheds along the village road; the middle of the hex and the ways to the neighbours stay free for units; buildings are only a picture of the +2 village (the whole hex counts as urban) and also show on LOW graphics. Drop "Houses … come later". §13 "Not in the game yet": remove "buildings in villages"; add "individual buildings as cover or obstacles".

## Out of scope

- Real building footprints from OpenStreetMap and farmsteads on non-urban hexes (procedural first – decided 2026-10-31; an importer task only if this is not convincing).
- Churches, town blocks, city labels, destructible buildings, buildings as rule objects.
- Real scale of units / trees / camera (TASK-110); textures, interiors, night lights.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
