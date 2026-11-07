# TASK-093c: Staff map (3/3) – front line, completes the staff map

- **Status**: blocked
- **Layers**: core (pure helper) + presentation + docs
- **Depends on**: TASK-092e
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The map shows who holds what: a front line drawn between the blocs and recomputed after every event, so the human reads the operational situation at a glance after orders have moved the counters (GDD "Operational map view" → "Front line"). Closes the staff-map track; TASK-094 (contact notice) and TASK-119 (political layer) build on this scene.

## Acceptance criteria (testable)

- [ ] Pure helper `FrontLine` (`src/core/operational/front_line.gd`, static): each land hex within 3 hexes (`FRONT_RANGE`, data on the operation, **[ASSUMPTION]**) of a formation belongs to the side of the nearest formation by hex distance; ties belong to nobody; water and unreached hexes belong to nobody. `ownership(state) -> Dictionary` (coord → player) and `edges(state) -> Array` (hex edges between hexes of different sides, ordered into polylines). Tests on hand-made grids: one formation per side 6 apart → a single straight line between them; a tie hex stays free; a lake hex is never owned; a formation move changes the line; deterministic.
- [ ] Drawn as a thick line with small teeth towards the enemy (relative to the viewer), plus a faint own / hostile territory tint (toggle **T**); recomputed on `formation_moved`, `operational_turn_started` and when the viewer changes; no per-frame work (measured, noted).
- [ ] The line never changes the simulation (rule 3; test: `OperationalState.snapshot()` is identical with and without the view).

## Playtest (for the human)

1. Open **Operation**: a line runs between the Polish and Russian groups; the teeth point away from your side.
2. Give an order to a battalion (TASK-092d), end the turn: after it moved the line bends around it. Move one formation far forward and see a salient.
3. Press **T**: territory tint on / off. Switch viewer: teeth swap sides.

## Player manual

Section "Front line" in the "Operational map" chapter (what the line is and what the tint means; it is a display, not a rule).

## Out of scope

- Hex control as a rule (supply, TASK-096); country borders (TASK-119).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
