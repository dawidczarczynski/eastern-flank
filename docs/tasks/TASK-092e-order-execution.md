# TASK-092e: Order execution – formations carry out their orders over several turns at the end of their side's turn

- **Status**: ready
- **Layers**: core (`src/core/operational/`) + presentation (counter movement, report)
- **Depends on**: TASK-092d, TASK-093b
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Orders come alive: when a side ends its operational turn, each of its formations with an order follows its route as far as its posture's move points allow, and keeps going turn after turn until it arrives, makes contact or the order can no longer be carried out (GDD "Operational layer" → "Orders and postures"). The player plans; the formations move.

## Acceptance criteria (testable)

Execution (inside `EndOperationalTurnCommand.apply`, before `operational_turn_ended`; validation unchanged – still `battle_pending` only):

- [ ] Only the **current player's** formations execute, in `state.formations` order (placement order); each one sees the positions left by the ones before it. Formations without an order do not move. The other side's orders wait for the end of that side's turn (test: a player 1 order does not move when player 0 ends the turn).
- [ ] Per formation with an order, in this order:
  1. the destination holds another formation (either side) → order removed, event `formation_order_interrupted` (`formation_id`, `reason` `&"destination_occupied"`, `at` = its hex); no move;
  2. `route = OperationalRoutes.plan(state, formation, destination, posture.avoids_contact)`; empty → interrupted, reason `&"no_route"`; no move;
  3. `w = OperationalRoutes.walk(state, formation, coord, route, posture.budget(move_points))`; if the formation did not move and `w.stop` is `out_of_points` → interrupted, reason `&"blocked"`;
  4. if it moved: `coord` = `w.end`, event `formation_moved` (`formation_id`, `from`, `to`, `path` = `w.steps`, `cost` = `w.cost`);
  5. `w.stop` `arrived` → order removed, event `formation_order_completed` (`formation_id`, `destination`); `contact` → order **kept**, event `formation_halted` (`formation_id`, `at`, `reason` `&"contact"`); `out_of_points` → nothing more (still en route).
- [ ] Posture is never changed by execution (a formation that arrives keeps its posture).
- [ ] All formation events come before `operational_turn_ended`; within one formation `formation_moved` comes first.

Examples (hand-made grids of TASK-092c, formations of type `pl_mech_battalion` – 8 move points; player 0 moves first; each "round" = player 0 and player 1 end their turns):

- [ ] Plains row, F on (0, 0), `march` order to (6, 0): end of player 0's turn 1 → F on (4, 0), `formation_moved` path [(1, 0), (2, 0), (3, 0), (4, 0)], cost 8, order kept; player 1 ends → F unchanged; player 0 ends turn 2 → F on (6, 0), `formation_moved` then `formation_order_completed`, order null, posture still `march`.
- [ ] Same with `defend` → (2, 0), (4, 0), (6, 0) at the end of player 0's turns 1, 2, 3; with `advance` → (3, 0), (6, 0). Changing posture between turns (march, then `SetPostureCommand` to defend at (4, 0)) → the next turn reaches (6, 0) (cost 4 = the defend budget).
- [ ] Contact grid (enemy on (4, 1)), F `advance` to (6, 0): F ends player 0's turns on (3, 0); (4, 0) + `formation_halted` (contact), order kept; (5, 0) + `formation_halted`; (6, 0) + `formation_order_completed`.
- [ ] `no_route` at execution: on the contact grid with the enemy formation starting on (6, 1) (only the destination is in its zone of control – allowed), F gets a `march` order to (6, 0); the test then moves the enemy formation to (4, 1) by hand and ends the turn → F unmoved, `formation_order_interrupted` `no_route`, order null.
- [ ] `destination_occupied`: two own formations F (placed first) on (0, 0) and G on (0, 1) of a 10 × 2 plains grid, both `march` to (4, 0) → F arrives (completed), G is interrupted `destination_occupied` and does not move; with G placed first the roles swap (deterministic order).
- [ ] `blocked`: plains row, F on (0, 0) `defend` (budget 4) to (5, 0), own formations without orders on (1, 0) and (2, 0) → F does not move, interrupted `blocked`.
- [ ] Invariants after every end turn in a scripted `suwalki_gap` run (seed 7, every formation of both sides ordered to a hex at distance ≥ 3 with a route, 6 rounds): no two formations on one hex, none on an impassable hex, none on or across an enemy hex; every order either still active, completed or interrupted with one of the listed reasons.

