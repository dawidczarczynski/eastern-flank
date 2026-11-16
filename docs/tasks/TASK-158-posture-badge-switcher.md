# TASK-158: Staff map – posture badge on counters and one-click posture switcher

- **Status**: ready
- **Layers**: presentation
- **Depends on**: TASK-153, TASK-154
- **Sections**: GDD "Orders and postures"; design/operational_map/posture_badge_switcher.html (variant A, accepted 2026-11-16) and the README bullet "Posture badge and switcher"; `StaffMapCounter`, `StaffMapUnitStrip`, `StaffMapOrderGesture` as the nearest parts
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The player sees the posture (march / advance / defend) of every own formation on the map at a glance and changes it with the mouse – for a selected formation and for one with an issued order – without using the keyboard.

## Acceptance criteria (testable)

- [ ] Glyphs for the three postures drawn as polygons in a shared helper (march = double chevron, advance = spear, defend = arc over a bar); pure geometry covered by a unit test.
- [ ] Badge on every own `StaffMapCounter` at Z1+ per the mockup (disc Ø 18 px, lower-left of the tile); none on enemy tiles, hidden at Z0, independent of layer O; estimated tiles keep the 55 % look without a badge.
- [ ] `StaffMapPostureSwitcher`: three-segment strip (icon + name, caption "MARCH · 100 %") under the selected own formation on its side's turn, flipping above the tile when the order line leaves downwards; hover state, active = `ui.amber`, tooltip after 250 ms; inert and 35 % when disabled (enemy turn, modal, slide, strike mode).
- [ ] Pure model (`StaffMapPostureSwitcherModel`): segments, active posture, flip side, enabled flag, tooltip text from `OperationalPosture` data (move %, name) – tested without a scene.
- [ ] Click on a segment: formation with an order → `SetPostureCommand` (order kept, route re-planned, line restyled); formation without an order → arms the posture for the next target click (same state as keys 1–3 today). Same posture clicked = no-op. Keys 1–3 keep working as optional shortcuts and are only named in the tooltip.
- [ ] Views only read state and react to `formation_posture_changed`; no rules in the view layer.
- [ ] Screen-space, fixed pixel size at every zoom; no per-frame rebuilds; 60 FPS unchanged.

## Playtest (for the human)

1. Zoom to Z1: every own counter has a small badge (», spear, arc) at its lower-left; enemy counters have none. Zoom out to Z0: badges disappear.
2. Click an own counter: a strip MARCH / ADVANCE / DEFEND appears under it, the current one in amber. Click another segment with no order: the posture is armed; click a hex: the order is issued with that posture.
3. Select a formation with an issued order, click DEFEND: the line restyles, the order stays, the badge changes. Hover a segment: tooltip with the move %.
4. Give an order that leaves downwards: the strip appears above the counter. End the turn: the strip is dimmed and does not react.
5. Never touch the keyboard: everything above works with the mouse alone.

## Player manual

Orders: every own formation shows its posture as a badge; select it and click MARCH / ADVANCE / DEFEND under it (keys 1–3 are an optional shortcut); changing the posture of an issued order keeps the order.

## Out of scope

- Posture glyph at the order-line head (TASK-157), rules changes (changing posture stays free), bottom-bar control (variant B) and badge-as-button (variant C, rejected).

## Implementation notes

(to fill in)
