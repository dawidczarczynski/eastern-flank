# TASK-143: Escalation ladder window (axis + strike matrix)

- **Status**: done
- **Layers**: presentation
- **Depends on**: –
- **Sections**: docs/design/operational_map/README.md "Escalation ladder window", `escalation_ladder_window.html` (variant B accepted 2026-11-11); GDD "Escalation ladder" (View)
- **Model**: sonnet

## Goal

The ladder opened from the escalation chip is large and readable: the seven levels are drawn on a horizontal scale with a tick matrix of what may be struck, so the player sees where the level stands and what changes at each step.

## Acceptance criteria (testable)

- [ ] `StaffMapLadderCard` is replaced by an overlay exactly as in the design (size, axis, nodes, tick matrix, trigger chips, collapse strips, tooltip); data only from `OperationalState.ladder` and `StaffMapEscalation` (no rules in the view); all texts translated, long Polish names do not clip.
- [ ] Closes with the X button, Esc and a click outside the window; no input reaches the map while it is open.
- [ ] Opening it closes every other staff-map window (report, country card, decisions, strike / contact panels); opening any of them closes it.
- [ ] Tests: row / tick texts per level, current level marker, collapse tag per side, the three close paths, mutual exclusion with another window.

## Playtest (for the human)

1. Click the escalation chip: the window opens, level 1 marked NOW, ticks match the GDD table.
2. Close by X, by Esc and by clicking the dimmed map; open another window first and check it closes.
3. Raise the level to 5 and bring Russia below 50 %: nodes fill up to 5, COLLAPSE tag, hover on level 6 shows the conditions.
4. Switch to Polish: no clipped names; compare with `escalation_ladder_window.html` (variant B).

## Player manual

Update the ladder paragraph in docs/MANUAL.md (by `game-designer`).

## Out of scope

- Variants A and C; click-for-details on a level; history of who raised the level.

## Implementation notes

New `StaffMapLadderWindow` (`staff_map_ladder_window.gd`, full-screen overlay drawn in `_draw`, 1320×660 plate scaled with the viewport, 150 ms fade) replaces `StaffMapLadderCard` (deleted); owned by `StaffMapEscalationHud` (`ladder_opening` signal, `handle_key`). Data only from `OperationalState.ladder` and `StaffMapEscalation` (`collapse_strip` now also returns name / strength / readiness). `staff_map.gd`: opening the ladder closes decisions, strike mode, report, country card and debug panels, and each of those closes the ladder; `_modal_open()` blocks map keys, wheel, drag and click. New ESC_* i18n keys (EN + PL). Tests: `test_staff_map_ladder_window.gd`; `tools/screenshot.sh` state `ladder[:<level>]`.

Deviations from the mockup: no "START" tag on level 1 (the state does not hold the operation's start level); row labels use nominative keys `ESC_ROW_*`; tooltips for levels 0–5 added (n · name, may strike, trigger text); edge `#3a3f33` and the grey above-current number are local constants; the bottom command bar stays live and a click on it closes the window; the escalation chip is under the scrim, so closing is by X, Esc or a click outside; contact notice / queue are not closed by opening the ladder. English look and motion not seen by the agent.
