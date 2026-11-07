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

## Look (Claude Design)

Reference: [docs/design/operational_map/README.md](../design/operational_map/README.md) ("Front line", "Line hierarchy"). The line is a px-width ribbon lying on the relief; the teeth are screen-space and evenly spaced in pixels, so the tilt of [TASK-125](TASK-125-staff-map-restyle-2-5d.md) never makes them uneven.

- [ ] Width **2.4 / 3 / 3 px** at Z0 / Z1 / Z2 (constant in screen pixels); **teeth 5.5 px long every 15 px**, pointing to the enemy as seen by the viewer (flip when the viewer changes).
- [ ] Smoothed variant (edge midpoints + **Chaikin ×3**) by default; the exact hex-edge polyline when the grid is shown (`G`, Z2) and as a debug option. Test: both variants have the same endpoints; the smoothed one has no vertex further than 1 hex from the exact one **[ASSUMPTION]**.
- [ ] Rebuilt only on `formation_moved` / `operational_turn_started` / viewer change (as above), never per frame.
- [ ] **Differs from the reference:** it derives the front from hex control (RU hex vs NATO hex); ours comes from `FrontLine.ownership` (nearest formation within 3 hexes). Our rule stays. "No front against a closed country" is **not adopted** here (needs TASK-114 / 116).
- [ ] Territory tint (T): own / enemy at ~5 % alpha (`side.own` / `side.enemy`, as the reference's country tint) **[ASSUMPTION]**.

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
