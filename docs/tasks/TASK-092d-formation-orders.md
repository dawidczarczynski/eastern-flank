# TASK-092d: Formation orders – postures as data, issue / cancel order, set posture (commands, codec, snapshot)

- **Status**: blocked
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data
- **Depends on**: TASK-092c
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The player commands formations the operational way: a formation gets an **order** – a destination and a **posture** (march, advance, defend) – instead of being moved hex by hex (GDD "Operational layer" → "Orders and postures"; human decision 2026-11-01). This task stores orders and postures in the state through commands; they are carried out at the end of the turn by TASK-092e.

## Acceptance criteria (testable)

Postures as data:

- [ ] `OperationalPosture` (Resource, `src/core/data/operational_posture.gd`, one `.tres` per posture in `data/operational/postures/<id>.tres`): `id`, `display_name` (English, translation key), `move_percent` (int, share of the formation's `move_points` spent per turn), `avoids_contact` (bool, passed to `OperationalRoutes.plan`), `problem() -> String` ("" when valid; `move_percent` outside 1 … 100 → problem, test). `OperationalPosture.NAMES` = `[&"march", &"advance", &"defend"]`; `OperationalPosture.find(id)` → the resource or null.
- [ ] Shipped values **[ASSUMPTION]** (test reads the files): `march` 100 %, avoids contact; `advance` 75 %, does not avoid contact; `defend` 50 %, avoids contact.
- [ ] `OperationalPosture.budget(move_points) -> int` = `move_points * move_percent / 100` rounded down, at least 1. Examples: 8 → march 8, advance 6, defend 4; 5 at 75 % → 3; 1 at 50 % → 1.
- [ ] `OperationDefinition.initial_posture` (StringName, default `&"defend"`; `suwalki_gap.tres` uses the default). `Operation.from_definition` rejects an unknown initial posture (`push_error`, null – test).

State:

- [ ] `Formation.posture: StringName` (= the operation's `initial_posture` at build) and `Formation.order: FormationOrder` (`RefCounted`, `destination: Vector2i`; null = no order). All formations start without an order.
- [ ] Snapshot entries gain `posture` (String) and `order` (null, or `[q, r]` of the destination). Test: a fresh `suwalki_gap` build has every formation in `"defend"` with `order` null; the determinism test of TASK-092b still passes.

`IssueOrderCommand(formation_id: StringName, destination: Vector2i, posture: StringName)` – `{"type": "issue_order", "formation_id": "<id>", "destination": [q, r], "posture": "<id>"}`:

- [ ] Rejections in this order (one test each): `battle_pending`, `formation_not_found`, `not_your_formation` (owner ≠ current player), `unknown_posture`, `invalid_destination` (off the map, impassable, or the formation's own hex), `occupied` (any formation, either side, on the destination), `no_route` (`OperationalRoutes.plan(state, formation, destination, posture.avoids_contact)` is empty – e.g. TASK-092c's contact grid: `march` to (6, 0) → `no_route`, `advance` to (6, 0) → accepted).
- [ ] Apply: `posture` = the given posture, `order` = a new `FormationOrder` (replaces any existing order – issuing twice leaves one order with the second destination); the formation does **not** move; event `formation_order_issued` (`formation_id`, `destination`, `posture`, `forecast` – `OperationalRoutes.forecast` with the posture's budget and `avoids_contact`). Example (plains row of TASK-092c, `move_points` 8): `advance` (budget 6) to (6, 0) → forecast `[(3, 0), (6, 0)]`; `defend` (budget 4) → `[(2, 0), (4, 0), (6, 0)]`.
- [ ] Orders do nothing yet at the end of a turn (execution is TASK-092e): after a full round the formation is still on its hex and keeps its order (test).

`CancelOrderCommand(formation_id)` – `{"type": "cancel_order", "formation_id": "<id>"}`:

- [ ] Rejections in this order: `battle_pending`, `formation_not_found`, `not_your_formation`, `no_order`.
- [ ] Apply: `order` = null, posture unchanged; event `formation_order_cancelled` (`formation_id`).

`SetPostureCommand(formation_id, posture)` – `{"type": "set_posture", "formation_id": "<id>", "posture": "<id>"}`:

- [ ] Rejections in this order: `battle_pending`, `formation_not_found`, `not_your_formation`, `unknown_posture`, `same_posture`.
- [ ] Apply: `posture` changed, the order (if any) kept unchanged – it is re-planned when it executes (TASK-092e interrupts it with `no_route` if the new posture cannot reach the destination); event `formation_posture_changed` (`formation_id`, `posture`, `previous`). Works without an order (a formation holding its hex in a new posture).

Codec and docs:

- [ ] `OperationalCommandCodec`: round trip of all three commands; null for a non-string `formation_id` or `posture`, a `destination` that is not two integral numbers, a missing field. An unknown posture string decodes (the command rejects it in `validate`), like unknown ids elsewhere.
- [ ] docs/ARCHITECTURE.md: "Operational events" gets `formation_order_issued`, `formation_order_cancelled`, `formation_posture_changed`; "Two layers" names `OperationalPosture`, `FormationOrder` and the three commands.

## Playtest (for the human)

None – no view yet (TASK-093). Review the posture numbers (GDD "Orders and postures").

## Player manual

None yet – not reachable before TASK-093. TASK-093's "Operational map" chapter will describe giving an order (destination + posture), the three postures with their pace (march 8, advance 6, defend 4 move points per turn for 8-point formations) and contact behaviour, changing posture, cancelling an order, and the per-turn stops shown on the route.

## Out of scope

- Executing orders (TASK-092e); battle effects of postures (TASK-094); a `delay` posture (needs retreat rules – TASK-095, GDD open question); waypoints or several queued orders per formation.
- Any view (TASK-093); operational AI (TASK-102).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
