# TASK-220: Bridges – study and specification: road and rail bridge types, load capacity, river-crossing mechanic

- **Status**: idea
- **Layers**: design study (game-designer; no code) → follow-up tasks for core (load capacity, crossing rules, data), importer and presentation
- **Depends on**: TASK-108c (soft: TASK-219a railway data, TASK-218b overpasses, TASK-216 river widths)
- **Tags**: battle-look
- **Model**: opus

## Goal

Bridges stop being one concrete deck: a few real road and railway bridge types with their own look, size and **load capacity**, so that crossing a river becomes a real mechanic (heavy vehicles need a bridge that carries them; a blown or weak bridge matters). This task produces the specification and splits it into implementation tasks – it does not implement them.

## Questions to settle (with the human, then write the results into the GDD)

1. **Types** (look and size, with real examples from the Suwałki region / Poland): road – small culvert-like slab bridge over a stream, beam bridge on piers (the typical 10–40 m concrete bridge), steel truss, arch / stone bridge, pontoon / military bridge, ford (no bridge); rail – single-track girder, double-track, truss; combined. Which of them are needed for the theatre; dimensions per type (width, span range, height, piers, railings) in metres, model budget (triangles, one merged mesh).
2. **Where the type comes from**: OSM (`bridge=*`, `bridge:structure`, `maxweight`, `width`, `layer`, `man_made=bridge` polygons, `railway` + `bridge=yes`) vs. rules from road / rail class and river width (TASK-216). What the importer must store per crossing; a determined default when no data.
3. **Load capacity**: a number per bridge (tonnes, from `maxweight` or by type and road class, e.g. 3.5 / 12 / 30 / 60 t), unit **weight classes** (unit catalog: light 3–10 t, medium, heavy MBT 40–65 t, tracked/wheeled, engineers' bridge-layers), and the rule: can a unit step over a bridge / how an overweight unit is handled (blocked, slowed, risk of collapse, crossing one at a time). Must stay consistent with TASK-108 river rule (road link = no +1) and the invariant that every unit can enter every passable hex from a full move – decide what changes for hexes with a river and how the operational layer (staff map routes) sees bridges.
4. **Interaction**: destroying bridges (engineers, artillery, demolition orders), capture intact, reconnaissance ("is the bridge standing / what does it carry") and fog of war (TASK-007), AI use of bridges (routes, objectives), fords and engineer bridging as alternatives.
5. **Presentation**: an icon / marker for load capacity on the map and in the hover panel (needs a mockup – `/design-ui`), the bridge models per type, how a damaged / destroyed bridge looks, railway bridges with TASK-219b/c.
6. **Data**: types and capacities as resources (`data/**/*.tres`), per-crossing data in the map data; migration for maps without bridge data.

## Deliverables

- GDD section "Bridges" (types, capacity classes, crossing rules, numbers) and an ADR if the data model changes.
- Follow-up tasks (core rules + data, importer, models per type, UI marker, AI, optional demolition) written with acceptance criteria and put in BACKLOG order; marked `battle-look` where visual.

## Out of scope

- Any implementation; pontoon-bridge deployment and demolition mechanics beyond what the study decides to schedule.

## Implementation notes

_Filled in by the agent when done._
