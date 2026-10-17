# TASK-024: Terrain panel (bottom-left) with the path cost

- **Status**: done
- **Layers**: core (tiny pure coordinate helper) / presentation (pure panel model tested in `tests/unit/`)
- **Depends on**: **TASK-014**, **TASK-016a** (elevation), TASK-023 (strings), TASK-017 (the path label it replaces). Soft: TASK-002 (defense column and terrain display names), TASK-020 (same HUD root). Reference: `docs/design/game_screen.template.html` lines 326–347; `game_screen.scene.js` lines 542–550.
- **Model**: sonnet

## Why a separate task

The orchestrator's draft had the terrain panel inside the HUD layout task (TASK-020). Split out because it adds its own pure model, a core coordinate helper and the removal of the TASK-004 `Label3D` – together with the top bar/button/banner it would not fit one session.

## Goal

Hovering any tile tells the player what it is – terrain name, hex coordinate, movement cost, defense, elevation – and, with a unit selected, what the route there costs. This replaces the floating `2/3` label from TASK-004.

## Layout & style

Bottom-left, 16 px margins, width 250, `PANEL_BG` + 1 px `PANEL_BORDER`, `MOUSE_FILTER_IGNORE`, visible only while a map tile is hovered:
- Header row, padding 9/12/0: `TERRAIN` left, `HEX 03·05` right (Mono Medium 10, spacing 2, `TEXT_SECONDARY`).
- Name (Sans SemiBold 20), padding 4/12/10.
- Three equal columns, 1 px `DIVIDER` on top and between: caption (Mono Medium 9.5, spacing 1, `TEXT_SECONDARY`) over value (Mono Medium 13): `MOVE` / `DEFENSE` / `ELEV.`.
- Tags row (only if any), chips Mono Medium 10, padding 2/6, background `rgba(235,232,223,0.08)`, `TEXT_MUTED`.
- Path row (only when the hovered tile is a valid move target of the selected unit): background `rgba(235,232,223,0.06)`, padding 8/12, Mono Medium 11: `PATH COST` (`TEXT_SECONDARY`) left, `2 / 3 MP` right.

## Acceptance criteria (testable)

- [x] Core: `MapGenerator.axial_to_offset(c: Vector2i) -> Vector2i` (inverse of `offset_to_axial`). Test: round trip for every tile of a 12×10 map; `axial_to_offset(offset_to_axial(3, 5)) == (3, 5)`.
- [x] Pure model `src/presentation/terrain_panel_model.gd` (`class_name TerrainPanelModel`, static) `build(grid: HexGrid, coord: Vector2i, path_cost: int, moves_left: int) -> Dictionary` (`path_cost = -1` when there is no valid path) returning `{name, hex, move, defense, elevation, tags: PackedStringArray, path}` (untranslated keys / formatted numbers):
  - `hex`: 1-based offset column and row, zero-padded to 2, joined with `·` → offset (2, 4) gives `"03·05"`.
  - `move`: `str(move_cost)`; water → `"—"`.
  - `defense`: `"+N"` from `grid.defense_bonus` if TASK-002 is done (`"+0"` on plains), `"—"` on water; without TASK-002 the column shows `"—"`.
  - `elevation`: `"%d m" % roundi(maxf(elevation, 0) · 420 + 12)` (mock-up formula) – elevation 0.2 → `"96 m"`, −0.3 → `"12 m"`, 1.0 → `"432 m"`.
  - `tags`: `["Impassable"]` on water, otherwise empty.
  - `path`: `"2 / 3 MP"` for `path_cost = 2, moves_left = 3`; `""` when `path_cost < 0`.
  - `name`: `TerrainDefinition.display_name` if TASK-002 is done, otherwise `"Plains"`, `"Forest"`, `"Hills"`, `"Water"`.
- [x] Tests `tests/unit/test_terrain_panel_model.gd` for every bullet above, on hand-made grids with set elevations.
- [x] `BattleController` feeds the panel from the hovered tile (path cost from `HexGrid.reachable`, path validity from `path_to` – as in TASK-004); the TASK-004/017 path `Label3D` is **deleted** from `MapView`.
- [x] The TASK-003 selected-unit panel moves up so it sits above the terrain panel (8 px gap) and never overlaps it; it is removed later by TASK-021.
- [x] New strings (`TERRAIN`, `HEX %s`, `MOVE`, `DEFENSE`, `ELEV.`, `PATH COST`, `%d / %d MP`, `Impassable`, terrain names) have CSV rows en + pl (`TEREN`, `HEKS %s`, `RUCH`, `OBRONA`, `WYS.`, `KOSZT TRASY`, `%d / %d PR`, `Niedostępny`, `Równina`, `Las`, `Wzgórza`, `Akwen`).
- [x] Agent visual check: the default screenshot has no hovered tile, so the panel must **not** be visible; confirm that and compare panel styling with `docs/design/reference.png` only if a hover can be scripted (see TASK-017's optional screenshot hook). Otherwise the human checks.

## Playtest (for the human)

1. Hover a plains tile – bottom-left shows `TERRAIN · HEX cc·rr`, `Plains`, `MOVE 1`, `DEFENSE +0` (or `—` before TASK-002), an elevation in metres.
2. Hover water – `MOVE —`, `DEFENSE —`, an `Impassable` chip.
3. Hover a hill vs a lowland tile – the hill shows a higher elevation.
4. Select a unit and hover a reachable tile – a `PATH COST 2 / 3 MP` row appears; the floating number above the path is gone.
5. Move the cursor off the map – the panel disappears. With a unit selected, its info panel sits above the terrain panel, not on top of it.

## Out of scope

- City names, river/road tags (no such terrain), defense in % (GDD question), elevation affecting rules.

## Implementation notes

- Core: `MapGenerator.axial_to_offset` (inverse of `offset_to_axial`), round-trip tests in `tests/unit/test_terrain_generation.gd`.
- `TerrainPanelModel.build` (`src/presentation/terrain_panel_model.gd`) returns the specified keys plus the raw ints `path_cost` / `moves_left`. The view formats the path row from these with the translated `%d / %d MP` key. The untranslated `path` string is kept for the spec and the tests but is not displayed. Water is detected by `move_cost == Terrain.IMPASSABLE`.
- Widget `src/presentation/ui/terrain_panel.gd` (`TerrainPanel`) is built in code with `HudTheme`/`UiPalette`, and all of its controls use `MOUSE_FILTER_IGNORE`.
- Layout decision: the TASK-003 unit info panel and the terrain panel share a bottom-left `VBoxContainer` (16 px margins, 8 px separation, grows upward). Hidden children collapse, so the two can never overlap and no maximum height is hard-coded.
- `BattleController._draw_path_preview()` returns the path cost (-1 if none) and feeds the panel on every hover or selection change. The `MapView` path `Label3D` was deleted, and `show_path` no longer takes a label text.
- 12 new en/pl rows in `assets/i18n/strings.csv`.
- Known limitations:
  - Static captions are translated once at construction; there is no runtime locale switch yet.
  - The `—` glyph has not been seen on screen (water hover is not scripted).
- Visual check: the default screenshot shows no panel. `SCREENSHOT_SELECT_UNIT=1 tools/screenshot.sh` shows the panel (HEX 04·04, Plains, 1 / +0 / 183 m, PATH COST 2 / 3 MP) with the info panel stacked above it.
