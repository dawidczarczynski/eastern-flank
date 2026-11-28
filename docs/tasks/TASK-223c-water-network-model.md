# TASK-223c: Water network (3/7): `WaterNetwork` in core – reaches, bodies, junctions, water surface profiles

- **Status**: blocked
- **Layers**: core (`WaterNetwork`, pure, immutable after build)
- **Depends on**: TASK-223b, TASK-223a
- **Sections**: ADR 0034 decisions 1, 2, 5
- **Model**: opus
- **Tags**: battle-look

## Goal

One model of all water that rendering and rules read, whose water surface is hydrologically consistent: rivers never run uphill, tributaries and lakes meet at one level.

## Acceptance criteria (testable)

- [ ] `WaterNetwork.build(map data, DEM sampler)` → reaches (polyline in world metres, per vertex: width, surface height, bed depth, bank height and steepness left / right, current), bodies (polygon with holes, level), junctions (confluence, inflow, outflow, with the shared level), crossings (bridges, fords). Queries: `surface_at(p)`, `water_at(p) -> reach / body / none`, `crossings_of(segment)` (every water polygon a straight move crosses, with entry / exit points).
- [ ] Surface profile: DEM sampled along the line, smoothed over ~200 m, non-increasing downstream, pinned to the lake level at an inflow / outflow and to the main river at a confluence (a tributary is solved after its main river, lakes first).
- [ ] Bed depth by width (stream 0.5–1 m … 60 m river 4 m, a table in a `.tres` resource, not constants); bank height from the DEM above the surface; cut bank on the outer side of a bend (curvature above a threshold), low bank on the inner side.
- [ ] 223a's validator runs on the network: zero `surface_rises`, `junction_step`, `lake_step`, `steep_water` on Suwałki (the terrain rules wait for 223d).
- [ ] Deterministic (same input → identical network), no `GameState.rng`; build time on Suwałki theatre cut measured and < 300 ms.

## Playtest (for the human)

None visible yet; the validator report shows the surface rules at zero.

## Player manual

None.

## Out of scope

- Terrain shaping (223d), rendering (223e), rules (223f).

## Implementation notes

_Filled in by the agent when done._
