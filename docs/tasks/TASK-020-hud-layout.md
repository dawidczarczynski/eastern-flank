# TASK-020: HUD layout – turn bar, end-turn button, controls hint, turn banner

- **Status**: ready
- **Layers**: presentation (pure HUD model tested in `tests/unit/`)
- **Depends on**: **TASK-014** (theme), TASK-023 (strings through `tr()`), TASK-015 (the hint describes its controls). Soft: TASK-008 (button disabled while the queue plays), TASK-019 (`UnitStatus.is_done` for "ready units"). Reference: `docs/design/game_screen.template.html` lines 300–324 (top bar), 349–357 (hint, end turn), 396–401 (banner), 424–426 and 444–448 (logic).

## Goal

The screen frames the battle like the mock-up: whose turn it is and the turn number at the top centre, a big "End turn" button with the count of units that can still act at the bottom right, a short controls hint above it, and a banner announcing each new turn.

## Design decisions

- **Faction names are placeholders** until the setting is decided (GDD open question): player 0 **"Blue Force" / `BF`**, player 1 **"Red Force" / `RF`**, colours `UiPalette.FACTION`. They live in one presentation table (`UiPalette.FACTION_NAMES`, `FACTION_SHORT`), translated via CSV (pl: "Siły Niebieskie" / `SN`, "Siły Czerwone" / `SC`).
- The status label from TASK-000 is **removed**: turn info goes to the top bar, the hint to the hint box, victory/defeat to a persistent banner.
- "Ready units" = living units of the current player that are not `UnitStatus.is_done` (TASK-019; if TASK-019 is not done yet, add that helper here with the same rule).

## Layout & style (CSS px 1:1, colours from `UiPalette`)

- **Top shade**: full width, 120 px high, vertical gradient `rgba(10,12,9,0.55)` → transparent (`TextureRect` + `GradientTexture2D`).
- **Top bar**: centred, 14 px from the top, `PANEL_BG` + 1 px `PANEL_BORDER`; three sections:
  - Left (player 0), width 230, padding 10/16/10/10: 42×42 badge in faction colour with `BF` (Mono SemiBold 15, `FACTION_INK[0]`); name (Sans SemiBold 16); status line (Mono Medium 10.5, `TEXT_SECONDARY`, uppercase) `YOUR TURN · 3 UNITS` / `WAITING · 3 UNITS`. Active side: 3 px bottom border in faction colour, opacity 1; inactive: no border, opacity 0.5 (0.3 s fade).
  - Centre, padding 8/26, 1 px dividers left/right: `TURN` (Mono Medium 10, glyph spacing 2, `TEXT_SECONDARY`), turn number zero-padded to 2 digits (Mono SemiBold 32), then a 7×7 square in the active faction colour + `MOVE: <ACTIVE NAME>` (Mono Medium 11, `TEXT_MUTED`, uppercase).
  - Right (player 1): mirrored (badge on the right, `RF`, ink `FACTION_INK[1]`), status `3 UNITS · AI TURN` / `3 UNITS · WAITING`.
- **End-turn block**: bottom-right, 16 px margins, `PANEL_BG` + border: left part padding 8/16 with `READY UNITS` (Mono Medium 9.5, spacing 1, `TEXT_SECONDARY`) over `2 / 3` (Mono SemiBold 20); right part a `Button` `END TURN` (Sans Bold 15, uppercase, glyph spacing 2, padding 0/26, background = active faction colour, text `#121410`), hover brightness ×1.12, pressed ×0.92, **disabled** (alpha 0.5) when it is not the human's turn, after `game_over`, or while the TASK-008 queue plays. Pressing it = pressing Enter.
- **Controls hint**: right 16, bottom 88, max width 220, Mono Regular 10.5 (line height 1.6), `TEXT_MUTED`, background `rgba(17,19,15,0.6)`, padding 7/10, right-aligned, text = the TASK-015 controls hint.
- **Turn banner**: full width, vertical position 34 % of the viewport height, padding 22 px top/bottom, horizontal gradient transparent → `rgba(17,19,15,0.85)` at 30 % → same at 70 % → transparent; `TURN 02` (Mono Medium 12, spacing 4, `TEXT_SECONDARY`) above the active faction name (Sans Bold 40, uppercase, spacing 2, faction colour). Shown for **1.5 s** on every `turn_started` that changes turn or player (not at game start); a new one restarts the timer. On `game_over`: a persistent banner `VICTORY` (human won) / `DEFEAT`, in the winner's colour, subtitle `TURN NN`.
- All HUD containers `MOUSE_FILTER_IGNORE` except the button.

