# TASK-157: Staff map: edit an issued order by clicking its head (stage 4)

- **Status**: done
- **Layers**: presentation
- **Depends on**: TASK-153, TASK-154
- **Sections**: order_lines_analysis.md sections 4, 5, 7 (docs/design/operational_map/); GDD "Orders and postures"; MANUAL "Orders"
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The player re-aims an issued order by clicking the head (end grip) of its line and then a new hex, without re-selecting the formation by hand. This turn's order is free to re-aim (TASK-154); an older one costs 1 order.

## Decisions (2026-11-16)

1. Click-click only; press-drag stays deferred (decision 3, 2026-11-15, touchpads).
2. Every own issued order has a grabbable head, not only this turn's; an older one costs 1 order to re-aim.
3. Cost cue is the aim label only ("FREE" / "COSTS 1 ORDER"); no new grip look (the existing head marker of `StaffMapRouteMarks` is reused, so no /design-ui).
4. No cancel gesture on the grip; cancel stays on Delete and the right-click order ring.
5. Hit-test: an own counter under the cursor wins (existing click path); otherwise the nearest head within 14 screen px wins.
6. No rule changes: `IssueOrderCommand` already prices free vs paid. GDD "Orders and postures" is unchanged (no GDD edit).

## Acceptance criteria (testable)

Gesture (`StaffMapOrderGesture`, tests in `tests/unit/`):

- [ ] New state EDITING: `click_head(id)` from IDLE or ARMED returns intent `edit` {id}; state EDITING, `formation_id()` = id, `is_aiming()` true after a `hover` over a hex.
- [ ] In EDITING `hover(hex, verdict, orders_left)` sets Aim SNAPPED / INVALID exactly as in AIMING (same reason codes).
- [ ] In EDITING `click_hex` on a valid hex returns `ISSUE` {hex, posture} and goes COMMITTED then IDLE after `SETTLE_SEC` (0.12 s); a border-incident hex returns `CONFIRM_NEEDED`, and Esc from that CONFIRM returns to EDITING aiming.
- [ ] Esc in EDITING while aiming (a hex is hovered): back to the hex-less editing state, no command; a second Esc: `DISARM`, state IDLE, `edited_from()` empty. The old order is never touched by Esc.
- [ ] `fail()` (command rejected) returns from COMMITTED/CONFIRM to EDITING, not to plain AIMING.
- [ ] `click_head` while blocked (strike mode, modal, sliding, not viewer's turn) returns `NONE` and changes nothing.
- [ ] `click_head(id)` while another formation is armed/editing switches to id (posture pick cleared, as `click_own_counter`).
- [ ] Posture keys 1-3 (`pick_posture`) work in EDITING and the picked posture is in the `ISSUE` details.
- [ ] Costs: `edit_cost_label(is_free: bool) -> String` returns exactly "FREE" for true and "COSTS 1 ORDER" for false.
- [ ] Free edit with 0 orders left: the caller passes an effective `orders_left` of at least 1 for this turn's order, so a valid hex gives SNAPPED (no `no_orders_left`).
- [ ] Older order with 0 orders left: grab still enters EDITING; hover gives INVALID with reason `no_orders_left`; `click_hex` returns `REJECT` {reason}, no command, no toast.

Hit-test (pure function in `StaffMapOrders`, e.g. `head_at(point: Vector2, heads: Dictionary) -> StringName`, heads = {formation id: screen Vector2}):

- [ ] A point 13 px from a head returns that id; 15 px returns `&""` (radius 14 px).
- [ ] Two heads within 14 px of the point: the nearer wins; an exact tie: the lexicographically smaller id (deterministic).
- [ ] Empty `heads` returns `&""`.
- [ ] Only own issued orders are in `heads` (enemy and foreign orders never grabbable); a formation without an order has no head.
- [ ] View routing: a click that hits an own counter AND a head within 14 px goes to `click_own_counter`, not `click_head`.

View (verified by playtest, plus a headless check where feasible):

- [ ] While EDITING the old line stays as a dim ghost at its old target (opacity at most 0.35 of the issued opacity); the live line follows the cursor; the ghost vanishes on COMMITTED or Esc-to-IDLE. [ASSUMPTION: 0.35]
- [ ] The aim label shows `edit_cost_label` text: "FREE" if `ordered_this_turn` has the id, else "COSTS 1 ORDER".
- [ ] Delete and the right-click order ring still cancel the order while EDITING (and end the editing without a second command).

## Playtest (for the human)

1. Give one formation an order this turn. Click the head of its line: the line stays dim, a live line follows the cursor, label says "FREE". Click another valid hex: the order moves, the order counter does not drop.
2. Repeat and press Esc: the old order is unchanged; Esc again deselects.
3. End the turn; next turn click the head of the old (carried) order: label says "COSTS 1 ORDER"; re-aim spends 1 order.
4. With 0 orders left: grabbing this turn's head still shows "FREE" and works; grabbing an older head shows the usual no-orders reason on hexes and nothing is issued.
5. Click a head right next to an own counter: the counter is selected, not the head.
6. Re-aim across a border: the CONFIRM prompt appears as for a normal order; Esc returns to aiming.
7. Press 1-3 while editing: the posture changes. Delete or the right-click ring cancels the order.
8. In strike mode, with a modal open, during a slide, or on the enemy's turn: the head does nothing.

## Player manual

Orders chapter in docs/MANUAL.md: how to re-aim an issued order (click the head of its line, then a hex; Esc keeps the old order); this turn's order is free, an older one costs 1 order; cancel stays on Delete and the order ring.

## Out of scope

- Waypoints, multi-select, undo.
- Press-drag (deferred, decision 3 of 2026-11-15).
- A new grip look or a cancel gesture on the grip.

## Implementation notes

- `StaffMapOrderGesture`: state EDITING (flag `_editing` so AIMING/ARMED logic is shared), intent `edit`, `click_head`, `edited_from()`, `edit_cost_label`; `fail()` resumes editing.
- `StaffMapOrders`: `head_at` (14 px, nearest, smaller id on ties), `heads_on_screen`, `set_ghost` (old order drawn on the fresh ribbon at 0.35 of the issued opacity, no marks).
- `StaffMap`: `_grab_head` in `click_at` (counter and enemy target win), `_effective_orders_left` (>= 1 for this turn's order), ghost/label wiring, Delete while editing ends it. `StaffMapRoutePreview.cursor_label` shows FREE / COSTS 1 ORDER while editing.
- Limitations: the head is not highlighted on hover (no new look, per decision 3); the ghost has no head/spear marks. Tests: gesture, orders hit-test, view tests. A timing test (`test_auto_resolve:test_speed`) flaked once under load, passes alone.
