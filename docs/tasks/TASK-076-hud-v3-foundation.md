# TASK-076: HUD v3 foundation – fonts, tokens, chamfered frame primitives, screen decoration

- **Status**: ready
- **Layers**: presentation (`src/presentation/ui/`: `UiPalette`, `HudTheme`, new `HudShapes` / `FramedPanel`, new `ScreenDecor`), assets (fonts), docs (ADR, docs/design/README pointer), tests. Role: **presentation-engineer**.
- **Depends on**: –  (soft: TASK-014 done – theme being replaced)
- **Model**: sonnet

## Goal

The shared building blocks of the new "tactical C2" HUD from the design handoff ([docs/design/hud_v3/README.md](../design/hud_v3/README.md), reference render: open [hud-elementy.html](../design/hud_v3/hud-elementy.html) in a browser) exist, so TASK-077 … TASK-082 only compose them. Nothing the player sees changes except the screen decoration.

## Design

- **Fonts**: Chakra Petch (600/700, display + 400 description body) and JetBrains Mono (400–700), both SIL OFL. The HTML only embeds them as woff2 blobs – download the TTFs (Google Fonts / upstream repos, OFL) into `assets/fonts/chakra_petch/` and `assets/fonts/jetbrains_mono/` with each `OFL.txt`; Polish diacritics (ąćęłńóśźż) must be present. `HudTheme` gets the new files and keeps `font(file, spacing)`; IBM Plex stays only where still used (remove once TASK-077 … 080 are done). Record the font swap as an ADR.
- **Tokens** in `UiPalette` (single place, values from the README "Design Tokens"): `BG_APP #0a0c09`, `PANEL rgba(8,11,8,.86)`, `PANEL_STRONG .93`, `LINE rgba(232,176,74,.34)`, `AMBER #e8b04a`, `TEXT #dfe5d6`, `MUTED #8d9585`, `DESC #b7bfae`, HP good/mid/low/empty, disabled/error `#e07c5e`, note bg/text. Faction colours and inks keep coming from `FactionDefinition` (design shows #5b93d6 / #d76a52 as sample – check the two faction `.tres` colours against them and adjust the data if the human agrees; do not hard-code).
- **`HudShapes`** (pure, testable): chamfer polygons `chamfer(size, c_tl, c_tr, c_br, c_bl) -> PackedVector2Array`; hex-badge polygon; skewed-segment polygon; trapezoid (turn bar); header-tab polygon; tick-ruler / hatch geometry (thin: 2 px stripes every 6 px at 135°, wide: 6 px every 9 px).
- **`FramedPanel`** (`Control`, `_draw`-based): the "outer 1 px line + inner panel fill" frame from the README as one polygon pair, any chamfer per corner, optional header tab (text, fill colour, right-hand text), optional corner brackets. Content goes in a child container with margins. Blur behind the panel is not required (Godot `backdrop_filter` equivalent optional; plain translucent fill is acceptable).
- **`HatchBar`** control (thin / wide hatch in a given colour, size) and **`Bracketed`** tag helper (`[ text ]` with amber brackets, mono 10.5).
- **`ScreenDecor`** (full-rect, mouse ignore, drawn above the 3D view, below the HUD panels): vignette `radial 110%×85%, transparent 62% → rgba(0,0,0,.42)`, scanlines (1 px at 4 px period, α .05), 22 px corner brackets (1.5 px `LINE`) at 10 px inset. Must stay cheap (one `ShaderMaterial` canvas_item or two textures) – 60 FPS budget, check with `FramePacing` unchanged.

## Acceptance criteria (testable)

- [ ] `HudShapes` unit tests: chamfer polygon vertex counts/positions for 0..4 chamfered corners, trapezoid, hex badge (40×36), skewed segment, tab; hatch geometry stays inside its rect.
- [ ] `UiPalette` constants equal the README values (test with a few spot checks); no colour literal for the new look outside `UiPalette`.
- [ ] Fonts load (`HudTheme` test: every new font file loads, has glyphs for `ąćęłńóśźż ▸ ◆ ■ ↵` – fall back to a symbol font/drawn shapes for any missing glyph and note it).
- [ ] `ScreenDecor` ignores the mouse and does not change the layout; with it on, `tools/screenshot.sh` still renders and no script errors.
- [ ] `tools/check.sh` passes.

## Playtest (for the human)

1. Start a battle: a soft dark vignette, faint scanlines and amber corner brackets frame the screen; the map is still fully readable and clickable.
2. FPS counter stays at 60 (HIGH, focused window).

## Player manual

none (no gameplay change).

## Out of scope

Any concrete HUD widget (TASK-077 … TASK-082); localisation changes (new strings come with the widgets).

## Implementation notes

_Filled in by the agent when done._
