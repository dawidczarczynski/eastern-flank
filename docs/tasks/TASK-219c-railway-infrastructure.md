# TASK-219c: Railways (3/3) – catenary, signals, level crossings, stations, points

- **Status**: blocked
- **Layers**: data (rows in a `RailwayFurnitureRules` resource) + presentation (`RailwayFurniturePlanner` + drawer, reuse the MultiMesh chunking of `RoadFurniture` from TASK-218a)
- **Depends on**: TASK-219b, TASK-218a (planner / drawer pattern, sign atlas, rule resource pattern); soft: TASK-198
- **Sections**: ARCHITECTURE "Terrain rendering"; code (grep CODEMAP): `RailwayPlanner` (219b), `RoadFurniturePlanner` (218a), `bridge_sites.gd`, building templates used by settlements (TASK-194 … 198)
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Railways look like working lines: electrified lines carry masts and wire, signals stand at stations and crossings, roads cross rails at proper level crossings with barriers, stations have platforms and a small building, sidings join the main line through turnouts. Placement is **rule-based per rail class** (flags from TASK-219a); only stations, halts and level-crossing positions come from imported points. `true` preset only.

## Decisions / assumptions

- **[ASSUMPTION]** Rules (in a `data/` resource, spacing / offset in metres):

| Kind | Rule |
|---|---|
| Catenary masts (7 m, portal masts every 4th over double track) + one contact wire and catenary wire as a thin ribbon | electrified lines; mast spacing 60 m, 3.2 m from the track centre; on bridges and in tunnels none |
| Signals (colour-light mast, static colour, no light emission) | main / secondary lines: 200 m before each station, level crossing and junction with a siding; both directions on double track |
| Level crossing: asphalt crossing panels across the rails, 2 half-barriers + St Andrew's cross signs + warning lights (static) | at imported crossing points, else at every at-grade road-rail crossing of road class ≤ 4; barriers only on class 1-4 roads, a cross sign only on tracks / class 5-6 |
| Station / halt: 2 side platforms (or one island on double track), 120 m × 3 m, 0.9 m high, shelter, lamp posts every 30 m, name sign; station building from an existing building template on the settlement side of the track | imported station points; a halt has no building |
| Turnouts: a visible fan (two rails diverging over 30 m) + point lantern | where a class-3 link branches off a class 1-2 link |
| Fences / posts: wire fence both sides in settlements, boundary posts every 100 m in open land | main and secondary lines |
| Culverts: concrete portal under an embankment where a river or ditch crosses | where a river link crosses an embankment tile |

- **[ASSUMPTION]** Reuse the road-furniture machinery: one MultiMesh per kind per chunk, shared meshes (< 300 triangles), visibility ranges (masts / signals 300 m, platforms 600 m), deterministic hash placement, planning < 20 ms per chunk. Wires are drawn as one thin ribbon per chunk, not per span.
- Level crossings change the road ribbon (panels) in the 219b / TASK-202 ribbon planner through a small hook, no change to the rail geometry.

## Acceptance criteria (testable)

- [ ] Rule resource loads; no numbers hard-coded in the planner (test changes a value, output follows).
- [ ] Electrified 1 km straight fixture: masts every 60 m ± 1 m on the correct side, wire present; non-electrified: none; on a bridge / tunnel tile: none.
- [ ] Double-track electrified fixture: portal masts every 4th position span both tracks.
- [ ] Signals: 200 m ± 5 m before a station point and before a level crossing, one per direction on double track; none on sidings.
- [ ] Level crossing at an imported point and at a geometric road-rail crossing: panels cover the road width across the rail bed, barriers on both sides for road class ≤ 4; a track (class 5) gets a cross sign without barriers.
- [ ] Station fixture: platforms 120 m ± 1 m long beside the track without overlapping the ballast bed; building on the settlement side; a halt has no building.
- [ ] Turnout at a class-3 branch: fan of two rails diverging over 30 m; none for a class-1 ↔ class-1 junction.
- [ ] Furniture never overlaps road ribbons (except crossing panels), water or buildings; determinism; `balanced` preset and maps without rail data unchanged (tests).
- [ ] Budget on `true` at Suwałki: planning < 20 ms per chunk, ≤ 8 extra draw calls per chunk view, frame time within 0.3 ms of before, 60 FPS kept.
- [ ] Screenshots (Read) of an electrified line, a level crossing, a station and a siding junction at camera distance 0.4 / 1.2 / 5, compared with the look reference (TASK-190); deviations stated.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle` on the `true` scale: the electrified line carries masts and wire, signals before stations and crossings.
2. A road crossing the track: barriers and crossing panels; a field track crossing: a cross sign only.
3. A station: platforms, shelter, building, name sign; a siding joins with a turnout.
4. Default scale: nothing of this appears; 60 FPS at the station (HIGH quality).

## Player manual

docs/MANUAL.md "Roads and rivers": on the true-size scale railways carry masts, signals, level crossings and stations; purely visual.

## GDD

No rule changes.

## Out of scope

- Trains, rolling stock and animation of signals / barriers; marshalling yards and depots as detailed layouts; real signal and switch positions from OSM; rail movement or supply rules.

## Implementation notes

_Filled in by the agent when done._
