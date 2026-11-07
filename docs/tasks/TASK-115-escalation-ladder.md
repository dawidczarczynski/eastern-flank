# TASK-115: Escalation ladder – shared level as data, raise / lower with attribution, ROE by target class, sanctuary gate, allies join at Regional war, calm decay, threshold ends the operation

- **Status**: blocked
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data + presentation (level in the turn bar, notices, end screen)
- **Depends on**: TASK-114, TASK-094, TASK-093b (re-ordered 2026-11-01: the loop first – the threshold must also stop battles)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

One escalation level shared by both sides decides what may be struck, whether Russian soil is off limits, when the allies are dragged in – and ends the operation in defeat for the side that pushes it over the top (GDD "Operational layer" → "Escalation ladder"; human decision 2026-11-01). The player's choices to escalate or de-escalate (TASK-117) and the incidents of movement and strikes (TASK-116, TASK-097) all go through the functions of this task.

## Acceptance criteria (testable)

Data:

- [ ] `EscalationLevel` (sub-resource: `id`, `display_name` – English, translation key, `strike_classes: Array[StringName]`) and `EscalationLadder` (Resource, `src/core/data/escalation_ladder.gd`, `data/operational/escalation.tres`): `levels: Array[EscalationLevel]` (index = level), `sanctuary_open_level`, `allies_join_level`, `calm_rounds`, `sanctuary_breach_escalation`, `urban_strike_escalation`; `top() -> int` = `levels.size() − 1`; `problem() -> String` ("" when valid; one test per case: fewer than 3 levels, duplicate ids, `sanctuary_open_level` or `allies_join_level` outside 0 … top − 1, `calm_rounds` < 1, a negative escalation number).
- [ ] Shipped values **[ASSUMPTION]** (test reads the file): levels `contained` [formation], `limited_war` [formation, air_defence, depot], `open_war` [formation, air_defence, depot, airfield, c2], `regional_war` [same as open_war], `strategic_threshold` []; `sanctuary_open_level` 2, `allies_join_level` 3, `calm_rounds` 3, `sanctuary_breach_escalation` 1, `urban_strike_escalation` 1. The target class ids are the ones TASK-097 uses.
- [ ] `OperationDefinition.initial_escalation` (int, default 1; `suwalki_gap` uses 1); `Operation.from_definition` rejects a value outside 0 … top − 1 (`push_error`, null – test).

State:

- [ ] `OperationalState`: `escalation_level` (= initial), `escalation_floor` (= initial – the calm decay never goes below it), `escalation_caused: Array[int]` [0, 0], `escalation_deescalated: Array[int]` [0, 0], `last_raise_turn: Array[int]` [−1, −1], `calm_rounds` 0, `raised_this_round` false, `result: Dictionary` (`{}` while the operation runs, else `{winner, reason}`).
- [ ] `snapshot()` gains `escalation: {level, caused, deescalated, last_raise_turn, calm_rounds, raised_this_round}` and `result`. Determinism test of TASK-092b still passes.
- [ ] `OperationalSimulation.execute` rejects **every** command with `operation_over` while `result` is not empty (checked before the command's own `validate`; one place for all current and future commands – test with `EndOperationalTurnCommand`, `IssueOrderCommand` and TASK-094's `ResolveBattleCommand`).
- [ ] **No battle after the end**: when `result` becomes non-empty, `pending_battles` is cleared and no contact of the same end-of-turn step starts a battle (no `battle_started` after `operation_ended`). Test: a TASK-094 contact pending, then `raise` to the top → `pending_battles` empty, `ResolveBattleCommand` → `operation_over`.

