# TASK-049: Overlay readability – reach outline, dim outside, hover-only fill, faint fading grid

- **Status**: done
- **Layers**: presentation (`map_view.gd`, `overlay_geometry.gd`, `unit_view.gd` marker values, `battle_controller` key), tests
- **Depends on**: – (TASK-017 overlays and the TASK-011 range outline are done). First task of the realism track (see BACKLOG "Visual realism").
- **Model**: sonnet

## Goal

Selecting a unit no longer paints the whole map blue. The reachable area is shown as one clean outline around its outer edge, the rest of the map is gently dimmed, and the ground itself stays visible. The hex grid is a faint hint, not dark strips, and can be switched off.

## Design

Today every reachable tile gets a 0.9-scale wash (alpha 0.2) plus its own ring (alpha 0.55); the green gaps between the patches read as thick dark strips (see `docs/images/gameplay.png`). The attack range (TASK-011) already draws only the outer boundary (`OverlayGeometry.boundary_edges` + `edge_ribbons`) – reuse that.

| Overlay | New look |
|---|---|
| Reach | **outline only** along the outer boundary of `reach ∪ {unit tile}`: ribbon width **0.06**, faction colour, alpha **0.85**, lift 0.045, 3 segments per edge. No per-tile rings, no per-tile wash. Holes in the area (unreachable tiles inside it, e.g. a lake) get their own outline, which `boundary_edges` already produces. |
| Outside dim | one merged mesh of full hex patches (scale **1.0**, so no gaps) over every **land** tile **not** in `reach ∪ {unit tile}`: colour `#0b0f0a`, alpha **0.22**, lift 0.02. Shown only while a unit is selected. Water tiles are not dimmed. |
| Hover inside reach | the hovered reachable tile gets the faction-colour wash (patch 0.92, alpha **0.18**) under the existing white pulsing ring. Outside reach: only the white ring (fill removed). |
| Attack targets | unchanged (they must stay the strongest marker). |
| Grid lines | colour `#e9eddc` (light, not dark), alpha from `grid_alpha(distance, selected)` (below), updated when the camera distance changes; never drawn over water. |
| Unit base marker (`unit_view.gd`) | fill alpha 0.1 → **0.06**, ring alpha 0.95 → **0.8**; selected/hovered values unchanged. |

- `OverlayGeometry.grid_alpha(distance: float, selected: bool) -> float`: linear from **0.16** at `CameraMath.MIN_DISTANCE` (7) to **0.05** at `MAX_DISTANCE` (46), clamped; ×**1.5** while a unit is selected (hex counting matters then). Grid mode `off` → 0.
- **Grid toggle**: key **G** cycles the grid mode `auto` (default, the formula above) → `off` → `auto`. The mode is a view setting (not saved, not in the match record). Ignored while text input has focus; works during animations and the AI turn (like camera keys).
- No game rules in the view: reach still comes from `HexGrid.reachable`.

## Acceptance criteria (testable)

