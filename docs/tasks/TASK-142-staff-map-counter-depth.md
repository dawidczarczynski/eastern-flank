# TASK-142: Staff map counters and markers as hex game tiles

- **Status**: done
- **Layers**: presentation
- **Depends on**: –
- **Sections**: docs/design/operational_map/README.md "Counter and marker tokens", `unit_tokens_hex.html` (variant D)
- **Model**: sonnet

## Goal

Counters and installation markers on the tilted staff map look like physical wargame tiles lying on a realistic map (no cartoon outlines); flat map = flat tiles.

## Acceptance criteria (testable)

- [ ] `StaffMapCounter` draws the hex tile exactly as in "Counter and marker tokens": a hexagon base (same for both sides), the raised side plate (own rectangle with the cut corner, enemy diamond), wall, bevel, engraved glyph and echelon bars, 5 studs, shadow; the old slab code (wall hull as a box, rim, hover rise, back plates) is replaced, not kept.
- [ ] `StaffMapInstallationMarker` uses the same tile (base R 18, chamfered square plate with the class glyph, 4 studs; destroyed = grey + cross); depot, airfield, air defence and command post look alike.
- [ ] Depth follows the camera: `StaffMapCounter.depth_for_pitch` (0 flat map = flat hexagon, no wall / shadow; 1 from 35° up); counters and installations get it from `StaffMap._on_pitch_changed`.
- [ ] All states: hover, selected brackets, moved, low, in contact (ground ring), estimated ghost once that state exists, stack (3 stacked tiles + badge), has order, country tag, join pulse. No outlines except for hover and low.
- [ ] `hits()` / `body_rect()` fit the hexagon + thickness + studs; picking test updated; fixed pixel size at all zooms and pitches (0°, 35°, 50°).
- [ ] 60 FPS kept with all formations; no new palette colours.

## Playtest (for the human)

1. Staff map: `V` and Ctrl+wheel at 0° / 35° / 50°, zoom Z0–Z2: flat map shows flat hexagon tiles, tilted map shows thin tiles with a bevel and an engraved symbol.
2. Own = rectangle plate, enemy = diamond plate on the same hexagon base; select, hover, order, contact, stack (3 tiles stacked), low strength.
3. Depot, airfield, air defence and command post use the same tile; compare with `docs/design/operational_map/unit_tokens_hex.html`.

## Player manual

None (visual only).

## Out of scope

- Other token directions (slab, pin, glass, miniature); changes to counter data or rules.

## Implementation notes

_First version (extruded slab, depth from pitch, frameless edges) was implemented and rejected by the human on 2026-11-11; its pitch-driven `depth` plumbing (`depth_for_pitch`, `set_depth` in StaffMapCounters / StaffMapInstallations, `_on_pitch_changed`) stays; the drawing is replaced by variant D. The estimated-enemy ghost needs a state that does not exist yet._

_Second version (variant D, 2026-11-11): `StaffMapCounter` draws the hex tile (statics `draw_base`, `base_colour`, `hex_points`, `in_hex`, `squash`, `draw_shadow`; the whole tile is drawn under a (1, squash) transform; wall = hull of the hexagon and itself lowered; plate raised 1.6 px; engraved glyph / echelon; 5 studs; stack = up to 3 tiles, front one lifted). `StaffMapInstallationMarker` reuses the base (R 18, chamfered plate, 4 studs). Slab code, hover rise and back plates removed; `hits()` / `body_rect()` follow hexagon + wall + stack. Stud placement is tuned so the outer studs sit on the base edge (checked in a screenshot at 1.1 zoom, 35°, not at 0° / 50°). Estimated ghost still missing (no state yet)._
