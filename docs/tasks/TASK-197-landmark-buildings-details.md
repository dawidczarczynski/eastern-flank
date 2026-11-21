# TASK-197: Landmark buildings and close-up building detail

- **Status**: idea
- **Layers**: presentation (building templates, `src/presentation/buildings/`)
- **Depends on**: TASK-194, TASK-196
- **Sections**: ADR for buildings (TASK-193); `/model-unit` habit for reference images
- **Model**: opus
- **Tags**: battle-look

## Goal

The buildings a player recognises – churches, silos and grain elevators, water towers, factory chimneys, town hall / station / school – look like themselves, and ordinary buildings hold up when the camera comes within ~100 m.

## Acceptance criteria (testable)

- [ ] Templates (pure mesh builders on the same API as TASK-194) for: church (nave + tower + steep roof, tower spire / onion by region), grain silo cluster, water tower, factory hall with chimney and ventilators, chimney / cooling tower, barn with ramp, kiosk / shed, petrol station canopy; OSM tags (`building=church`, `man_made=silo|water_tower|chimney`, `amenity=place_of_worship`, `shop`, `railway=station`) choose the template, with footprint fitting rules.
- [ ] Close detail by rule at LOD0 only: window frames and sills as geometry, door steps, gutters and downpipes, chimney caps, roof ridge tiles, satellite dishes on blocks (hashed), fences are TASK-198.
- [ ] Per template a reference sheet (real photos' proportions from the research, recorded in the task) and a screenshot at 0.4 / 1.2 distance; the agent compares them and states deviations.
- [ ] Triangle budgets per template recorded; LOD1 provided; frame time over the densest village unchanged within 0.5 ms.
- [ ] Tests: each template builds for its sample footprints within bounds; tag selection picks the template; defaults when the tag is missing.

## Playtest (for the human)

1. Find the churches, silos and the factory areas of Suwałki: they read as such from 1 km and from 100 m.

## Player manual

None.

## Out of scope

- Interiors; destruction; exact copies of real buildings.

## Implementation notes

_Filled in by the agent when done._
