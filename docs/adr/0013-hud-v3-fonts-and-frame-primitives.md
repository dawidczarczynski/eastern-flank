# ADR 0013: HUD v3 – Chakra Petch + JetBrains Mono, geometry-first frame primitives

- **Status**: accepted
- **Date**: 2026-10-23

## Context

The "tactical C2" HUD handoff (`docs/design/hud_v3/`, TASK-076 … 082) replaces the IBM Plex look: chamfered panels with a thin amber frame, header tabs, hatched bars and monospace data. The HTML reference uses CSS `clip-path`, gradients and Google Fonts (Chakra Petch for display and description text, JetBrains Mono for data). Godot has no `clip-path`; a `StyleBoxFlat` cannot cut corners, and its border would be cut off by a clipped fill anyway.

## Decision

- **Fonts**: Chakra Petch (static Regular / Medium / SemiBold / Bold) in `assets/fonts/chakra_petch/` and JetBrains Mono (one variable font, `wght` axis, weight chosen per use through `FontVariation.variation_opentype`) in `assets/fonts/jetbrains_mono/`, both SIL OFL with their `OFL.txt`, from the google/fonts repository. `HudTheme.display(weight, spacing)` and `HudTheme.mono(weight, spacing)` serve them (cached). IBM Plex stays in `assets/fonts/ibm_plex/` until the widgets of TASK-077 … 080 have moved over, then it is removed together with the old `HudTheme.font(file)` users.
- **Glyph coverage**: both families contain the Polish diacritics. Chakra Petch lacks `▸` and `↵`, JetBrains Mono lacks `↵`. Chakra Petch gets JetBrains Mono as a font fallback (covers `▸`); `↵` is a known gap (`HudTheme.GLYPH_GAPS`) and is drawn as a shape by the key-hint widgets. `tests/unit/test_hud_theme.gd` checks the glyphs.
- **Frames are polygons, not styleboxes**: `HudShapes` (pure geometry, unit-tested) produces chamfer, hex-badge, skewed-segment, trapezoid, header-tab, hatch and tick-ruler shapes; `FramedPanel` draws the README's "outer line + inner fill" as two polygons of the same shape (`_draw`, `draw_colored_polygon`), so the 1 px line follows the cut corners. Hatch stripes are clipped to their rectangle with `Geometry2D.intersect_polygons`. No backdrop blur (plain translucent fill).
- **Tokens** live only in `UiPalette` (new names `BG_APP`, `PANEL`, `PANEL_STRONG`, `LINE`, `AMBER`, `HUD_TEXT/MUTED/DESC`, `INK`, `DISABLED`, `NOTE_*`, …); the old constants stay until their users are migrated. Faction colours keep coming from `FactionDefinition` (the `.tres` values already equal the design's #5b93d6 / #d76a52).
- **Screen decoration** is one `ColorRect` with a `canvas_item` shader (`screen_decor.gdshader`): vignette, scanlines and corner brackets computed analytically per pixel, no textures, mouse ignored. It is the first child of the HUD root, above the 3D view and below the panels.

## Consequences

- (+) Pixel-exact shapes from the README with tests on the geometry; any chamfer per corner; one cheap full-screen pass for the decoration.
- (+) Fonts are OFL, shipped with licence texts; Polish text renders in every face.
- (-) Font sizes are integers in Godot, so the design's 10.5 px labels render at 11 px.
- (-) Until the migration finishes, two font families and two palettes coexist.
