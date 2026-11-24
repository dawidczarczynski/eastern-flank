# TASK-218b: Road furniture by road class (2/2) – roundabouts, traffic lights, overpasses

- **Status**: blocked
- **Layers**: data (rows in `RoadFurnitureRules`) + presentation (junction planner, overpass geometry next to `bridges.gd`)
- **Depends on**: TASK-218a (rule resource, planner, drawer, signs), TASK-108c (bridges: site finding, deck builder), TASK-202 (junctions, classes)
- **Sections**: ARCHITECTURE "Terrain rendering" (road ribbon bullet); code (grep CODEMAP): `bridge_sites.gd`, `bridges.gd`, `FeatureRibbonPlanner`, `RoadFurniturePlanner` (218a)
- **Model**: opus (new geometry: raised road over another, ramps matched to terrain)
- **Tags**: battle-look

## Goal

Junctions look like real ones: a simple roundabout in towns, traffic lights at main-road crossings in towns, and an expressway never crosses a lower road at grade – the lower road goes over it on a bridge with ramps. Rule-based per road class, no map data. `true` preset only.

## Decisions / assumptions

- **[ASSUMPTION]** Roundabout: a junction of roads of class ≤ 3 inside a settlement with ≥ 4 links gets an island disc (8 m radius), a ring ribbon and 4 yield signs; a T-junction does not. "Rozjazdy" is read as junctions; full motorway interchanges with slip roads are a follow-up.
- **[ASSUMPTION]** Traffic lights: only where class 2 crosses class ≤ 3 in a settlement; one set per crossing (a pole with a light head at each arm). No light emission animation beyond a static colour (one emissive material, no per-instance lights).
- **[ASSUMPTION]** Overpass: where a class-1 ribbon crosses a lower-class ribbon, the lower road is raised: deck 5.5 m above the class-1 surface, 24 m long, 9 m wide, 2 pillars + abutments, parapets (concrete), approach ramps 30 m each side at ≤ 8 % grade with embankment shoulders; the class-1 road stays at terrain height. Two class ≤ 3 roads crossing stay at grade. Reuse bridge-site finding and the deck mesh builder from `bridges.gd` where it fits.
- Performance as in 218a (< 20 ms planning per chunk, shared meshes, MultiMesh where repeated); overpasses are few and may be plain meshes.

## Acceptance criteria (testable)

- [ ] Rule rows for roundabout / traffic light / overpass live in `RoadFurnitureRules` (no hard-coded numbers); changing them changes output (test).
- [ ] 4-link class-3 junction in a settlement -> roundabout (island + ring + 4 yield signs); a T-junction and the same 4-link junction in open land -> none.
- [ ] Traffic lights only at class-2 ↔ class ≤ 3 crossings in settlements, one set per crossing; none elsewhere.
- [ ] Class-1 ↔ class-4 crossing fixture: deck 5.5 m ± 0.1 over the class-1 surface, ramps ≤ 8 % grade, the lower road ribbon follows ramp and deck with no vertex > 0.1 m off the drawn surface, class-1 ribbon unchanged; class-3 ↔ class-4 crossing -> no overpass.
- [ ] Furniture and overpass parts do not overlap other ribbons or buildings; existing `bridge_sites` / `bridges` output on a river-bridge fixture is identical before and after.
- [ ] Determinism, `balanced` preset unchanged (test), maps without class data get none.
- [ ] Budget on `true` at Suwałki: planning < 20 ms per chunk, frame time within 0.3 ms of before, 60 FPS kept.
- [ ] Screenshots (Read) of a roundabout, a signalised crossing and an overpass at camera distance 0.4 / 1.2 / 5, compared with the look reference (TASK-190); deviations stated.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle` on the `true` scale: find an overpass – ramps blend into the terrain, no gaps or z-fighting, pillars stand on the ground.
2. Find a town roundabout and a signalised crossing.
3. Default scale: roads look exactly as before.

## Player manual

docs/MANUAL.md "Roads and rivers": roundabouts, traffic lights and overpasses on the true-size scale; purely visual.

## GDD

No rule changes – GDD untouched.

## Out of scope

- Full motorway interchanges (slip roads, clover leaves), real roundabouts from OSM, railway crossings, tunnels, traffic and vehicles.

## Implementation notes

_Filled in by the agent when done._
