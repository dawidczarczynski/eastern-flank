# TASK-108c: Real-terrain look v2 – river at real width as flowing water with muddy banks, real-size bridges

- **Status**: done
- **Layers**: presentation (`FeatureRibbonPlanner` real widths, flow coordinate, bank band and bridge sites, `FeatureRibbons`, new `assets/shaders/river.gdshader`, bridge mesh, `GraphicsQuality` switch) + docs (ARCHITECTURE, MANUAL)
- **Depends on**: TASK-108b (`MapScale`, ribbon `across` attribute in `UV.y`, min on-screen width, ribbon edge fade) (soft: TASK-110; priority: after the operational core loop 092 → 094 → 095)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Rivers on real-terrain maps have their real width and look like water – darker in the middle, shallow at the edges, ripples drifting downstream, muddy banks – and every place where a road crosses a river shows a small bridge at its real size, so the player sees where crossing costs nothing extra (TASK-108 rule: a step along a road link into a river hex has no +1). Generated maps have no rivers or roads: nothing changes there.

## Design

All dimensions in metres, converted with `MapScale.metres_per_unit` (TASK-108b; Suwałki 144.3 m / unit). Minimum visible feature and the 1.5 px minimum on-screen width: see TASK-108b "Scale".

### Real width and banks (part of the river ribbon)

