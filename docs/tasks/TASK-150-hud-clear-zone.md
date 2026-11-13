# TASK-150: HUD clear zone – units never hidden under bars or panels

- **Status**: done
- **Layers**: presentation
- **Depends on**: –
- **Sections**: docs/design/operational_map/README.md "HUD clear zone" (spec), hud_clear_zone.html (variant A frames)
- **Model**: sonnet

## Goal

The player can always see and order every unit: the formation panel never covers its own unit, and the top / bottom bars never hide map area that cannot be panned away.

## Acceptance criteria (testable)

- [ ] Pure `StaffMapCameraMath` takes insets (top, bottom, left, right as screen px) and computes the clear zone; pan clamp lets the theatre edge reach the clear-zone edge (tests).
- [ ] Insets come from the real HUD: turn bar + chip (112), `ActionBar` (76), open docked windows (left x 16…436, right x 1124…1424); they update when a window opens / closes.
- [ ] Formation panel docks on the half opposite the selected counter (counter x > width/2 and left dock free → left, else right); re-docks only on a new selection, 120 ms fade; pure side rule tested.
- [ ] If the opposite dock is busy, the panel stays right and the camera eases the selected counter into the clear zone (280 ms ease-out, nearest point inside + 40 px margin); only on selection, never on hover; pure target maths tested.
- [ ] The right-click order ring stays inside the clear zone.
- [ ] Look unchanged (no new tokens); deviations from hud_clear_zone.html stated.

## Playtest (for the human)

1. Select a unit on the right side: the formation panel opens on the left; the unit stays visible and right-click orders work.
2. Select a unit on the left: the panel stays right.
3. Open the journal (left), select a right-side unit: the panel stays right, the map eases the unit into the free area.
4. Pan the map so a unit at the top / bottom edge is above / below the bars: it can be dragged fully into the visible zone.
5. Open the order ring on a unit near an edge: the ring is fully visible.

## Player manual

docs/MANUAL.md: one line – the panel docks opposite the selected unit and the map keeps units clear of the bars.

## Out of scope

- Slimmer bars, collapsible panel (variant B); the battle screen (separate task).

## Implementation notes

- Pure maths in `StaffMapCameraMath`: `clear_rect`, `ground_insets`, `clamp_position(..., insets)` (clear zone must stay inside the theatre), `panel_on_left`, `ease_shift`, consts `TOP_INSET` 112 / `EASE_MARGIN` 40 / `EASE_SECONDS` 0.28 (tests: `tests/unit/test_hud_clear_zone.gd`).
- `StaffMap`: `_clear_insets()` = 112 top, `ActionBar.HEIGHT` bottom, visible docked `StaffMapWindow`s left/right (centred confirm dialogs excluded); `_sync_insets()` each frame re-clamps when a window opens / closes. `min_zoom` unchanged on purpose (no zoom jump when a window opens).
- `_dock_panel_for` runs only on a new selection: side by `panel_on_left`, 120 ms fade when the panel appears or changes side, then `_ease_into_clear_zone` (280 ms cubic ease-out, shortest shift + 40 px margin). Opening a left window moves a left-docked panel back to the right.
- `StaffMapOrderRing` takes an optional `clear` callable and clamps ring and card inside it.
- Deviations from the mock: the fade is applied to the whole panel (no per-element); the ease also runs when the counter is under a bar, not only when the left dock is busy. A camera pan by the user does not cancel a running 280 ms ease.

- Follow-up 2026-11-13: the compact turn bar (`docs/design/operational_map/compact_turn_bar.html`, variant B) lowers `TOP_INSET` from 112 to 92 px (bar + chip; guarded by `test_turn_bar_is_compact`).
