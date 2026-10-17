# TASK-014: UI theme (fonts, palette, panels)

- **Status**: done
- **Layers**: presentation (pure palette/theme builder tested in `tests/unit/`)
- **Depends on**: nothing. Used by every later HUD task (TASK-020, -021, -024) and by unit labels (TASK-019). Reference: `docs/design/README.md` ("Palette", "Fonts"), `docs/design/game_screen.template.html`.
- **Model**: sonnet

## Goal

The HUD stops looking like default Godot: condensed IBM Plex text, monospaced numbers, dark translucent panels with a hairline border – the look of the mock-up, applied to the HUD that exists today (status label, unit info panel).

## Design decisions

- The theme is **built in code** (`HudTheme.build()`), not hand-written as a `.tres`: it is testable headless and avoids hand-editing font `ext_resource`s. Colours live in one place, `UiPalette`.
- Sizes are the design's CSS pixels 1:1 (no stretch mode change). At the 1280×720 screenshot size this matches the mock-up; UI scaling for other resolutions is an open question in the GDD.
- Letter-spacing from the CSS (`.08em`–`.3em`) is approximated with `FontVariation.spacing_glyph` (rounded to whole pixels, e.g. `.16em` at 10 px → 2 px).
- IBM Plex Mono has no Bold file in `assets/fonts/ibm_plex/`; CSS `700` Mono maps to **SemiBold**.

## Acceptance criteria (testable)

- [x] `src/presentation/ui/ui_palette.gd` – `class_name UiPalette`, `extends RefCounted`, constants (all `Color`):
  - `BACKGROUND = #11130f`, `PANEL_BG = rgba(17,19,15,0.84)`, `PANEL_BG_STRONG = rgba(17,19,15,0.94)` (popup), `PANEL_BORDER = rgba(235,232,223,0.12)`, `DIVIDER = rgba(235,232,223,0.10)`;
  - `TEXT = #ebe8df`, `TEXT_SECONDARY = #a8a598`, `TEXT_MUTED = #d8d5cb`, `TEXT_DIM = #c9c6bb`, `ACCENT = #e2c069`;
  - `HP_HIGH = #b9d38a`, `HP_MID = #e2c069`, `HP_LOW = #e07c5e`, `HP_EMPTY = rgba(233,231,223,0.12)`;
  - `FACTION = [#5b93d6, #d76a52]` (player 0, player 1) and `FACTION_INK = [#0f1a26, #2a110b]` (text on a faction-coloured badge);
  - `static func hp_color(hp: int, max_hp: int) -> Color` – `HP_HIGH` when `hp / max_hp > 0.6`, `HP_MID` when `> 0.35`, otherwise `HP_LOW` (float division; `max_hp <= 0` → `HP_LOW`).
- [x] `src/presentation/ui/hud_theme.gd` – `class_name HudTheme`, `static func build() -> Theme`:
  - `default_font` = IBM Plex Sans Condensed Regular, `default_font_size = 14`;
  - `Label/colors/font_color = TEXT`;
  - `PanelContainer/styles/panel` = `StyleBoxFlat` with `bg_color = PANEL_BG`, `border_width_*` = 1, `border_color = PANEL_BORDER`, all corner radii 0, content margins 12 (left/right) and 9 (top/bottom);
  - type variations (`Label` base): `TitleLabel` (Sans Condensed SemiBold, 20 px), `CaptionLabel` (Mono Medium, 10 px, `spacing_glyph = 2`, colour `TEXT_SECONDARY`), `ValueLabel` (Mono Medium, 13 px), `MonoLabel` (Mono Regular, 10.5 → 11 px, colour `TEXT_MUTED`);
  - `Button`: Sans Condensed Bold 15 px, flat `StyleBoxFlat` (no corner radius); colours for hover/pressed are set per button by TASK-020.
  - Fonts are loaded once (static cache), from `res://assets/fonts/ibm_plex/*.ttf` via `load()`.