## Acceptance criteria (testable)

- [ ] Pure model `src/presentation/hud_model.gd` (`class_name HudModel`, static): `top_bar(state: GameState, human_player: int) -> Dictionary` with `turn_text` (`"01"`), `active_player`, and per player `{units: int, ready: int, status: String, active: bool}` (`status` is the untranslated key, e.g. `"YOUR TURN"`, `"AI TURN"`, `"WAITING"`); `banner_for(prev_turn: int, prev_player: int, turn: int, player: int) -> bool`; `result_banner(state, human_player) -> String` (`""`, `"VICTORY"`, `"DEFEAT"`).
- [ ] Tests `tests/unit/test_hud_model.gd` (3v3 setup on `Fixtures.plains_grid(3)`):
  - start: `turn_text == "01"`, player 0 active, `units == 3`, `ready == 3`, status `"YOUR TURN"`; player 1 `"WAITING"`.
  - after one unit moves all its points and attacks → player 0 `ready == 2`; after it dies → `units == 2`.
  - `current_player = 1` → player 1 status `"AI TURN"`, player 0 `"WAITING"`.
  - turn 12 → `"12"`; turn 7 → `"07"`.
  - `banner_for(1, 0, 1, 1) == true`, `(1, 1, 2, 0) == true`, `(1, 0, 1, 0) == false`.
  - `result_banner`: `winner == -1` → `""`; `winner == 0` (human 0) → `"VICTORY"`; `winner == 1` → `"DEFEAT"`.
- [ ] The HUD is built in code (e.g. `src/presentation/ui/battle_hud.gd`, a `Control` under `HUD/Root`) and refreshed from `turn_started`, `turn_ended`, `game_over` and after every executed command / drained queue; it reads state only through `HudModel`.
- [ ] The old `StatusLabel` is removed from `battle.tscn` (keep ext/sub resource ids consistent) and from `BattleController`.
- [ ] Every new string (`TURN`, `MOVE: %s`, `YOUR TURN`, `AI TURN`, `WAITING`, `%d UNITS`, `READY UNITS`, `End turn`, `VICTORY`, `DEFEAT`, faction names) is a CSV row with en + pl (`TURA`, `RUCH: %s`, `TWOJA TURA`, `TURA SI`, `OCZEKUJE`, `%d JEDN.`, `GOTOWE JEDNOSTKI`, `Zakończ turę`, `ZWYCIĘSTWO`, `PORAŻKA`); the localization coverage test passes.
- [ ] Agent visual check: take a screenshot with `tools/screenshot.sh` and compare with `docs/design/reference.png` / the values above: top bar centred with the blue side highlighted, `TURN 01`, `MOVE: BLUE FORCE`; bottom-right `READY UNITS 3 / 3` + blue `END TURN`; hint box above it; dark shade at the top edge; nothing overlaps at 1280×720. (The banner is not visible at start – by design.)

## Playtest (for the human)

1. `tools/run.sh` – top centre: blue badge `BF`, "Blue Force", `YOUR TURN · 3 UNITS`, `TURN 01`, red side dimmed.
2. Move and attack with one unit – bottom-right changes to `2 / 3`.
3. Click `END TURN` (or press Enter) – a banner `TURN 01 / RED FORCE` appears in the middle for 1.5 s, the red side lights up, the button is dimmed and does nothing while the AI plays.
4. When your turn comes back – banner `TURN 02 / BLUE FORCE`, counters reset to `3 / 3` (or fewer if units died).
5. Win or lose – a persistent `VICTORY` / `DEFEAT` banner; the button stays disabled.
6. Clicks on the map near the HUD panels still reach the map; the hint text matches the real controls.

## Out of scope

- Terrain panel (TASK-024), hover popup (TASK-021), loading screen, operation name, real faction names/emblems (GDD ideas), UI scaling.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
