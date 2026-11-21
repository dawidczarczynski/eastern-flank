# TASK-198: Villages and towns as places – plots, fences, yards, garden trees

- **Status**: idea
- **Layers**: presentation (`SettlementDecor`, scatter planners)
- **Depends on**: TASK-195
- **Sections**: ARCHITECTURE "Chunked lazy world"; look reference (TASK-190); ADR 0026
- **Model**: sonnet
- **Tags**: battle-look

## Goal

A village is more than houses: plots with fences and hedges, yards, gardens, roadside trees and orchards give settlements the readable pattern of the reference images.

## Acceptance criteria (testable)

- [ ] Plot rules from the footprints and roads: a plot per building cluster (buffer of the footprint toward the road, bounded by neighbours and tile edges); fence or hedge line around it on the street side (hashed: wooden, mesh, hedge, none), gate toward the road.
- [ ] Yards and gardens: a ground patch of packed earth / gravel by the barn and house, a lawn / vegetable-bed texture (rows) on the rest of the plot; kept out of roads and forests.
- [ ] Trees and shrubs: garden trees and orchards (rows of apple / cherry from `building=farm` plots), road avenues and village-green trees (`natural=tree`, `highway` rules), through the existing scatter planners; individual trees at real size, deterministic.
- [ ] Everything is chunked on the building chunk layer (TASK-195), instanced, <= 1 ms main-thread build per chunk; frame time over the densest village within 0.5 ms of TASK-195's.
- [ ] Tests: fences stay outside footprints and off roads; orchard rows are regular; determinism of the plan; no objects on water or steep slopes.
- [ ] Screenshots Read: a village at 1.2 and 5 compared with the reference (human, 2026-11-21).

## Playtest (for the human)

1. Fly over villages: houses sit in fenced plots with gardens and trees, roads have avenues, farms have yards.

## Player manual

None.

## Out of scope

- Field parcels (TASK-200) and hedgerows between fields (TASK-199).

## Implementation notes

_Filled in by the agent when done._