- [x] `OverlayGeometry.grid_alpha`: `(7, false) == 0.16`, `(46, false) == 0.05`, `(26.5, false) == 0.105` (±0.001), `(100, false) == 0.05`, `(3, false) == 0.16`, `(7, true) == 0.24`.
- [x] `MapView.show_reach(coords, color, unit_tile)` builds the outline from `boundary_edges(coords + [unit_tile])`: for a unit in the middle of a 3×3 plains fixture with its 6 neighbours passed as reach (radius-1 hex area = 7 tiles), the outline has exactly 18 boundary edges; the reach wash mesh and per-tile ring meshes no longer exist (no `_reach_fill`/`_reach_ring` instances with geometry).
- [x] The dim mesh covers every land tile outside `reach ∪ {unit tile}` and no water tile (count patches: `land_tiles − reach − 1`); it is hidden after `clear_highlights()`.
- [x] Hover fill: shown in the faction colour only when the hovered tile is in the current reach; no fill for tiles outside reach or without a selection; the white ring is shown in all cases as before.
- [x] Grid mode: pressing G (simulated `InputEventKey`) switches `auto → off → auto`; in `off` the grid instance is hidden; in `auto` its material alpha equals `grid_alpha(camera distance, has selection)`.
- [x] Grid lines have no vertices inside water tiles.
- [x] Existing overlay tests pass (update the ones that asserted per-tile reach rings).
- [x] Agent visual check: `SCREENSHOT_SELECT_UNIT=1 tools/screenshot.sh .screenshots/reach.png --frames=20` – one continuous blue outline around the reachable area, terrain inside it clearly visible (grass, trees), outside slightly darker; no dark strips between hexes.
- [x] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. Select your infantry: a single blue outline surrounds the tiles it can reach; outside the outline the map is slightly darker. Inside, the ground and trees look untouched.
2. Move the cursor inside the outline: the hovered tile gets a light blue wash under the white pulsing ring; outside the outline only the ring.
3. Select a unit next to a lake: the outline goes around the water, not across it.
4. Zoom in and out: the grid is faint up close and almost invisible zoomed out, never darker than the ground.
5. Press G: the grid disappears; press G again: it is back.
6. Select the rocket artillery: the amber range outline and the blue reach outline are both readable and clearly different.
7. Judge: is the reach still obvious enough at full zoom-out? If not, report the zoom level – the dim alpha may need to go up.

## Player manual

- Section 10 (Screen): describe the selection look – "Selecting a unit outlines the area it can reach in your colour and slightly darkens the rest of the map; the tile under the cursor is tinted when the unit can move there."
- Section 11 (Controls): add row "Show / hide the hex grid | G". Mention that the grid fades as you zoom out.
- Section 11, "Move the selected unit": "Left-click a tile inside the outlined area" instead of "a highlighted tile".

## Out of scope

- Threat ranges, attack-move previews, path dots restyle (unchanged).
- Terrain shader changes (TASK-055); a reach mask in the terrain shader could replace the dim mesh later.

## Implementation notes

- `OverlayGeometry.grid_alpha()` (+ `GRID_ALPHA_NEAR/FAR`, `GRID_SELECTED_FACTOR`); `MapView.show_reach(coords, color, unit_tile)` draws only the `boundary_edges` outline (`_reach_line`) and a merged `_dim` mesh over land outside the reach; per-tile reach wash/rings removed. Hover wash only inside the current reach (refreshed when the selection changes under a still cursor).
- Grid: `#e9eddc`, water tiles contribute no grid edges (land/water shore edges are still drawn by the land side), alpha via `MapView.set_camera_distance()` (called from `BattleController._process`, early-out when unchanged – only a material alpha changes), `cycle_grid_mode()` auto/off.
- G is handled in `BattleController._unhandled_input` before the turn/animation gate (like F5); ignored with Ctrl/Alt/Meta held or while a `LineEdit`/`TextEdit` has focus. `CameraRig.distance()` getter added. HUD controls hint now lists "G – grid".
- Unit base marker: fill 0.06, ring 0.8.
- Tests: `test_overlay_geometry.gd` (grid_alpha), new `test_map_view_overlays.gd` (18-edge outline, only outline + dim added, dim count/hide, hover fill, grid alpha/mode, no grid in water, G key). The text-focus case is not unit-tested (needs a viewport in the tree).
- Visual check: one continuous outline, terrain inside stays visible.
- Playtest tuning (2026-10-21, human: "the range is too weak, barely visible"): outline width 0.06 → **0.1** and alpha 0.85 → **1.0**; dim alpha 0.22 → **0.6** and lift 0.02 → **0.035**. Measured in the screenshot: blending is in linear space, so 0.4 only took the bright outside plains (96 → 67) down to about the level of the wooded tiles inside the outline (80), and the contrast disappeared. At 0.6 the outside is 50 against 80 inside. The Design table above keeps the original spec values.
