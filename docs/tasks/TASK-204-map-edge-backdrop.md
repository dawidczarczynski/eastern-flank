# TASK-204: Map edge and backdrop at real scale – no visible end of the map

- **Status**: ready
- **Layers**: presentation (`BackdropMesh`, `BackdropTypes`, `BackdropHeights`, `BackdropCanopy`, `ForestShell`, `TreeField`, `MapView`), data (`TacticalLayer` / `LandCover` margin beyond the playable rect)
- **Depends on**: TASK-135, TASK-108g, TASK-190, TASK-192b, TASK-189 (all done)
- **Sections**: ARCHITECTURE "Real-scale vegetation", "Chunked lazy world"; ADR 0024, 0026, 0027, 0028; TASK-052 (backdrop ring); look reference (TASK-190)
- **Model**: opus (data beyond the playable rect, LOD of a large ring, seams)
- **Tags**: battle-look

## Goal

The end of the playable map does not show: the landscape continues past it as real terrain with the same forests, colours and haze, and fades into the horizon – instead of dense forest stopping at a line in front of a flat, featureless olive plain with a few dots for trees (human, 2026-11-21; `.screenshots/edge/east_edge_a.png`).

**Top requirement (human, 2026-11-23: "above all, the map border must not be hexes like now, raised up like rocks")**: the terrain must not end in a hex-shaped, raised step (a rock-like wall of border hexes above the ring). Heights are continuous across the border and the border outline follows the landscape, not hex edges.

## Decisions (human interview, 2026-11-23)

0. The map border is not a hex-shaped raised step: heights continue smoothly across it and the outline follows the landscape (see the first criterion).

1. Ring width stays `BACKDROP_WIDTH` = 14 units (~2 km); haze (TASK-190) hides the far end.
2. Where no real data exists beyond the theatre layer, keep the current fallback: border copy of the tiles with the same fade.
3. Ring trees: tree impostors (GPU-placed, ADR 0027) in the inner part of the ring up to the impostor range, canopy shell (`BackdropCanopy` / `ForestShell` look) beyond; no step in density, colour or brightness at the map border.
4. Camera clamp stays (`CameraMath.clamp_target`, `CLAMP_MARGIN` 2.0 in `camera_rig.gd`); only verify, change code only if a void shows.

## Already in place (do not redo)

- `BackdropTypes` continues the real land-cover raster beyond the cut (`shares_at` / `forest_at` / `ring_type` via `CoverLook`, TASK-108g, ADR 0028; `LandCover.for_map` takes a margin for the backdrop) and falls back to border-tile copies outside the raster.
- Cause of the rock-like hex step (code read, to confirm by measurement as the first step of the task): the seam itself has no crack (`BackdropMesh` inner row = `TerrainLattice` border heights). The step comes from (a) `TerrainSurface` on authored/real maps: heights flatten around each tile centre (`_CORRECTION_FULL` 0.35, smoothstep blend of 3 centres), so border hexes read as plateaus whose outline is the hex edge; (b) `BackdropHeights.height` does not continue the surface outward: it repeats the nearest border height, eases towards `MEAN_LEVEL` 0.35 (60 % by 12 units) and adds noise of ±`NOISE_AMPLITUDE` 1.1 fading in over 5 units, so a high border hex stands above a lower ring; (c) the ground / forest / village cut follows border hex outlines. The criteria target these three.
- The remaining visual problem: flat olive ring, sparse dots for trees (`BACKDROP_SCATTER_REACH` 4.0 units), ring `BACKDROP_VALUE` 0.85 / `BACKDROP_SATURATION` 0.7 make the border visible, hard step against the dense map forest.

## Acceptance criteria (testable)

