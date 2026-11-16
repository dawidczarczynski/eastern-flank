# TASK-154: Orders – re-aiming or cancelling an order given this turn is free

- **Status**: done
- **Layers**: core
- **Depends on**: –
- **Sections**: GDD "Orders and postures"; GDD "Battle hand-off and auto-resolve" (Orders per turn bullet only)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

A player who mis-clicks or changes their mind about an order given this turn can re-aim or cancel it without losing a scarce order (human decision 2026-11-15).

## Rule

- The state remembers which formations hold an order paid for **this turn** (`ordered_this_turn`, a set of formation ids).
- `IssueOrderCommand` on a formation in that set: free – no `no_orders_left` check (works at 0 left), `orders_issued` unchanged, the formation stays in the set.
- `IssueOrderCommand` on any other formation: costs 1 as before and adds it to the set.
- `CancelOrderCommand` on a formation in the set: refunds 1 (`orders_issued -= 1`) and removes it; cancelling an order from an earlier turn stays free and refunds nothing.
- `SetPostureCommand` unchanged (free, keeps the order). The set is emptied together with `orders_issued` at the start of the side's turn. The GDD "Orders and postures" holds the rule (done); the implementer aligns the sentence "also a replacement of an earlier order" in the "Orders per turn" bullet of "Battle hand-off and auto-resolve" and the `IssueOrderCommand` doc comment.

## Acceptance criteria (testable)

- [ ] limit 4, issue 4 orders to 4 formations: re-aiming the first one to another hex is accepted, `orders_left()` stays 0; a fifth formation is still rejected with `no_orders_left`.
- [ ] issue, then cancel: `orders_left()` returns to its earlier value; issue again costs 1.
- [ ] an order carried over from a previous turn: re-aiming it costs 1 (and makes it refundable); cancelling it refunds nothing.
- [ ] re-aim to an invalid destination is rejected with the usual reason and changes nothing (no refund, no cost).
- [ ] the set is cleared at the start of the side's turn; it is in the snapshot, codec and save only when non-empty (older snapshots identical); round-trip test.
- [ ] `OperationalAi` stays within the limit and gives identical results to before for a plan without re-aims (a determinism check on an existing scenario).
- [ ] `formation_order_issued` carries `free: bool`; ARCHITECTURE event table updated.

## Playtest (for the human)

1. Issue an order: "ORDERS LEFT" drops by 1. Re-aim the same formation: unchanged. Cancel it (Delete): it goes up by 1.
2. At 0 left, re-aim an order given this turn: works; a formation without an order is refused. After End turn, re-aiming an old order costs 1.

## Player manual

Orders chapter: re-aiming or cancelling an order issued this turn is free and cancelling returns the order; an order from an earlier turn costs one when replaced.

## Out of scope

- Undo / redo; the drag-the-head edit UI (TASK-157).

## Implementation notes

- `OperationalState.ordered_this_turn` (Dictionary used as a set); cleared with `orders_issued` in `EndOperationalTurnCommand._switch_side`; in the snapshot only when non-empty (sorted id list).
- `IssueOrderCommand`: free for a formation in the set (skips `no_orders_left`), otherwise costs 1 and joins the set; the event carries `free`.
- `CancelOrderCommand` refunds 1 when the formation was in the set.
- GDD "Orders per turn" sentence and ARCHITECTURE event table aligned. Tests in `tests/unit/test_orders_per_turn.gd`; `tools/check.sh` passes.
- docs/MANUAL.md "Orders per turn" updated.
