# TASK-162: Lida airfield cannot be attacked: covered by the strike panel

- **Status**: done
- **Layers**: presentation
- **Depends on**: TASK-150 (done)
- **Sections**: docs/design/operational_map/README.md "HUD clear zone"
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Every installation (e.g. ru_airfield_lida in data/operations/suwalki_gap.tres) can be panned out from under the STRIKE panel and selected as a strike target while strike mode is open.

## Root cause (confirmed by the human)

The STRIKE panel (`staff_map_strike_panel.gd`, 420 px wide, top-right via `StaffMapStrikeHud.layout`, `covers(point)` blocks map clicks) is not a `StaffMapWindow`, so `StaffMap._clear_insets()` ignores it in the right inset. The pan clamp (`StaffMapCameraMath`, TASK-150) therefore lets eastern installations stay beneath it.

## Acceptance criteria (testable)

- [ ] While strike mode is open, the right inset of the clear zone is at least `viewport.x - panel.position.x` (panel 16 px margin included); e.g. viewport 1440 and panel x 1004 gives right inset >= 436. **[ASSUMPTION]**
- [ ] The inset is the max of the docked-window right inset and the strike panel inset (never the sum, never smaller than the docked one).
- [ ] An open strike report card docked/over the map is counted the same way (its right edge distance); a card that does not overlap the map adds 0.
- [ ] With strike mode open, the pan clamp lets the eastmost installation hex (Lida) be panned to screen x <= `clear_rect.end.x` (regression test, viewport 1440x900, default zoom).
- [ ] With strike mode closed, the right inset equals the docked-window inset again (0 with no window open); recomputed each frame via `_sync_insets` like docked windows. **[ASSUMPTION]**
- [ ] Opening strike mode re-clamps the camera by the minimal shift only if the new clamp requires it; when the view is already inside the new bounds the shift is 0 px.
- [ ] No other automatic camera move: no ease towards targets (the TASK-150 280 ms ease-out with the 40 px margin is not triggered by strike mode).
- [ ] Pure inset calculation lives in `StaffMapCameraMath`/`StaffMap` and is unit-tested in the style of `tests/unit/test_hud_clear_zone.gd`. **[ASSUMPTION]**

## Playtest (for the human)

1. Open the Suwalki Gap operation, press S to open strike mode.
2. Pan east until Lida can be brought into the free area left of the STRIKE panel.
3. Pick a weapon, hover and click Lida: the confirm card appears.
4. Close strike mode (S / Esc): the pan clamp relaxes and the map can be dragged back under the panel area.

## Player manual

docs/MANUAL.md "Deep strikes": one line that while the strike panel is open the map keeps every target clear of it (pan until the target is left of the panel).

## Out of scope

- Battle screen.
- Strike panel redesign or flipping it to the left side.
- Click-through of the panel margins; auto-ease of targets into view.
- GDD change: none expected.

## Implementation notes

- `StaffMapCameraMath.right_inset(docked, viewport_width, covers)`: max of the docked inset and `viewport.x - rect.x` of each rect on the right half (left-half rects add 0).
- `StaffMapStrikeHud.covered_rects()` (open panel + shown report card); `StaffMap._clear_insets()` feeds them in, so `_sync_insets` re-clamps each frame and releases on close. No ease added.
- Tests in `tests/unit/test_hud_clear_zone.gd` (inset 436 at 1440 px, max-not-sum, left card 0, eastmost target reaches the clear zone). The report card currently sits left, so it adds 0 today.