Pure rules (`EscalationRules`, static, `src/core/operational/escalation_rules.gd`; tests on TASK-114's "strip" grid, `first_player` 0, start level 1):

- [ ] `raise(state, by: int, cause: StringName, steps := 1) -> Array[Dictionary]`: `by` must be 0 or 1 (else `push_error`, `[]`); `steps` ≤ 0 → `[]`. New level = min(level + steps, top); `escalation_caused[by]` += the steps actually taken; `last_raise_turn[by]` = `turn`; `raised_this_round` = true; event `escalation_changed` (`level`, `previous`, `by`, `cause`). Example: `raise(state, 1, &"test")` → level 2, caused [0, 1], event previous 1.
- [ ] **Allies join**: when a raise takes the level from below `allies_join_level` to it or above, then for each country in setup order: aligned S → `CountryRules.set_stance(belligerent, S, &"ladder", -1)`; neutral with leaning ≥ 0 → `set_stance(aligned, leaning, &"ladder", -1)`; others unchanged. Events: `escalation_changed` first, then the stance changes. Examples: strip from 2 to 3 → lithuania belligerent 0, belarus belligerent 1, in that order. With belarus first set neutral (`set_stance` aligned → neutral) → belarus becomes aligned 1, not belligerent. A raise that starts at or above `allies_join_level` triggers nothing.
- [ ] **Threshold**: when a raise reaches `top()`, `result` = `{winner: 1 − by, reason: &"escalation_threshold"}` and the last event is `operation_ended` (`winner`, `reason`, `by`). Example: from 3, `raise(state, 0, &"test")` → level 4, winner 1; then `EndOperationalTurnCommand` → rejected `operation_over`. `raise(..., steps = 2)` from 3 → level 4, caused += 1 (capped). Mirrored (both sides playable): from 3, `raise(state, 1, &"test")` → winner 0.
- [ ] `lower(state, by: int, cause: StringName) -> Array[Dictionary]`: level 0 → `[]`; otherwise level − 1, `escalation_deescalated[by]` += 1 when `by` ≥ 0, event `escalation_changed`. Floors are the callers' rule (calm: `escalation_floor`; *Stand down*, TASK-117: 0). Stances never revert.
- [ ] **Calm decay** at the round boundary – inside `EndOperationalTurnCommand.apply`, when play returns to `first_player` (after `operational_turn_ended`, before `operational_turn_started`): if `raised_this_round` → `calm_rounds` = 0, else `calm_rounds` + 1; when `calm_rounds` ≥ `ladder.calm_rounds` and level > `escalation_floor` → `lower(state, -1, &"calm")` and `calm_rounds` = 0; then `raised_this_round` = false. Examples (test, raises called between commands): a raise to 2 by player 1 in round 1, rounds 2, 3, 4 quiet → level back to 1 at the boundary after round 4 (event cause `calm`, `by` −1, caused unchanged [0, 1]); 10 more quiet rounds → still 1 (floor); a second raise in round 3 instead → the drop comes after round 6.
- [ ] **Sanctuary gate**: `CountryRules.may_enter` / `may_strike` treat an enemy sanctuary as open also when `escalation_level ≥ sanctuary_open_level`. Strip, player 0, (6, 0): level 1 false; level 2 true; back to 1 (never breached) false; breached at level 1 true. Mirrored with TASK-114's test copy where `poland.sanctuary = true`: player 1, (0, 0) level 1 false, level 2 true.
- [ ] `breach(state, player, country_id, at: Vector2i, formation_id: StringName) -> Array[Dictionary]` (used by TASK-116 for ground entry and by TASK-097 for strikes): only for an enemy sanctuary with `breached_by[player]` false – else `[]`. Sets `breached_by[player]`, event `sanctuary_breached` (`country`, `player`, `at`, `formation_id` – `&""` for strikes), then `raise(state, player, &"sanctuary_breach", ladder.sanctuary_breach_escalation)`. Second call → `[]`.
- [ ] **ROE for strikes** (called by TASK-097): `strike_allowed(state, player, coord, target_class) -> String` – `""` or, in this order, `own_soil` (the player's own country), `closed_country` (`may_strike` false), `roe_class` (class not in the current level's `strike_classes`, also for unknown classes). Strip, level 1: player 0 → (6, 0) `formation` `closed_country`, (4, 0) `closed_country`, (1, 0) `own_soil`; player 1 → (0, 0) `formation` `""`, `airfield` `roe_class`. Level 2: player 0 → (6, 0) `airfield` `""`.
- [ ] `strike_escalation(state, player, coord) -> int` – the steps a strike there would cause: `sanctuary_breach_escalation` if it would breach + `urban_strike_escalation` if the hex is URBAN. Strip at level 2, player 0: (6, 0) plains → 1; (6, 0) made urban → 2; after a breach → 1. `on_strike(state, player, coord) -> Array[Dictionary]` applies them (`breach`, then `raise(..., &"urban_strike", …)` for an urban hex) – TASK-097 calls it after a strike resolves.
- [ ] No `rng` draws anywhere in this task (test: `rng_state` unchanged after the examples).

Docs:

- [ ] docs/ARCHITECTURE.md "Two layers": `EscalationLadder`, `EscalationRules` (raise / lower with attribution, joining at the level, threshold, calm at the round boundary, sanctuary gate, ROE); "Operational events": `escalation_changed` (causes: `decision`, `declaration`, `alliance`, `sanctuary_breach`, `urban_strike`, `stand_down`, `calm`; TASK-121 adds `support_request`), `sanctuary_breached`, `operation_ended`; the `operation_over` rejection.

View (the level on the staff map):

- [ ] The **turn bar** (TASK-093b) shows the escalation level: number and name (e.g. `2 · Limited war`), colour rising from calm to red, five ticks. Hover/click opens a **ladder card** with the five levels, the current one marked, and the ROE of each (what may be struck) and sanctuary / allies markers – read-only, from the data.
- [ ] Every change shows a **toast** with the cause and the side that caused it ("Open war – NATO entered Russian soil"), including calm decay at the start of a turn ("Calm: level 2 → 1"). When the level reaches **Regional war** the allies' stance change is visible through the tints (TASK-114) and the toast says who joined.
- [ ] Reaching the top level ends the operation: a full-screen **end notice** names the side that caused it and the outcome (the causer loses), the pending battles are dropped, the staff map goes read-only (End turn / orders disabled with the reason), and a button returns to the menu. Scene-level smoke test: raising to the threshold via the state shows the end notice and disables End turn.
- [ ] the debug politics panel (**F9**, only with `--debug` – introduced in TASK-114; every action in it goes through the same commands / functions as the real decisions, so it is a test handle, not a rule) gains **Raise / Lower** buttons (attributed to a chosen side) so every effect above can be reached without waiting for movement (TASK-116) or decisions (TASK-117).

## Playtest (for the human)

1. **Operation** (`--debug`): the turn bar shows `1 · Tension` (or the first level's name from the data) with five ticks; click it: the ladder card lists the five levels and what may be struck at each.
2. F9 → Raise as NATO: toast "… raised by NATO", the bar changes colour; raise to Open war: the Russian-soil tint stops being hatched (sanctuary open); raise to Regional war: Lithuania and Belarus change tint (allies join).
3. End turns without raising: after 3 quiet rounds a toast reports the calm decay and the level drops by one.
4. Raise to the top: the end screen "Operation over – NATO caused the strategic threshold – defeat" appears, End turn is disabled, **Back to menu** works.
5. Review the level table and numbers in GDD "Escalation ladder".

## Player manual

Section in the "Politics" chapter (started by TASK-113) – the five levels with their names and what may be struck at each, that the level is shared, what raises it (decisions, breaching Russian soil, striking towns) and lowers it (standing down, 3 quiet rounds back to the start level), that allies join automatically at Regional war, and that the side whose action reaches the Strategic threshold loses the operation at once.

## Out of scope

- Breach and casus belli detection in movement, closed hexes in routes (TASK-116); the player's decisions (TASK-117); allied formations entering play (TASK-118 – hooks into `set_stance`); the strikes themselves (TASK-097); the decisions that raise or lower the level for the player (TASK-117 – until then the debug panel); scoring by escalation (TASK-107); political events (TASK-106).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