- [x] Tests `tests/unit/test_hud_theme.gd`:
  - `UiPalette.hp_color`: (10, 10) → `HP_HIGH`; (7, 10) → `HP_HIGH`; (6, 10) → `HP_MID` (0.6 is not > 0.6); (4, 10) → `HP_MID`; (3, 10) → `HP_LOW`; (0, 10) → `HP_LOW`; (5, 0) → `HP_LOW`.
  - `PANEL_BG` equals `Color(17/255., 19/255., 15/255., 0.84)` (tolerance 0.002); `FACTION[0]` equals `Color.html("#5b93d6")`.
  - `HudTheme.build()`: `default_font` is non-null and its `get_font_name()` contains `"IBM Plex Sans Condensed"`; the `PanelContainer` stylebox is a `StyleBoxFlat` with the values above; the four type variations exist (`get_type_variation_base(&"CaptionLabel") == &"Label"`, …); building twice returns themes with the same font resources (cache).
- [x] The HUD gets a full-rect root `Control` (`HUD/Root`, `mouse_filter = IGNORE`, `theme = HudTheme.build()`); the status label and the TASK-003 unit info panel are moved under it (in code is fine; if `battle.tscn` is edited, keep ids consistent). Their per-node `font_size = 18` overrides are removed so the theme applies.
- [x] Clicks on the map under the HUD still work (all new containers use `MOUSE_FILTER_IGNORE`).
- [x] Agent visual check: take a screenshot with `tools/screenshot.sh` and compare with `docs/design/reference.png` / the values above: the status text is in a condensed sans font in `#ebe8df`; numbers stay readable at 1280×720. (The unit info panel is only visible with a selection – check it in the playtest.)

## Playtest (for the human)

1. `tools/run.sh` – the status text at the top-left uses the condensed IBM Plex font.
2. Select a unit – the bottom-left info panel is a dark translucent box (map visible through it) with a thin light border and square corners, text in the condensed font.
3. Clicking a tile right behind the panel's area (outside its rectangle) still selects/moves as before.
4. Text with Polish characters is not tested yet (TASK-023), but `ąęłńóśźż` should render if you type it into the status label temporarily.

## Out of scope

- New HUD elements and layout (TASK-020, TASK-024), hover popup (TASK-021), unit labels (TASK-019), translations (TASK-023).
- UI scaling / stretch mode for resolutions other than ~1280–1600 wide (GDD open question).
- A `.tres` theme editable in the Godot editor (possible later by saving `HudTheme.build()` once).

## Implementation notes

- `UiPalette` (`src/presentation/ui/ui_palette.gd`): the colour constants and `hp_color()`.
- `HudTheme.build()` (`src/presentation/ui/hud_theme.gd`) builds the theme in code. Fonts are loaded once into a static cache, and a missing font file triggers `push_error`.
  - `default_font` is the Sans Condensed Regular `FontFile` itself, not a variation.
  - Letter spacing is done with cached `FontVariation`s (`spacing_glyph`); only `CaptionLabel` uses it (2 px).
  - Mono "Bold" is mapped to SemiBold, as the task specifies.
  - Button styleboxes are transparent and flat for every state; TASK-020 sets the per-button colours.
- `BattleController._build_hud_root()` creates `HUD/Root` (full rect, `MOUSE_FILTER_IGNORE`, themed). It reparents `StatusLabel` under Root (now with `MOUSE_FILTER_IGNORE`), and the info panel is built under Root. Removed: the `font_size = 18` override in `battle.tscn` and `HUD_FONT_SIZE`.
- Tests: `tests/unit/test_hud_theme.gd` (7 tests, including the Button style).
- Screenshot check: the status text renders in condensed IBM Plex, off-white, 14 px. Known limitation: with no panel behind it, the light text has low contrast against the light grey background. The mock-up puts this text in panels, which comes with the TASK-020 layout. The info panel was not visible in the screenshot (it needs a selection), so the human checks it in the playtest.
- The "ObjectDB leaked / resources still in use" warnings at exit were already there before this task.
