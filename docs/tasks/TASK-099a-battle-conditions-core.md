# TASK-099a: Battle conditions from installations – core and data

- **Status**: done
- **Layers**: core
- **Depends on**: TASK-094c (done), TASK-091 (done), TASK-097a (done), TASK-120 (done)
- **Topic**: Two-layer game
- **Tags**: mvp
- **Sections**: GDD "Battle hand-off and auto-resolve" (incl. "Battle conditions"), GDD "Deep strikes" (Effects), GDD "Vision decisions" (C2 delay), ARCHITECTURE "Commands"
- **Model**: sonnet

## Goal

Damage to a side's command posts and airfields (deep strikes) changes its next battle: fewer command points, fewer fire-support missions – in played and auto-resolved battles alike.

## Decisions (human interview, 2026-11-11)

1. Scope = command points (from C2 installations) and fire support (from airfields) only. Ammunition (depots, resupply is TASK-081) and morale (TASK-090) stay unread and out of scope; `Conditions` keeps those fields.
2. Mapping per class, pure function with data in `data/battle/conditions.tres` (`BattleConditionsRules`, `src/core/`): value = base x mean integrity / 100, never below a floor (percent of base, data). Destroyed installations count as integrity 0 in the mean; a side with no installation of that class loses nothing (full base). The mean runs over all of the side's installations of the class (whole side, no distance or supply rules – supply is TASK-096).
3. The operation fills `BattleSetup.Conditions` when it builds a contact battle (`ContactRules._build_setup`), for both sides from their own installations, same function for played and auto-resolved battles.
4. Fire support in a played battle: new `FireSupportCommand` (see criteria). Missions per battle = round(base x mean integrity / 100); max 1 per turn per side; no command point spent.
5. Auto-resolve: command points cap the firing companies per round (lowest attack value sits out first); fire support adds one free volley per mission in rounds 1, 2, ... (one per round).

## Acceptance criteria (testable)

