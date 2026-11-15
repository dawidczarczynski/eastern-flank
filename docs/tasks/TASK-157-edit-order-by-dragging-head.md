# TASK-157: Staff map – edit an issued order by dragging its head (stage 4)

- **Status**: idea
- **Layers**: presentation
- **Depends on**: TASK-153, TASK-154
- **Sections**: order_lines_analysis.md sections 4, 5 (EDITING state); GDD "Orders and postures"
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The player moves the target of an order given this turn by grabbing the head (grip) of its line and dropping it on another hex; Esc restores. It is free because of TASK-154.

## Notes for the later specification

- Adds the EDITING state to `StaffMapOrderGesture`: press on the head grip of an issued line (hit-test in `StaffMapOrders`) behaves as AIMING; release on a valid hex issues the replacement (free), Esc restores the old order.
- Only orders issued this turn are editable (TASK-154 set); older orders show no grip.
- Whether this is a press-drag gesture or click-head, click-hex is open: decision 3 (2026-11-15) defers press-drag because of touchpads; prefer click–click, specify in the task.
- Acceptance criteria and playtest steps to be written when TASK-153 and TASK-154 are done.

## Player manual

Orders: how to re-aim an issued order from its head.

## Out of scope

- Waypoints, multi-select, undo.

## Implementation notes

_Idea only._