- **Water width 8 m** (± 25 % by the existing width noise; 40 % at a dead-end source as today) – one width for all rule rivers, because the importer stores no river class (Suwałki's rivers are small lowland rivers, 5–15 m). Suwałki: 0.055 units instead of 0.15. The meander (±0.07 units ≈ ±10 m) stays.
- **Bank band 3 m** on each side, part of the same ribbon mesh (the terrain mesh's 36 m vertex step cannot draw it as splat – TASK-108b): the ribbon is water width + 2 × 3 m wide; `across` (TASK-108b) is 0 on the centreline, ±1 at the bank's outer edge, and the water edge sits at `across` = water / (water + 6 m).
- Scatter clearance: ribbon half width + 3 m (as roads).

### Flow coordinate (pure, `FeatureRibbonPlanner`)

- Each river chain flows from its end with the higher drawn ground height (`TerrainSurface` at the end point) to the lower one. If the ends differ by less than **1.5 m** (converted to game height): from a dead-end end (source) towards the other; if both or neither are dead ends: from the end with the smaller `(x, z)`. Loops keep their point order. Deterministic.
- `mesh(grid, RIVER)` additionally returns `along: PackedFloat32Array` per point = arc length in **metres** from the upstream end, stored in `ARRAY_TEX_UV.x`. Junction discs take the `along` of the through chain at their centre.

### River shader (`assets/shaders/river.gdshader`)

- Replaces the river's `StandardMaterial3D`. Water part (`|across|` ≤ water edge): colour from deep `#2e4a52` (centre) to shallow `#4c6a62` (water edge), alpha 0.95 → 0.7. Bank part: wet mud (the mud ground layer, sampled like the road shader samples gravel), alpha fading to 0 at `|across|` = 1. Look values; start from `water.gdshader`'s palette so lakes and rivers match.
- Ripples: `water.gdshader`'s normal map at `UV = (along, across · half width)` in metres, scrolled downstream at **0.4 m/s** (two scales as the lake), `normal_scale` 0.3, roughness 0.06; reflections from sky / SSR on HIGH as the lake.
- New `GraphicsQuality.features` switch **`river_flow`** (HIGH true, LOW false): LOW draws the same colours and banks with static normals. Same minimum on-screen width as roads (TASK-108b). Compiles on the Compatibility renderer.
- Stays one `MeshInstance3D` (`Rivers`), no shadows; order: rivers below roads below bridges.

### Bridges (pure planner + one mesh)

- `FeatureRibbonPlanner.bridges(grid) -> Array[Dictionary]`: one entry per intersection of a road centreline with a river centreline (segment tests on the sampled polylines with the per-tile piece index; sites closer than 10 m merged). Entry: `position: Vector2`, `direction: Vector2` (unit, along the road), `span_m` = local water width / `|sin(angle)|` + 2 × **4 m** (abutments), capped at **40 m**; `width_m` = **7 m** (5 m carriageway + 2 × 1 m kerb with railing). Empty when either kind has no links.
- A road whose link enters a river hex but whose drawn line does not cross the drawn river gets **no** bridge (the rule still applies to that step; the picture shows only real crossings).
- `Bridges.build(sites, drape) -> MeshInstance3D` (`src/presentation/bridges.gd`): **one** merged `ArrayMesh` `Bridges` (one draw call): per site a deck (0.6 m thick, top **1.5 m** above the water surface mid-span, ramps so both ends meet the road ribbon height within 0.3 m), two railings (0.3 m wide, 1.0 m high), two abutment blocks; ≤ **60 triangles per bridge**. Concrete grey `#8d8b84`, roughness 0.9. Shadows on HIGH, not on LOW. No node without sites.
- At today's camera a 7 m × 20 m bridge is ~2 × 6 px at the default zoom (TASK-108b "Scale"); the road's minimum width keeps the crossing readable.

### Performance

- Budget (Windows D3D12, HIGH, default camera, `SCREENSHOT_MEASURE_FRAMES=240`, median of 3, before → after): **Suwałki ≤ +0.3 ms** GPU and ≤ +1 draw call (+ shadow pass); **default battle identical draw count**, frame time ± 0.3 ms. `MapView.build` on `suwalki_battle` ≤ +0.1 s.

## Acceptance criteria (testable)

`test_feature_ribbon*.gd`, new `test_bridges.gd`, `test_graphics_quality.gd`, a `MapView` test (shared via `before_all`):
- [ ] Widths at Suwałki scale: a straight mid-river cross-section is 8 m × (1 ± 0.25) + 6 m wide; the water edge lies at `|across|` = water / (water + 6 m) (± 1e-3); halving `metres_per_unit` doubles the world width.
- [ ] Flow: a river chain over a field sloping down towards +x has `along` = 0 at its −x end, increasing monotonically, last value = polyline length in metres (± 0.1 m); reversed slope → reversed; equal heights with a dead end → `along` = 0 at the dead end; same grid twice → identical arrays.
- [ ] `mesh(grid, ROAD)` is unchanged from TASK-108b (no `along`, same widths).
- [ ] Bridges, hand-made grid with one straight road crossing one straight river: exactly **1** site within 1 m of the true intersection; at 90° `span_m` = water width + 8 m (± 0.5 m); at 45° = water width / sin 45° + 8 m (± 0.5 m); a very shallow angle is capped at 40 m; a road beside a river without crossing → 0 sites; no links → 0 sites and no `Bridges` node.
- [ ] Suwałki: ≥ 1 bridge site; each lies in a tile with both a road and a river link; no two closer than 10 m.
- [ ] Bridge mesh: ≤ 60 triangles per site; deck top mid-span ≥ 1.5 m (in game height) above the river surface; both deck ends within 0.3 m of the road ribbon height; one `MeshInstance3D` for all.
- [ ] `GraphicsQuality.features`: `river_flow` true on HIGH, false on LOW; the river material's flow uniform follows it.
- [ ] Scatter clearance: no tree, rock, bush or grass instance within ribbon half width + 3 m of a river centreline.
- [ ] Frame and build times before/after recorded; within budget or explained.
- [ ] Screenshots Read by the agent: Suwałki default view and a close-up at distance 7 on a road–river crossing (`SCREENSHOT_FOCUS`): the river is a thin continuous water line with mud banks, a bridge spans it at the crossing; `docs/images/suwalki_battle.png` re-rendered; `docs/images/gameplay.png` unchanged in content.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle`, find the river in the north-west. It is now as narrow as the real river (about 8 m): a thin water line with muddy edges. Zoom in fully: darker middle, lighter edges, ripples drifting downhill.
2. Where a road crosses the river there is a small grey bridge with railings; the road runs onto it without a step.
3. With a unit selected, a path along the road over the bridge shows no extra cost, a path into the river hex elsewhere +1.
4. `--quality=low`: same river and bridges, no moving ripples, no bridge shadows.
5. Frame rate on HIGH on Suwałki: no visible drop.

## Player manual

§10 "Screen" → "Roads and rivers": rivers are drawn at their real width as flowing water with muddy banks; a small bridge marks every place where a road crosses a river (no extra cost there). Replace "(Houses, bridges and a proper river look come later.)" with "(Houses in villages come later.)" – or drop it if 108d is already done. §13 "Not in the game yet": keep "bridges over lakes / wide rivers".

## Out of scope

- River widths by class or OSM `width` tag (no class data stored), valley carving, waterfalls, foam.
- Bridges over water hexes and any rule change.
- Reeds (TASK-108e), houses (TASK-108d), real scale of units / trees / camera (TASK-110).

## Implementation notes

- **Planner** (`feature_ribbon_planner.gd`): river = 8 m water (± 25 % noise, 40 % at a dead-end source) + 3 m bank each side in one ribbon (`RIVER_WATER_M`, `RIVER_BANK_M`; `width(RIVER)` is now the whole 14 m ribbon, `max_half_width` includes the banks, `clearance` is 3 m for both kinds). River lines are stored downstream-first (`_flows_forward`: higher drawn ground `TerrainSurface.ground_height` first; ends within 1.5 m: dead-end source, else smaller (x, z); loops keep order); `flows(grid)` gives metres from the upstream end, `mesh(grid, RIVER)` adds `along` and `water_edge`. `bridges(grid)` tests road vs river segments per tile on the existing clearance index, merges sites < 10 m; `bridge_span_m` is a separate pure function (the 90 / 45 degree and 40 m cap cases are unit-tested on it, since hex geometry cannot give those angles on a hand-made grid).
- **Rendering**: `river.gdshader` (water deep to shallow, mud bank sampled from the ground layer array, `water.gdshader`'s normal map in (along, across) metres, min 1.5 px width, `render_priority` -1 so the transparent river draws under the transparent road); `GraphicsQuality.features.river_flow` (HIGH true, LOW false; the material's `flow_speed` follows it). `Bridges.build` makes one merged flat-shaded mesh, 52 triangles per bridge; `FeatureRibbons.add_to` builds roads, rivers and bridges (moved out of `MapView`, which was at the 1000-line lint limit). Bridges cast shadows with `GraphicsQuality.shadows`.
- **Deviations / assumptions**: vertical metres (1.5 m clearance, 1.5 m flow tie, deck thickness) are converted 1:1 with `MapScale.to_units`, as the game height has no separate metre scale; no extra `bridge_shadows` switch (reuses `shadows`); bridge deck ends use the plain road ribbon height (without the per-triangle crest lift), so on a crest the ribbon can sit a little above the deck end; no dedicated `LOW`-only code path in the shader beyond `flow_speed = 0`; the river's `half_widths` now include the banks (the clearance index and forest mask use them as the ribbon half width).
- **Suwałki**: 8 bridge sites (`bridges` takes ~0.24 s of planning, cached per grid), one of them at a very shallow angle (span capped at 40 m). Screenshots read: default view (rivers are thin water lines) and a close-up on the crossing near (5.6, 14.26) at distance 0.4 (mud banks, darker water in the middle, a grey bridge with railings under the road). `docs/images/suwalki_battle.png` re-rendered; `tools/readme_screenshot.sh` re-run, `gameplay.png` is unchanged (generated map, no ribbons).
- **Not verified**: frame times and draw-call budget (GPU ms, `MapView.build` +0.1 s) were not measured; flowing-ripple motion, input feel and the LOW look need the human's playtest (a still image cannot show them).


### Follow-up (playtest fixes)

- **Confluences**: rivers have no discs; a tributary (spoke) now fades its opacity to 0 over the last 9 m towards the through river (and a source over 12 m): `fade` in `COLOR.g`, multiplied into `ALPHA` by `river.gdshader`; tributary strips come last in the mesh so they draw over the through river. Left / right `across` and `water_edge` are per vertex, so the shader needs no change for uneven banks.
- **Natural look**: `RiverShape` (new, split out of `FeatureRibbonPlanner`, which hit the 1000-line limit): meander up to ±32 m (24.5 m at 317 m + 7.5 m at 108 m), per-side water edge (±25 %) and bank band (±50 %) noise at 130 m and 40 m wavelengths. Every length is metres converted with `MapScale` (`RIVER_MEANDER_M`, `*_WAVELENGTH_M`, `JUNCTION_CALM_M`, `SOURCE_TAPER_M`); `half_widths` is now the wider side, bridges take the water width from the index (`water`). Tests: `test_river_shape.gd`, `test_feature_ribbon_river.gd`.
- **Vegetation**: reeds were working (edge_distance in the 3-10 m band outside the ribbon, since scatter keeps 3 m clear of the ribbon edge incl. the mud); they are sparse because they use the grass density and are grass-LOD only. Not changed. New `RiparianPlanner` (shrubs + alders, patchy, capped, `tests/unit/test_riparian_planner.gd`) hooked into `FoliageChunks._plan_source`; Suwalki gets ~154 trees and ~660 shrubs in total. LOW has no foliage, so no extra cost; generated maps (no links) plan nothing.
- Screenshots read: bank close-up (reeds, shrubs, banks), default Suwalki. The confluence was checked with a top-down raster of the planner mesh with the shader's alpha model (the game camera is too low to see it past trees); true-size preset close-ups landed inside forest hexes, so the true-size look of the river banks was not seen.

### Follow-up 2 (floating ribbons, bridge tangle; true-size playtest)

- **Floating**: ribbons were draped on the coarse lattice mesh (36 m vertices) with a geometric lift of 0.02 / 0.024 world units (2.9 / 3.5 m at Suwalki scale), while the near terrain LOD (4.5 m vertices, surface heights) draws the ground close up: a gap of metres. Now `MapView._ribbon_drape` puts every ribbon / bridge point on the exact `TerrainSurface` height plus `FeatureRibbonPlanner.LIFT_M` / `ROAD_LIFT_M` (0.25 / 0.3 m, converted by `MapScale`), the centreline sample step is 0.03 units (one near cell), and the crest lift is skipped (`FeatureRibbons.add_to(..., crest := false)`). `road.gdshader` / `river.gdshader` pull the ribbon towards the camera along the view ray (`pull_base` 0.003 + `pull_per_distance` 0.004 x distance; a screen-space no-op) so the coarse far mesh does not poke through it.
- **Bridges**: the larger meander made a river weave across a nearby road, giving several decks within a few tens of metres (overlapping, different angles). `BridgeSites` (split out of the planner, which hit the line limit) collects all crossings, sorts them steepest first and drops any whose centre is closer than half the two spans (at least 10 m) to a kept one. Decks and abutments now use the same ribbon drape and lifts. Tests: `test_ribbon_ground.gd` (vertices on the exact ground at the default and a halved scale, overlap rule, no overlaps on Suwalki).
- Screenshot read: terrain viewer hex (35, 61), true-size preset, low camera: river and road lie on the ground, bridge deck at road height. Build time of the ribbons grew (surface heights at 29 us per call, twice the vertices); not measured separately.
