# TASK-139: Full-width bottom command bar (battle and staff map)

- **Status**: done
- **Layers**: presentation
- **Depends on**: –
- **Sections**: docs/design/hud_v3/README.md "07 Bottom command bar", docs/design/hud_v3/bottom_bar.html (variant A, accepted 2026-11-10)
- **Model**: sonnet

## Goal

Keyboard shortcuts get buttons: one full-width bar docked to the bottom, with its own content in the battle and on the staff map. Everything that sat along the bottom lives in it.

## Acceptance criteria (testable)

- [x] `ActionBar` is full width, 76 px high, docked to the bottom; zones left / centre / right.
- [x] Battle: operation label + terrain strip (left), GRID / RESET / DESELECT / SAVE (centre), ready counter + End turn (right); no key-hint rows.
- [x] Staff map: hex card in the left zone, nine buttons in the centre, Save only here, End turn stays in the top turn bar.
- [x] Toasts and the border prompt float above the bar.
- [ ] (not done, see notes) Camera treats the bar as a bottom inset (decided "ok" by the human; not done: see notes).

## Playtest (for the human)

1. Battle: hover hexes (strip fills, route chip with a selected unit), click each button, End turn, enemy turn greys it.
2. Staff map: hover hexes, click each toggle (it stays lit), Save, Cancel with a selected formation.

## Player manual

Section 10 Screen and the staff map controls table.

## Out of scope

- Narrow windows (< 1280 px): keycap-only buttons.

## Implementation notes

- Buttons are icons (`ActionIcons`, drawn from polylines) with a hover tooltip (`ActionTooltip`: name, key, description); no labels or key caps on the bar, so no width switching. End turn moved from the staff map top bar to the bar (same spot as in the battle); strips have fixed slot widths. The camera bottom inset (human said ok) is NOT done: the bar takes mouse input so picking is unaffected, but the map centre is not shifted up. The bottom screen-corner brackets now sit behind the bar.
- Rebuilt `ActionBar` as the docked bar (`add_left` / `add_right` slots); `TerrainPanel` and `StaffMapCard` became horizontal strips.
