# TASK-205: Continuous tactical space (1/9): `TacticalMap` and `TacticalSpace`

- **Status**: ready
- **Layers**: core
- **Depends on**: –
- **Sections**: ADR 0029; ARCHITECTURE "Coordinates"
- **Model**: opus
- **Tags**: continuous-space

## Goal

The types the rest of the continuous-space work stands on, added **beside** `Hex` / `HexGrid` (nothing switches yet): a battle map that answers terrain questions at any metre point, and position helpers.

## Acceptance criteria (testable)

- [ ] `TacticalSpace` (pure, static): `snap(Vector2) -> Vector2` to a 1 cm grid (deterministic, idempotent), `distance`, `facing_of(from, to)`, conversion to / from the world `Vector3` of `TerrainSurface`; tests incl. snap idempotence.
- [ ] `TacticalMap` (`RefCounted`): built from an existing `HexGrid` + `LandCover` + roads / rivers (and from a generated map); `terrain_at(p)`, `height_at(p)`, `cover_at(p)` (land cover class), `road_at(p)`, `river_at(p)`, `in_bounds(p)`, `size_m`. Values agree with `HexGrid` / `TerrainSurface` at hex centres (test on `Fixtures` maps).
- [ ] Every query is defined off the map (returns impassable / out of bounds, no error).
- [ ] No `Node`, no autoload, no `GameState.rng`; existing tests untouched and green.

## Playtest (for the human)

None (core only).

## Player manual

none

## Out of scope

- Changing `GameState`, commands or the view (TASK-208 and later).

## Implementation notes

_Filled in by the agent when done._
