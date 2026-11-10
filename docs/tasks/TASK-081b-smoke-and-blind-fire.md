# TASK-081b: Smoke screen and Blind fire (core)

- **Status**: blocked
- **Layers**: core (+ data `.tres`); no presentation, no AI
- **Depends on**: TASK-081a, TASK-131a (line of sight and range hexes)
- **Sections**: GDD "Unit orders", GDD "Combat"; TASK-131a (LoS rules)
- **Model**: sonnet

## Goal

A tank can lay a smoke screen that blinds direct fire through a hex, and any unit can fire at a hex it cannot see.

## Acceptance criteria (testable)

- [ ] Data: `data/orders/smoke.tres` (tank, range 1–2) and `blind_fire.tres` (tank / infantry 1–2, MLRS 3–6, `attack_modifier` −1); `OrderRules.orders_for` includes them for the right classes.
- [ ] `SmokeCommand` (`order_smoke {unit_id, target}`): adds `{coord, owner}` to `GameState.smoke_hexes` (no duplicate for the same hex), sets slot state as in 081a, `moves_left = 0`; event `unit_order_issued {order: &"smoke", target}`.
- [ ] Rejections: `invalid_target` (off map), `too_close` (distance 0), `out_of_range` (3), `order_not_available` (infantry, MLRS), plus the common codes of 081a.
- [ ] `LineOfSight.visible` takes the smoke hexes: a smoke hex strictly between attacker and target blocks direct fire (`no_line_of_sight` for an attack, no counter); smoke on the attacker's or target's own hex does not; an indirect-fire unit (MLRS) still attacks through it.
- [ ] Smoke lasts through the enemy's turn: it exists after the owner's `EndTurnCommand` and is removed (event `smoke_cleared {coord, owner}`) when the owner's next turn starts, not at the enemy's turn start.
- [ ] `BlindFireCommand` (`order_blind_fire {unit_id, target}`): strike on the unit in the hex via the normal roll (one rng draw per hit point of the striker, as in TASK-089a); margin = `max(1, attack − defence − tile bonus − 1)`; attacker `has_attacked`, `moves_left = 0`, `slot_order = &"blind_fire"`; `unit_attacked` with `blind: true`; counter by the normal rules (no counter from a direct-fire defender with no line of sight).
- [ ] Blind fire works with no line of sight: infantry at distance 2 behind a forest hex hits where `AttackCommand` returns `no_line_of_sight`. Table-driven: attack 5 vs defence 2 → margin 2 (normal 3); attack 3 vs defence 4 → 1.
- [ ] Blind fire rejections: `invalid_target`, `too_close` (infantry at 0; MLRS at 1–2), `out_of_range` (infantry at 3; MLRS at 7), `no_unit_at_target`, `not_an_enemy` (own unit in the hex), plus common codes.
- [ ] Forecast: `CombatForecast` exposes the blind-fire margin (pure, no rng) for TASK-082's targeting preview.
- [ ] Codec round trip for both commands; replay of a scripted match with smoke + blind fire gives identical snapshots twice; `smoke_hexes` is in `snapshot()` only when non-empty.
- [ ] ARCHITECTURE events table: `smoke_cleared`, the `blind` flag of `unit_attacked`.

## Playtest (for the human)

none – core only; playtest via TASK-082 (menu, targeting mode).

## Player manual

Add when TASK-082 exposes the orders: Smoke screen and Blind fire (ranges, effects, cost, duration) as in GDD "Unit orders".

## Out of scope

Smoke visuals, targeting UI (TASK-082), AI use (Smoke / Blind fire stay unused by the AI), Ambush, Scoot, fog of war.

## Implementation notes

_Filled in by the agent when done._
