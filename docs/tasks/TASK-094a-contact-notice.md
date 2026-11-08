# TASK-094a: Contact (1/4) – contact rule, pending battle with its `BattleSetup`, contact notice on the staff map

- **Status**: done
- **Layers**: core (`src/core/operational/`, `src/core/battle_setup.gd`, `src/core/data/`) + data + presentation (notice, contact queue)
- **Depends on**: TASK-092e (soft: TASK-093c; TASK-088, TASK-087 are done)
- **Sections**: GDD "Battle hand-off and auto-resolve", "Player roles"; reference [docs/design/operational_map/README.md](../design/operational_map/README.md) ("Panels" → contact notice); ADR 0015 §3
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Split from TASK-094 (2026-11-07): an advancing formation that halts next to an enemy now **starts a battle**: the staff map dims and a contact notice names both sides. The battle itself is TASK-094c; here the human can only read the notice and (debug) resolve it as a draw. `ContactRules` alone is not a task – the notice is its visible result.

## Acceptance criteria (testable)

Core:

- [x] `ContactRules.battle_allowed(state, attacker, defender) -> bool` – always true here (TASK-116 adds the border rule, TASK-100 fog); the one predicate every contact asks.
- [x] Detection runs in `EndOperationalTurnCommand.apply` **after** order execution and before `operational_turn_ended`: for each `formation_halted` (reason `contact`) of this step, in event order, the halted formation attacks the adjacent enemy formation (first in `Hex.DIRECTIONS` order; ties by formation order) if `battle_allowed`. A formation takes part in at most one pending battle per step **[ASSUMPTION]** (the others stay halted with their order and are detected again next turn). Arriving next to an enemy (`arrived`) starts no battle.
- [x] `OperationalPosture.position_bonus` (data, `problem()` range −3 … 3): `defend` +1, `advance` 0, `march` −1 (test reads the files).
- [x] Per battle a `BattleSetup` is appended to `pending_battles` (FIFO): `seed` drawn from `state.rng` inside the apply (one draw per battle, ADR 0015 §3), `operation_name`, `map_id` = the operation's map, `factions`, one `Company` per formation company (order: attacker's then defender's formation; `strength`, `ref` from the formation), `attacker` = the attacker's player, `terrain` = terrain id of the defender's operational hex, per player `Conditions.posture` and `position_bonus` from the posture data, per player a `Mission` (`task` `&"attack"` for the attacker, `&"defend"` for the defender or `&"hold_out"` when its posture is `march`; `intent` = the order destination as text key + args; formation display name). `to_dict` / `from_dict` carry the new fields (null on a missing or malformed one; scenario battles keep `attacker` −1, `terrain` `&""`, posture `&""`, no mission). Company `coord` and `map_region` are **placeholders** (`Vector2i.ZERO`, empty rect) – TASK-094b fills them; `objectives` stay `default_objectives()` until then.
- [x] Event `battle_pending` (`attacker_id`, `defender_id`, `at` = the defender's hex, `index` in the queue). Example (TASK-092e contact grid, enemy on (4, 1), F `advance` to (6, 0)): end of F's turn 2 → F on (4, 0), `formation_halted`, then `battle_pending`; `pending_battles` length 1, attacker 0, defender posture `defend` → bonus +1, terrain `plains`. Forest hex under the defender → `forest`. Defender on `march` → mission `hold_out`, bonus −1.
- [x] `ResolveBattleCommand(result: BattleResult)` v0 (`{"type": "resolve_battle", "result": {...}}`): rejections `no_pending_battle`, `result_mismatch` (company count, `ref`s, `strength_start` differ from the first pending setup); apply removes the first pending battle, event `battle_resolved` (`attacker_id`, `defender_id`, `winner`, `reason`) – **no consequences** (TASK-095). Codec round trip.
- [x] While a battle is pending every order / turn command is rejected `battle_pending` (existing rule); after resolving, End turn works again.
- [x] Determinism: the scripted run of TASK-092e extended by a contact: replay from dicts → identical `snapshot()`, events and `pending_battles` dicts. **Conflict:** TASK-092e's criterion "nothing in execution draws from `state.rng`" holds for execution; this task adds exactly one draw per battle after it – amend that test (it must compare `rng_state` only on runs without contact) and note it in 092e.
- [x] docs/ARCHITECTURE.md "Two layers" / "Operational events": `ContactRules`, `battle_pending`, `battle_resolved`, `ResolveBattleCommand`, the new `BattleSetup` fields.

View (the contact notice):

- [x] On `battle_pending` the camera centres on the defender's hex, the map dims (scrim), and a **contact notice** sits next to the battle hex (screen-space card anchored to the projected hex, kept on screen; must work under the 2.5D camera of [TASK-125](TASK-125-staff-map-restyle-2-5d.md)). Content: title, attacker vs defender (counter shapes of TASK-092b: own rectangle / enemy diamond relative to the viewer, names, posture, strength segments), the strength totals and their ratio as the odds line **[ASSUMPTION]**, the place, the mission text of the attacker. Buttons **Play battle** `B` (disabled with the reason "Battle scene not hooked up yet" until TASK-094c) and, with `--debug`, **Resolve as draw (debug)** which sends a `ResolveBattleCommand` with every company at its start strength. **NOT adopted:** the reference's 3-band forecast (breakthrough / stalemate / repulse) – needs its own rule; **Auto-resolve** `A` is TASK-120.
- [x] Contact queue on the left: `1 OF 2` and a row per pending battle (the active one marked); the notice shows the first.
- [x] Scene-level smoke test: a scripted contact on a hand-made grid shows the notice with the right names; resolving removes it and re-enables End turn.
- [x] Strings `tr()` (en + pl), `test_localization.gd` green.

## Playtest (for the human)

1. **Operation**, play the side that moves first. Select a battalion in the Gap, give it an **Attack** order (key 2) to a hex next to a Russian formation, press End turn (the other side too) until the counter stops with the red ring next to the enemy.
2. The map dims and the contact notice appears next to that hex: both frames, names, strengths, odds line; the queue on the left says `1 OF 1`. **Play battle** is greyed with a reason.
3. Start with `--debug` and press **Resolve as draw**: the notice closes, the map brightens, End turn works again.
4. Make two contacts in one turn (two attackers): the queue shows `1 OF 2`; resolving the first shows the second.

## Player manual

Section "Contact": when a battle starts (an advancing formation halts next to an enemy; a marching formation caught in column is the defender with a penalty), what the notice shows, the queue. Mention that battles cannot be skipped yet.

## Out of scope

- The tactical map, deployment, objectives (TASK-094b); playing the battle and returning (TASK-094c); saving (TASK-094d); auto-resolve (TASK-120); consequences of a result (TASK-095); the border rule (TASK-116); fog (TASK-100).

## Implementation notes

Core: `ContactRules` (`battle_allowed`, `start_battles`, called from `EndOperationalTurnCommand.apply` after execution), `ResolveBattleCommand`, `OperationalPosture.position_bonus`, `OperationalState.map_id`, `BattleSetup` fields `attacker` / `terrain` / `missions` and `Conditions.posture` / `position_bonus`; events `battle_pending`, `battle_resolved` (ARCHITECTURE.md updated). 092e determinism test amended (rng compared only without contact). Tests: `test_contact.gd`, `test_staff_map_contacts.gd`.

View: `StaffMapContacts` (queue, scrim, ring, placement, debug draw), `StaffMapContactNotice`, `StaffMapContactQueue`; glue in `staff_map.gd`; `tools/screenshot.gd` token `contact:<attacker>:<defender>`.

Deviations from mockup 03: place shown as hex + terrain (no names), tab text "TURN 01 · 1/2", no flavour line, title 22 px, no blur on scrim, queue at left edge y 130. Intent keys are placeholder-free (view appends the hex). Not verified visually after the last two layout fixes (counter centring, queue height). Known limits: the `--pending-battle` dummy shows no notice; the `--debug` button was only tested as hidden without the flag. README screenshot not refreshed (battle scene unchanged).

Follow-up: attack order on an enemy formation. `IssueOrderCommand` accepts an enemy-held destination only for a posture with `avoids_contact == false` (Attack/`advance`); March/Defend get `enemy_destination`, an own formation there stays `occupied`. `OperationalRoutes.plan` ends the route on the enemy hex (other enemy hexes stay blocked), `walk` never enters an enemy hex and halts with `contact` before it, also with zero steps when already adjacent, so `EndOperationalTurnCommand` emits `formation_halted(contact)` and `ContactRules` starts the battle without a move. The order is kept after a contact halt (as for other contact halts). Target gone at execution: the destination is empty, so the formation goes there and `formation_order_completed` fires; an own formation on it or a non-attack posture on an enemy = `destination_occupied` interrupt. View: `StaffMap.click_at` orders an attack when an own formation in Attack is selected and an enemy counter is clicked; `StaffMapRoute.unreachable_reason` allows enemy hexes for that posture. Strings `ORDER_REJECTED_ENEMY_DESTINATION`, `ROUTE_ENEMY` updated. Tests: `test_attack_order.gd`, amended `test_formation_orders`, `test_operational_routes`, `test_staff_map_route`.
