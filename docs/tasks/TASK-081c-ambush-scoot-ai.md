# TASK-081c: Ambush reaction strike, Scoot and AI use of orders (core + ai)

- **Status**: blocked
- **Layers**: core, ai (+ data `.tres`); no presentation
- **Depends on**: TASK-081b
- **Sections**: GDD "Unit orders", GDD "Combat" (incl. "Per-element rolls"); ARCHITECTURE "Events"
- **Model**: opus (a strike triggered inside another command's move, rng order, AI changes)

## Goal

Infantry can wait in ambush for a free first strike, rocket artillery can relocate after firing, and the AI uses Dig in, Ambush and Scoot without upsetting balance.

## Acceptance criteria (testable)

- [ ] Data: `data/orders/ambush.tres` (infantry, `attack_modifier` +1 for counters) and `scoot.tres` (MLRS, `move_budget` 2).
- [ ] `AmbushCommand` (`order_ambush {unit_id}`): sets `ambush`, slot state and `moves_left = 0` as in 081a; rejects `already_ambushing`, `order_not_available` (tank, MLRS), common codes.
- [ ] Counter bonus: an ambushing infantry counterattack uses attack +1 (attack 4 vs defence 2 → margin 3 instead of 2); the forecast shows it; non-ambushing units unchanged.
- [ ] Reaction strike: after `unit_moved`, every enemy ambusher (ascending id) adjacent to the mover's **end hex** strikes once, no counter, normal roll (`hp` draws), `unit_attacked {reaction: true}`, then its `ambush` is cleared (`unit_order_cleared {reason: &"spent"}`); passing through an adjacent hex does not trigger; a dead mover ends the command (`unit_died`, `BattleRules.after_strike` as in a normal strike, may end the game; later ambushers do not fire).
- [ ] Reaction strikes ignore the mover's command points and do not set the ambusher's `has_attacked`; an ambusher with no line of sight (never for adjacent hexes) or a friendly mover never triggers.
- [ ] Ambush clears when the unit moves, at the owner's next turn start (`reason: &"turn_started"`), or when spent; a dug unit keeps `dug` while ambushing.
- [ ] `ScootCommand` (`order_scoot {unit_id, target}`): valid only for an MLRS that fired this turn (`has_attacked` and `slot_order` empty or `blind_fire`); moves it by a path costing ≤ 2 movement points (forest costs 3 → out of reach), sets `scoot_used`, `moves_left = 0`, emits `unit_moved` and `unit_order_issued {order: &"scoot"}`; no extra command point or slot.
- [ ] Scoot rejections: `not_fired`, `already_scooted`, `unreachable` (further than 2 points, occupied or own hex), `order_not_available` (not MLRS), common codes. Capturing an objective hex on arrival works as for a move.
- [ ] Codec round trip for both commands; scripted match with an ambush reaction and a scoot replays to identical snapshots twice.
- [ ] AI uses: infantry or tank on an objective hex it already holds, not attacked, not dug → Dig in; infantry already dug there with a free slot → Ambush; an MLRS that fired from a hex within an enemy's maximum range → Scoot to the reachable hex (≤ 2 points) farthest from the nearest enemy, ties lowest (y, x). It never uses Smoke or Blind fire. AI orders consume no rng.
- [ ] Balance: `tools/simulate.sh 200` for `poland,russia`, `russia,poland`, `poland,poland`, `russia,russia` with the AI using orders: Poland 40–60 % of decided matches over the first two, draws ≤ 15 %, errors 0, numbers recorded in GDD "Balance of the default battle" together with the effect of Dig in (+2); if out of range, tune `defence_bonus` in `data/orders/dig_in.tres`, not code.
- [ ] Regression fixture regenerated only if AI behaviour changes it; ARCHITECTURE events table: `reaction` flag of `unit_attacked`.

## Playtest (for the human)

none – core only; playtest via TASK-082. Optional: watch `tools/simulate.sh 5 --verbose` and confirm infantry dig in on objectives.

## Player manual

Add when TASK-082 exposes the orders: Ambush and Scoot rules as in GDD "Unit orders", plus a note that the opponent digs in and ambushes.

## Out of scope

HUD and visuals, Smoke / Blind fire AI use, Resupply, Camouflage, pass-through ambush triggers, fog of war.

## Implementation notes

_Filled in by the agent when done._
