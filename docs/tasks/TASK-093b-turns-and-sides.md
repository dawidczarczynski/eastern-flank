# TASK-093b: Staff map (2/3) – operational turns, turn bar, End turn, playing either side

- **Status**: blocked
- **Layers**: core (`src/core/operational/`) + presentation (turn bar, side parameter) + docs
- **Depends on**: TASK-092b
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The operation has turns the human can click through: an **End turn** button hands the move to the other bloc and the turn bar shows turn number, date / time of day and the side to play. The human can play either bloc and the view switches perspective (friendly blue / hostile red) when the side to play changes in hot-seat (GDD "Operational turns", "Sides"). Split out of TASK-092b so that every task has a visible result.

## Acceptance criteria (testable)

Core (moved here from TASK-092b, same wording and tests):

- [ ] `EndOperationalTurnCommand` (`{"type": "end_operational_turn"}`), rejected with `battle_pending` while `pending_battles` is not empty (test: append a `BattleSetup` by hand).
- [ ] Apply: event `operational_turn_ended` (`player`), the other player becomes current, `turn` + 1 when the new current player is `first_player`, then event `operational_turn_started` (`player`, `turn`). Small private steps (e.g. `_switch_side`) – TASK-092e inserts order execution before `operational_turn_ended`.
- [ ] Example (test, `first_player` 1): turn 1 / player 1 → end → turn 1 / player 0 → end → turn 2 / player 1; events in that order with these fields.
- [ ] Codec round trip; `{"type": "end_turn"}` (the tactical type) and unknown / missing `type` → null.
- [ ] docs/ARCHITECTURE.md "Operational events": `operational_turn_ended`, `operational_turn_started`.

View:

- [ ] Turn bar (HUD v3 style, reuse TASK-077 parts): turn number, date and time of day (turn 1 = a fixed start date from the operation data, 12 h per turn, **[ASSUMPTION]**), the side to play with its colour, an **End turn** button and key **Enter / E**. The button is disabled with a tooltip reason while the command would be rejected.
- [ ] Turn banner when the move changes (TASK-080 notice) naming the bloc.
- [ ] The view has a `viewer_player` parameter (0 or 1, `--side=nato|russia` override, default NATO – a **[ASSUMPTION]**). Counters and frames are drawn friendly / hostile relative to it. In hot-seat v0 the viewer follows the side to play after each End turn (the human plays both until the AI, TASK-102, exists); a toggle in the turn bar ("follow side to play / fixed side") keeps one side's view.
- [ ] The viewer index never enters the operational state or snapshot (test: same snapshot whichever side is viewed – the TASK-092b rule).

## Playtest (for the human)

1. Open **Operation**. The turn bar says turn 1, the first side (Russia, `first_player` 1), date and time.
2. Press **End turn** (or Enter): banner "NATO to move", counters change from red to blue and vice versa (if "follow" is on), turn number stays 1; press again: turn 2, Russia.
3. Start with `--side=russia`: your own formations are friendly-blue-framed there. Switch the toggle to a fixed side and end turns: the perspective stays.
4. While a (test) pending battle exists the button is disabled with a reason (debug flag in the notes).

## Player manual

Section "Turns": alternating bloc turns of 12 h, End turn, which side you play and how to change the view.

## Out of scope

- Executing orders at turn end (TASK-092e); the enemy playing by itself (TASK-102); date-based events; a side choice screen when starting the operation (TASK-107).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