- [ ] Data `data/battle/conditions.tres`: `command_points_base` 4, `command_points_floor` 25 (% of base), `fire_support_base` 2, `fire_support_floor` 0, `fire_support_die` 10 (die size of the off-map shooter), `fire_support_attack` 4 (fixed attack value of the off-map shooter, **[ASSUMPTION]** balance guess). Loaded by `BattleConditionsRules.shipped()`.
- [ ] `BattleConditionsRules.for_side(installations, player)` -> `BattleSetup.Conditions` with `command_points` and `fire_support` set; `ammunition` 100, `morale` 100 untouched; posture fields are not touched by it.
- [ ] One C2 at integrity 100 -> 4 command points; at 50 -> 2; at 10 -> 1 (floor 25 % of 4 = 1); at 0 (destroyed) -> 1 (floor).
- [ ] Mean over several: C2 at 100 and C2 destroyed -> mean 50 -> 2 points.
- [ ] A side with no `c2` installation -> 4 command points (loses nothing); no airfield -> 2 fire-support missions.
- [ ] Airfields at 100 -> 2 missions; at 50 -> 1; at 24 -> 0 (round(0.48)); destroyed -> 0 (floor 0). Rounding: half rounds up (50 % of base 3 would be 2).
- [ ] Only the side's own installations count: enemy damage does not change the side's value; two sides get independent values (test with different integrities).
- [ ] `ContactRules._build_setup` fills `conditions[p].command_points` / `fire_support` for both players from `state.installations`; posture and position_bonus stay as before.
- [ ] Scenario battles keep `Conditions` defaults (command_points 0 = unlimited, fire_support 0); existing scenario tests stay green.
- [ ] `FireSupportCommand(player, target_unit_id)`, extends `Command`, via `GameSimulation.execute`; `validate()` reason codes: `not_your_turn`, `no_fire_support` (none left), `fire_support_used_this_turn` (already 1 this turn for the side), `unknown_target`, `friendly_target`, `target_dead`, `target_not_visible` (not seen by the side per existing visibility rules). Test for each.
- [ ] `apply`: the target company takes one normal per-element roll (the AttackCommand roll rules: shots = shooter strength -> here `fire_support_attack` as the attack value against the target's defense incl. terrain / position bonus; `hit_on` clamp as in AttackCommand) drawn from `GameState.rng`; no counter-fire; no command point spent; events `fire_support_used` (player, target, hits, remaining) plus the existing damage / destroyed events (add the new type to the ARCHITECTURE event table).
- [ ] Shooter strength for the roll = fixed `fire_support_shots` in data (**[ASSUMPTION]** 6 shots). Same seed -> same hits; a test fixes the seed and checks the exact hit count.
- [ ] State: `GameState.fire_support_left` per player (from `Conditions.fire_support`) reduced by 1 per use; `fire_support_used_turn` per player reset by `EndTurnCommand` for the new current player; both in `snapshot()` / `GameState` serialisation.
- [ ] `FireSupportCommand` round-trips through `CommandCodec` (to_dict / from_dict, malformed -> null) and replays (`BattleReplay`) reproduce the same state hash.
- [ ] Auto-resolve (`AutoResolve.resolve`): with `command_points` N > 0 only the N living companies with the highest attack value of the side fire each round (ties: setup order); the rest sit out. Replaces the earlier "first N in setup order". `command_points` 0 -> every living company fires (test).
- [ ] Auto-resolve fire support: a side with `fire_support` m fires one free volley (`fire_support_shots` shots at `fire_support_attack`) in each of rounds 1..m, at the enemy company with the highest hit chance, simultaneous with the round's other fire; rules numbers in `data/battle/auto_resolve.tres` / `conditions.tres` (no constants in code).
- [ ] Auto-resolve stays deterministic: own RNG seeded from `setup.seed`, same setup twice -> identical result; `ResolveBattleCommand` `auto_mismatch` re-computation passes unchanged (test with conditions set).
- [ ] Seed sweep (e.g. 200 seeds): raising a side's `command_points` or `fire_support` never lowers its win share (>= with the weaker value) in a fixed symmetric setup.
- [ ] A side whose C2 is all destroyed keeps the floor (1 command point of base 4), never 0 (0 would mean unlimited).
- [ ] Doc: GDD "Battle hand-off and auto-resolve" subsection "Battle conditions" matches the numbers (already written by the designer; adjust if implementation differs).

## Playtest (for the human)

1. Debug-strike a Russian command post to 0 in the operation, then trigger a contact battle: Russia's side has 1 command point, NATO still 4 (check in the battle HUD / report; the view is TASK-099b).
2. Auto-resolve the same contact twice from a save: identical result.

## Player manual

None (the view and the rules text come with TASK-099b).

## Out of scope

- Ammunition (depots, TASK-081) and morale (TASK-090); distance and supply rules (TASK-096); AI use of fire support (the AI does not call it yet – follow-up); any view (TASK-099b); balance tuning (TASK-103).

## Implementation notes

- `BattleConditionsRules` (`src/core/data/battle_conditions_rules.gd`, `data/battle/conditions.tres`): `for_side(installations, player)` and the shared `scaled(...)`; half-up rounding in integers; command points clamped to at least 1. `ContactRules._build_setup` uses it for both sides.
- `FireSupportCommand` (`src/core/commands/fire_support_command.gd`), codec entry `fire_support`; `GameState.fire_support_left` / `fire_support_used_turn` (set in `Scenario.from_setup`, flag reset in `EndTurnCommand`). The snapshot gets the two keys only once a mission exists, so older snapshots / golden fixtures are unchanged. Event `fire_support_used` added to ARCHITECTURE.
- `AutoResolve`: `_firing` (command cap by highest attack value, ties setup order) and free volleys in rounds 1..m; `resolve_from` takes the missions left from the played `GameState`.
- Assumptions beyond the task text: (1) `fire_support_die` = 10 added to `conditions.tres` (the off-map shooter needs a die size; `hit_on` is clamped to it); (2) "seen by the side" = some living own unit has `LineOfSight.visible` to the target hex (there is no fog or sight range in the tactical layer yet; TASK-100 can tighten it); (3) validation order follows the criteria list; (4) the volley emits `fire_support_used` + `unit_died` / `game_over`, no `unit_attacked`.
- GDD "Battle conditions" matches; no change needed beyond that.
- Tests: `test_battle_conditions.gd`, `test_fire_support_command.gd`, `test_auto_resolve_conditions.gd`. Presentation (TASK-099b) must show the missions left and a call button; the AI does not call fire support.