Determinism and docs:

- [ ] Operational replay: on `Operation.build("suwalki_gap", 7)`, a scripted sequence over 3 full rounds – a road march, an `advance` that comes into contact, a `defend` order, one `CancelOrderCommand`, one `SetPostureCommand`, one rejected command – is turned into dicts, decoded and executed on a fresh build → identical `snapshot()` and an identical list of emitted events (types and fields).
- [ ] Nothing in execution draws from `state.rng` (test: `rng_state` unchanged after the scripted run).
- [ ] docs/ARCHITECTURE.md: "Operational events" gets `formation_moved`, `formation_halted`, `formation_order_completed`, `formation_order_interrupted` (with the reasons); "Two layers" describes the execution step of `EndOperationalTurnCommand`.

View (End turn now does something):

- [ ] **End turn** (TASK-093b) executes the side's orders: the counters **slide along `path`** from `formation_moved` events (about 0.4 s per hex, capped at 2.5 s per formation, all formations of the side at once; **Space** or a click skips the animation; End turn is disabled while it plays). Arrows are redrawn for the remaining route from the state.
- [ ] A short **turn report** panel after the move lists, per ordered formation, `arrived` / `halted on contact` / `interrupted` with the reason in words and a place name or coordinate; clicking an entry centres the map and selects the formation. The report can be closed and reopened (key **R**).
- [ ] An order that continues over several turns shows its remaining route and the new per-turn ticks; a formation that arrived loses its arrow.
- [ ] Skipping the animation and letting it play give the same final state (test on the controller: events applied first, animation is cosmetic).
- [ ] Operational replay check (above) is additionally exercised by a scripted run through the scene controller with no input (headless smoke test: end 6 turns with orders given, state equals the pure-logic run).

## Look (Claude Design)

Reference: [docs/design/operational_map/README.md](../design/operational_map/README.md) ("Counters" states, "Orders"). Counters slide in screen space along the projected path (following the relief); must work under the 2.5D camera of [TASK-125](TASK-125-staff-map-restyle-2-5d.md).

- [ ] Counter state **"moved"** (dimmed / marked frame) for formations that moved this turn, cleared when the side's next turn starts; state **"in contact"** = dashed `ui.alert #e07c5e` ring on a formation that `formation_halted` with `contact` (and on the adjacent enemy). Test on the view-model.
- [ ] Remaining routes redrawn as issued orders (82 % opacity, no dots – TASK-092d); an arrived formation loses the arrow and the "has order" mark.
- [ ] The turn report uses the HUD v3 panel style; the reference has no report layout (its report is the after-action report, TASK-095) – **no design values beyond that**.
- [ ] **NOT adopted:** "AI moving…" state (TASK-102).
- [ ] **Note for TASK-094a:** it draws one `state.rng` value per started battle after execution; the "no `rng` draws" test above must therefore use a scripted run without a contact (or compare only until the contact).

## Playtest (for the human)

1. Give a Polish battalion in the Gap a far destination with posture advance (6 points), another a march order along a road.
2. End turn: nothing moves yet for the other side – then End turn again for the other bloc and again for yours: the counters slide hex by hex, the road convoy further than the one going across country.
3. Press Space during the slide: counters jump to their end hexes. The report lists "arrived", "halted on contact" etc.; click an entry: the map centres on that formation.
4. Send an advancing battalion towards a Russian one: it halts next to it (contact, order kept) – nothing else happens yet (battles are TASK-094).
5. Order a formation onto a hex that another formation then occupies: the report says why the order was dropped.

## Player manual

Section "End of turn": orders execute when you end your turn, in the order of battle; a formation keeps following its order on later turns; it stops when it arrives (the order is done), when an advancing formation comes next to an enemy (it halts and keeps the order), or the order is cancelled and reported when the destination is taken, no route is left or the way is blocked by own formations; the turn report.

## Out of scope

- What happens on contact (battle, TASK-094); supply and readiness lowering the budget (TASK-096, TASK-095); fog (TASK-100).
- Simultaneous resolution of both sides' orders – rejected by the human (2026-11-01); turns stay alternating.
- The front line (TASK-093c); battles on contact (TASK-094).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
