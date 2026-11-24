# TASK-219b: Railways (2/3) – track bed, sleepers, rails, embankments, bridges, tunnels

- **Status**: blocked
- **Layers**: presentation (`RailwayPlanner` next to `FeatureRibbonPlanner`, `Railways` drawer, `assets/shaders/rail.gdshader`) + data (`data/` Resource with widths per class)
- **Depends on**: TASK-219a, TASK-134 (terrain LOD, exact surface), TASK-108c (bridge machinery); soft: TASK-202
- **Sections**: ARCHITECTURE "Terrain rendering" (ribbons), "River water and bridges"; code (grep CODEMAP): `FeatureRibbonPlanner`, `FeatureRibbons`, `bridge_sites.gd`, `bridges.gd`, `MapScale`
- **Model**: opus (smoothed gradient profile, cut / embankment geometry)
- **Tags**: battle-look

## Goal

Railway lines are drawn at real scale: a gravel ballast bed with sleepers and two steel rails (single or double track, sidings), running as flat as real railways do – on embankments over dips, in cuttings through rises – with bridges over rivers and roads and tunnel portals. `true` preset only; `balanced` / default unchanged.

## Decisions / assumptions

- **[ASSUMPTION]** Widths (metres, in `data/`): standard gauge 1.435 between rail heads, sleepers 2.6 m long every 0.6 m, ballast bed 4.2 m wide (6 m shoulder on main lines), double track 4.2 m centre spacing, siding / yard like single. Tram / light rail: embedded rails with a 3 m paved strip. Dismantled (class 7): only a grassy embankment strip, no rails.
- **[ASSUMPTION]** Profile: the centre line height is a low-pass smoothed terrain profile (window ~80 m, max gradient 2.5 % main / 4 % others, clamped to the terrain by ≤ 6 m of fill or cut). Embankment shoulders and cutting slopes (1:1.5) blend into the terrain over the verge; the terrain itself is not carved (the mesh covers the cut and the shoulder mesh hides the seam). Bridges (flag) reuse the span machinery; a line over a road or river keeps its smoothed height, and the road ribbon under it is unchanged. Tunnels (flag): ribbon and bed end in a concrete portal; underground part is not drawn.
- Rails and sleepers are drawn by shader on one ribbon (same approach as road ruts: a texture / procedural pattern in metres), not as per-sleeper geometry; rail head highlights only close up. One material per class family, no per-instance geometry; frame time within 0.3 ms.
- Crossing a road at grade: the road ribbon is lifted by the existing ROAD_LIFT step over the rails; the crossing panels (asphalt across) belong to 219c.

## Acceptance criteria (testable)

- [ ] `data/` Resource with widths per class; planner uses only those numbers (test changes a value, output follows).
- [ ] Planner on a main-line fixture: ballast width 4.2 m (single), double track centres 4.2 m apart, sleepers 0.6 m pitch, gauge 1.435 m, in metres via `MapScale`; a siding is single track with the narrower bed.
- [ ] Gradient: on a 15 % hillside fixture the centre line stays ≤ 2.5 % (main) / 4 % (others) and within 6 m of the terrain; on flat ground it equals the terrain height ± 0.05 m.
- [ ] Embankment and cutting: shoulder / slope geometry meets the terrain with no gap > 0.1 m and no vertex below the terrain edge (fixtures: fill 3 m, cut 3 m).
- [ ] Bridge flag over a river fixture: span and deck follow `bridges.gd`; `bridge_sites` / `bridges` output for river bridges identical before and after; a line crossing a road on a bridge leaves the road ribbon unchanged; at-grade crossing lifts the road by ROAD_LIFT with no coplanar overlap.
- [ ] Tunnel flag: bed ends in a portal at both ends, nothing drawn between.
- [ ] Dismantled class: embankment strip only; no rails.
- [ ] Determinism: same map twice -> identical output. `balanced` preset: planner output for a rail fixture is empty (test); maps without rail data unchanged.
- [ ] Budget on `true` at Suwałki: planning < 20 ms per chunk, ≤ 4 extra draw calls per chunk view, frame time within 0.3 ms of before, 60 FPS kept.
- [ ] Screenshots (Read) of a single line over fields, a cutting, an embankment, a bridge over a river at camera distance 0.4 / 1.2 / 5, compared with the look reference (TASK-190); deviations stated.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle` on the `true` scale: follow the railway – ballast bed with sleepers and rails, flat course on embankments and in cuttings, no gaps at the foot of the slope.
2. Bridges over rivers and roads: no z-fighting, road under the bridge unchanged.
3. Default scale: no railways drawn, everything as before.

## Player manual

docs/MANUAL.md "Roads and rivers": on the true-size scale railways are drawn as lines with ballast, sleepers and rails; purely visual.

## GDD

No rule changes.

## Out of scope

- Infrastructure (TASK-219c); trains and rolling stock; carving the terrain; yards as detailed layouts; rail movement / supply rules.

## Implementation notes

_Filled in by the agent when done._
