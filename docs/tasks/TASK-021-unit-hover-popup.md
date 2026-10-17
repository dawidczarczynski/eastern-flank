# TASK-021: Unit hover popup

- **Status**: ready
- **Layers**: presentation (pure model + placement tested in `tests/unit/`)
- **Depends on**: **TASK-014**, TASK-003 (replaces its panel), TASK-019 (`UnitStatus`, `short_name`), TASK-023 (strings). Soft: TASK-024 (layout next to the terrain panel), TASK-002 (terrain defense row), TASK-015 (hidden while dragging). Reference: `docs/design/game_screen.template.html` lines 359–394 and 435–440; `game_screen.scene.js` lines 488–508.

## Goal

Hovering any unit – yours or the enemy's – shows a card with its strength and stats next to the cursor, so the player can size up a target before attacking. It replaces the TASK-003 bottom-left panel.

## Layout & style

- Card width **320**, background `PANEL_BG_STRONG` (`rgba(17,19,15,0.94)`), 1 px border `rgba(235,232,223,0.14)`, `MOUSE_FILTER_IGNORE`.
- Top strip 3 px in the faction colour.
- Header, padding 10/14: row with the unit type (`display_name`, Mono Medium 10, uppercase, spacing 1, `TEXT_SECONDARY`) left and the faction name (TASK-020 placeholder names) in faction colour right; below the name (Sans SemiBold 21) – for now the translated `display_name` again (unit names are a GDD idea).
- **Strength**: row `STRENGTH` (caption) / `hp / max` (Mono, `TEXT`); below it `max_hp` segments in one row, gap 2 px, height 7 px, filled segments (`i < hp`) in `UiPalette.hp_color(hp, max)`, empty ones `HP_EMPTY`.
- **Stats grid**: 2 columns, gaps 9 (rows) / 16 (columns), padding 10/14/12; each stat: label (Sans 12, `TEXT_DIM`) + value (Mono SemiBold 12.5) on one line, under it a 2 px bar (track `DIVIDER`, fill `#d8d5cb`, width = `min(1, value / scale)`). Stats: `Attack` (scale 10), `Defense` (10), `Moves` shown `moves_left/move_points` (bar `moves_left / 6`), `Range` (bar `attack_range / 6`), and `Terrain defense` `+N` (bar `N / 3`) only if TASK-002 is done.
- **Footer**: 1 px top divider, padding 9/14, Mono Medium 11: 7 px round dot + status – enemy: `Enemy unit` (dot in its faction colour); own and `UnitStatus.is_done`: `Done this turn` (`#a19f95`); own otherwise: `Ready` (`HP_HIGH`); own unit that already attacked but can still move: `Ready · already attacked`.
- Not ported now: portrait area (follow-up: `SubViewport` render with the mock-up's portrait lighting, `makePortraits`), rank pips, tags, designation line, ammo/vision/hard-soft stats (GDD ideas).
- **Placement** (mock-up rule, adapted to the real card height `h`): `x = mouse.x + 24`; if `x + 330 > viewport.width` → `x = mouse.x − 344`; `x = max(8, x)`; `y = clamp(mouse.y − 80, 96, viewport.height − h − 16)` (96 keeps it under the top bar; if that range is empty, `y = 96`).

## Acceptance criteria (testable)

- [ ] Pure model `src/presentation/unit_popup_model.gd` (`class_name UnitPopupModel`, static): `build(state: GameState, unit: Unit, viewer_player: int) -> Dictionary` with `type`, `faction`, `color`, `name`, `hp`, `max_hp`, `segments: Array[Color]`, `stats: Array[Dictionary]` (`{label, value: String, fill: float}`), `status`, `status_color`; and `placement(mouse: Vector2, viewport: Vector2, card: Vector2) -> Vector2`.
- [ ] Tests `tests/unit/test_unit_popup_model.gd`:
  - fresh own infantry: `hp 10`, `max_hp 10`, 10 segments all `HP_HIGH`; stats `Attack "4"` fill 0.4, `Defense "3"` 0.3, `Moves "3/3"` 0.5, `Range "1"` ≈ 0.1667; status `"Ready"`.
  - own cavalry with `hp = 3`: 8 segments, the first 3 `HP_MID` (3/8 = 0.375 > 0.35), the remaining 5 `HP_EMPTY`; with `hp = 2` the first 2 are `HP_LOW`.
  - own unit `moves_left = 0`, `has_attacked = true` → `"Done this turn"`; `moves_left = 2`, `has_attacked = true` → `"Ready · already attacked"`.
  - enemy unit (viewer 0, owner 1) → `"Enemy unit"`, `status_color == UiPalette.FACTION[1]`.
  - `placement((100, 300), (1280, 720), (320, 330))` → `(124, 220)`; `((1100, 300), …)` → `(756, 220)`; `((10, 50), …)` → `(34, 96)`; `((600, 700), …)` → `(624, 374)`.
- [ ] The card appears while the hovered tile (TASK-004 hover tracking) holds a living unit, follows the mouse, and hides when the cursor leaves the unit's tile, during a camera drag (TASK-015), while the TASK-008 queue plays, and on `game_over`. Refreshes on `unit_attacked`/`turn_started` while visible.
- [ ] The TASK-003 bottom-left panel is removed; `UnitInfo.lines()` is either reused by the model or deleted together with `test_unit_info.gd` (agent's call – note it).
- [ ] New strings (`STRENGTH`, `Attack`, `Defense`, `Moves`, `Range`, `Terrain defense`, `Enemy unit`, `Done this turn`, `Ready`, `Ready · already attacked`) have CSV rows en + pl (`SIŁA JEDNOSTKI`, `Atak`, `Obrona`, `Punkty ruchu`, `Zasięg (heks)`, `Teren · obrona`, `Jednostka przeciwnika`, `Wykonała ruch w tej turze`, `Gotowa do działania`, `Gotowa · już atakowała`).
- [ ] Agent visual check: the default screenshot has no hover – check that no card is visible; compare the card with `docs/design/reference.png` only if a hover can be scripted (TASK-017's optional hook), otherwise leave it to the human.

## Playtest (for the human)

1. Hover your infantry – a card appears right of the cursor: blue top strip, `INFANTRY` / `Blue Force`, 10 green segments, Attack 4, Defense 3, Moves 3/3, Range 1, `● Ready`.
2. Hover an enemy cavalry – red strip, 8 segments, `● Enemy unit` with a red dot.
3. Damage an enemy to 3/8 – its segments are 3 yellow + 5 empty; at 2/8 they turn orange-red.
4. Hover a unit near the right screen edge – the card flips to the left of the cursor; near the top it stays below the turn bar.
5. Drag the camera while over a unit – the card hides; the old bottom-left unit panel no longer exists.

## Out of scope

- Unit portrait render (follow-up), comparing attacker vs target / damage preview, pinning the card.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
