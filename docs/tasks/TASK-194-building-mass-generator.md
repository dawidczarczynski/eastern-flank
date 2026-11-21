# TASK-194: Procedural building masses – footprint + type to a 3D mesh

- **Status**: idea
- **Layers**: presentation (pure mesh builders in `src/presentation/buildings/`)
- **Depends on**: TASK-193
- **Sections**: ADR for buildings (TASK-193); `src/presentation/models/` for the procedural-mesh habit
- **Model**: opus
- **Tags**: battle-look

## Goal

A building footprint with its tags becomes a believable 3D mass: walls extruded to the right height, a roof of the right shape, chimneys, silo / tower cylinders – generated deterministically from the data, with sensible defaults where OSM is silent.

## Acceptance criteria (testable)

- [ ] `BuildingMass.build(footprint, tags, seed) -> mesh arrays` is pure and deterministic (same input, same mesh); walls get per-wall UV in metres (u along the wall, v height) and a wall id / orientation so the facade shader (TASK-196) knows the street side.
- [ ] Roofs from the footprint: gable (along the longest side – via the minimal-area bounding rectangle), hip, flat, mono-pitch, skillion for halls; pitch by type and region (house 30–45°, barn 25–35°, block flat or 5°); eaves overhang; non-rectangular footprints fall back to a flat or hip roof of the polygon (straight skeleton or a robust approximation).
- [ ] Heights: `height` tag, else `levels x floor height` (3 m, ground floor 3.5–4 m in blocks), else a type default (house 2 floors, barn 6 m, hall 7–9 m); defaults are data in `data/**/*.tres`.
- [ ] Extras: chimneys on houses (hashed), roof ridge detail, silo (cylinder + dome + cone options), tower / chimney cylinders, simple annexes for L-shaped footprints.
- [ ] Triangle budget per building recorded (house <= 120, block <= 200, hall <= 150 tris at LOD0) and a coarse LOD1 (box + roof, <= 24 tris) built from the same data.
- [ ] Tests: mesh bounds equal the footprint and height; roof ridge lies over the longest axis; holes (courtyards) produce an inner wall ring; degenerate footprints (collinear, tiny, self-touching) never crash and produce nothing or a box.
- [ ] A catalog page (screenshot via `tools/render_unit.sh`-like tooling or a `SCREENSHOT_SCENE`) renders 12 sample buildings side by side; the agent Reads it.

## Playtest (for the human)

1. Open the building sample sheet: houses, barns, blocks, halls and silos read as such; roofs follow the footprint.

## Player manual

None.

## Out of scope

- Textures and facades (TASK-196); placing buildings on the map (TASK-195); landmark buildings (TASK-197).

## Implementation notes

_Filled in by the agent when done._
