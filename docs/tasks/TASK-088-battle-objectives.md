# TASK-088: Per-battle victory conditions and turn limit (`BattleObjectives`)

- **Status**: ready
- **Layers**: core (+ ai, + minimal HUD text)
- **Depends on**: – (soft: TASK-086)
- **Model**: opus (end-of-game rules touch every command, AI goal change)

## Goal

Each battle defines how it is won and how long it lasts (GDD "Vision decisions"), instead of always "eliminate all enemy units" – the base for battles started from the operational map.

## Acceptance criteria (testable)

- [ ] `BattleObjectives` resource (`src/core/data/`): `turn_limit` (0 = none) and a list of conditions, each for one player or both:
  - `hold_hexes` – at the end of the battle (turn limit) the player holds the listed hexes (a hex is held by the last side that had a unit on it; initial owner set in the data);
  - `take_hexes` – the player has a unit on all listed hexes at the end of any own turn → immediate win;
  - `destroy_share` – the enemy has lost ≥ X % of its starting total HP → immediate win;
  - `eliminate` – today's rule (kept as a condition, the default battle uses it).
- [ ] Turn limit: when the last player's turn of turn `turn_limit` ends, the battle ends; the winner is decided by the `hold_hexes` / victory-point rule in the data; if nobody qualifies it is a **draw**. `game_over` carries `winner` (−1 = draw) and `reason` (`&"objective_taken"`, `&"enemy_destroyed"`, `&"turn_limit"`, `&"eliminated"`); add the fields to the event table in docs/ARCHITECTURE.md.
- [ ] Objective hexes and their owner live in the state, are in `snapshot()` and survive replay (`MatchRecord`), with a test.
- [ ] `Scenario.default_battle` keeps `eliminate` + no turn limit → all existing tests and the simulation statistics stay the same.
- [ ] A second test scenario with `take_hexes` + `turn_limit = 8` exists; the AI moves toward objective hexes when it has an objective condition (simple: objective distance in its move scoring); `tools/simulate.sh` reports draws by turn limit separately from the harness limit.
- [ ] HUD: the turn bar shows "Turn 3 / 8" when there is a limit; objective hexes have a simple marker (placeholder, presentation-engineer may restyle later).

## Playtest (for the human)

1. Start the objective test scenario (debug option); capture the marked hexes before turn 8 → win screen with reason.
2. Let turn 8 run out → draw / hold result.

## Player manual

Victory conditions and turn limits per battle; how holding a hex works.

## Out of scope

Deriving objectives from the operational map (TASK-094), victory points per unit type.

## Implementation notes

_Filled in by the agent when done._
