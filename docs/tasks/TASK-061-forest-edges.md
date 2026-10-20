# TASK-061: Forest edges and undergrowth – shrub belts along forest borders, ground cover under trees

- **Status**: ready
- **Layers**: presentation (`scatter_planner.gd` edge rules, `map_view.gd` scatter, foliage material), tests
- **Depends on**: soft **TASK-057** (wind include; tall-grass clumps reuse the grass card), soft **TASK-060** (shrubs use the new foliage shader if done), soft **TASK-059** (sizes)
- **Model**: sonnet

## Goal

Forests stop looking like islands of trees dropped on a lawn. Along their edges a belt of shrubs, young trees and tall grass softens the transition into open ground, and the forest floor is covered with low undergrowth.

## Design

- **Edge detection** (pure, in `ScatterPlanner`): for each forest tile, the **open sides** = hex directions whose neighbour is on the map and not forest (and not water). For each plains/hills tile, the **forest sides** = directions whose neighbour is forest.
- **Forest side of the edge** (inside the forest tile, per open side): **6 shrubs** in the sector of ±30° around that direction at radius **0.55–0.95** from the tile centre (`r = 0.55 + hash·0.4`), scale **0.35–0.6** (larger than today's bushes, ×TASK-059 bush scale), plus **2 young trees** (tree mesh, scale 0.4–0.6) at radius 0.5–0.8.
- **Open side of the edge** (inside the plains/hills tile, per forest side): **3 shrubs** within **0.3** of the shared edge midpoint region (radius 0.65–0.95 from the tile centre, sector ±25°), scale 0.25–0.45, and **8 tall-grass clumps** (grass card ×2.2 height) in the same band when TASK-057 exists (otherwise skip).
- **Forest floor**: +**6 low ground-cover** bushes per forest tile (scale 0.18–0.3, y-scale 0.5) anywhere in the tile, in addition to today's 8 bushes.
- Same rules as existing scatter: own RNG stream (new seed xor), every candidate draws a fixed count of numbers (a skipped candidate never shifts the stream), skip below `MIN_TREE_GROUND`, no change to existing trees/bushes/rocks output.
- Colours: shrubs `#3d5426 → #66733a` (instance mix by `k`), ground cover `#34482a → #55623a`. Shadows: shrubs cast, ground cover does not.

## Acceptance criteria (testable)

- [ ] `test_scatter_planner.gd` additions (fixture: a forest tile surrounded by 2 forest + 4 plains neighbours):
  - the forest tile gets exactly `6·4` edge shrubs and `2·4` young trees, each inside its sector (angle to the open-side direction ≤ 30°) and radius band [0.55, 0.95] / [0.5, 0.8];
  - each of the 4 plains neighbours gets 3 edge shrubs within its forest-side sector (≤ 25°) and radius band [0.65, 0.95];
  - a forest tile with only forest neighbours gets no edge shrubs but 6 ground-cover bushes;
  - water neighbours produce no edge plants on either side;
  - deterministic for a seed; existing tree/bush/rock arrays identical to before (compare against the current planner output on 3 maps).
- [ ] `MapView` creates the new MultiMeshes (edge shrubs, young trees, ground cover); ground cover has shadow casting off.
- [ ] Agent visual check (Windows build): forest borders show a shrub belt on both sides; no straight hex-shaped forest outlines at default zoom.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. Look at a forest from the side: the edge rises gradually – tall grass and shrubs in the open, then shrubs and small trees, then the forest.
2. Look from above at default zoom: forest outlines are ragged and natural, not hexagons.
3. Inside forests: the floor has low green cover between trunks.
4. A unit standing on a plains tile next to a forest is still clearly visible (shrubs don't cover it). Report if they do.
5. Frame rate unchanged within a few percent.

## Player manual

None (presentation only; the shrubs on plains tiles next to forests are decoration and give no cover – mention it only if players are likely to mistake them for forest; proposed: one line in section "Terrain": "Bushes along forest edges are scenery; only forest tiles give the forest bonus.").

## Out of scope

- Hedgerows/field boundaries (TASK-035), clearings inside forests, tree falls.

## Implementation notes

_Filled in by the agent when done._