- [ ] No hex-shaped raised step at the border: on Suwałki border hexes of differing elevation (test picks the highest and the lowest border hex), the height difference between the last playable mesh vertex row and the first ring row is ≤ 0.1 world unit, and the slope across the seam (|Δh| per unit over 1 unit each side) differs by ≤ 0.15.
- [ ] The ring continues the real DEM outward (or, outside the DEM, extrapolates the border slope) instead of repeating the border height: max |ring height − DEM| ≤ 0.1 within 2 units of the border; noise at the border is 0 and eases in only beyond 2 units, amplitude ≤ 0.3 within 5 units (constants may change; `balanced` / LOW keep today's values).
- [ ] The border outline follows the landscape: the height field within 1 unit of the border has no hex-edge plateau (variance of the height along the border line vs. a hex-agnostic smoothed DEM ≤ 0.1 unit RMS; test on Suwałki), and forest / ground cover crosses the border without a hex-shaped cut.
- [ ] On Suwałki the land-cover raster margin (layer cut margin) is ≥ `BACKDROP_WIDTH` (14 units) on all four sides; a test asserts `shares_at` returns raster data (not the fallback) at the outer ring corner points.
- [ ] Where the raster does not cover a ring point (synthetic map at the layer edge), `BackdropTypes` returns the border-tile copy and the fade is identical to today (test, fixed seed).
- [ ] `BackdropHeights` uses real DEM beyond the playable rect where the layer has it (max |height − DEM| ≤ 1 height step at 20 sample points in the ring); outside the DEM it keeps edge-clamp plus noise (test; state the finding in the notes).
- [ ] Tree impostors cover the ring from the map border out to the impostor range (ADR 0027), placed on the GPU with no per-tree nodes; ring forest cells have tree density within ±15 % of the adjacent map cells at the border (test on planned counts).
- [ ] Beyond the impostor range the canopy shell (`BackdropCanopy` / `ForestShell`) covers the ring forest cover; the two zones overlap with a cross-fade, no gap (test: every ring forest cell is covered by impostors or shell).
- [ ] No step at the border: mean luminance of a 32 px strip on each side of the border differs ≤ 10 % at distances 5, 12 and 24 over the east, south and a corner edge (screenshot crop comparison).
- [ ] Ground colour and detail continue across the border: satellite colour / ground splat (TASK-192b) covers the ring; `BACKDROP_VALUE` / `BACKDROP_SATURATION` retuned (target values written in the notes) so the border is not visible at 5, 12, 24.
- [ ] The hex-shaped cut of forest, bare ground and villages at the border is gone; the hex overlay may end at the border, the landscape may not.
- [ ] The ring's outer edge ends in haze (TASK-190) and sky: no rim, seam or hard cut at any camera height and yaw; checked at the lowest pitch.
- [ ] Camera clamp unchanged (verify only): at the widest zoom over all four edges and four corners the view shows landscape to the horizon, no void (screenshots); code changes only if a void shows, and then recorded in the notes.
- [ ] Ring planning stays off the main thread and chunked (ADR 0024): memory and plan cost of the ring recorded; frame time at 1.2 / 5 / 24 over the east, south and a corner edge ≤ 16.7 ms (RX 580, `true`, HIGH, 720p).
- [ ] `balanced` and LOW look unchanged apart from the shared data path (golden test of the backdrop output, existing values compared).
- [ ] Screenshots Read: four edges and a corner at 5 / 12 / 24 before and after, compared with the reference views (human, 2026-11-21).

## Assumptions

- **[ASSUMPTION]** If the layer cut margin is shorter than 14 units, it is raised to cover the ring (bigger layer cut, accepted memory cost recorded in the notes).
- **[ASSUMPTION]** Only the `true` preset gets the new ring trees and ring colour retune; `balanced` / LOW keep today's look.
- **[ASSUMPTION]** Retuned value / saturation may become per-preset constants in `map_view.gd`; any balance-like numbers stay in constants next to the existing `BACKDROP_*`, not in game rules.
- **[ASSUMPTION]** No GDD change: no rule changes.

## Playtest (for the human)

0. Look at every edge and corner from low pitch: the border is not a rock-like wall of hexes; the ground rises and falls smoothly into the ring.
1. `true` preset, Suwałki: pan to every edge and corner at several zooms – the landscape continues, forests and fields do not stop at a line, the far end fades into haze.
2. Zoom to the widest view over an edge and a corner: no flat plain, no hard rim, no void.
3. Switch to `balanced`: look is as before.

## Player manual

None (look only).

## Out of scope

- Making the ring playable; the operational map's own borders; terrain outside the theatre layer (falls back to the border copy); widening the ring or the camera clamp.

## Implementation notes

_Filled in by the agent when done._
