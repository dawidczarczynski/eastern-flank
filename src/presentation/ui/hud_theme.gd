class_name HudTheme
extends RefCounted
## Builds the HUD Theme in code (palette, dark translucent panels) and serves the HUD fonts:
## IBM Plex for the widgets of the old look, Chakra Petch (display / description body) and
## JetBrains Mono (data) for HUD v3 (ADR 0013). The old widgets move over in TASK-077 ... 080.

const FONT_DIR := "res://assets/fonts/ibm_plex/"
const DISPLAY_DIR := "res://assets/fonts/chakra_petch/"
const MONO_FILE := "res://assets/fonts/jetbrains_mono/JetBrainsMono.ttf"
## Chakra Petch weights shipped as static files.
const DISPLAY_WEIGHTS: Array[int] = [400, 500, 600, 700]
const _DISPLAY_NAMES := {400: "Regular", 500: "Medium", 600: "SemiBold", 700: "Bold"}
## Characters of the HUD symbol set that none of the v3 fonts contain: draw them as shapes.
## (Chakra Petch also lacks "▸"; it falls back to JetBrains Mono for it.)
const GLYPH_GAPS: Array[String] = ["↵"]

static var _fonts: Dictionary = {}  # file name -> FontFile
static var _spaced: Dictionary = {}  # "file:spacing" -> FontVariation
static var _mono: Dictionary = {}  # "weight:spacing" -> FontVariation


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = _font("IBMPlexSansCondensed-Regular")
	theme.default_font_size = 14
	theme.set_color(&"font_color", &"Label", UiPalette.TEXT)

	var panel := StyleBoxFlat.new()
	panel.bg_color = UiPalette.PANEL_BG
	panel.set_border_width_all(1)
	panel.border_color = UiPalette.PANEL_BORDER
	panel.set_corner_radius_all(0)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 9
	panel.content_margin_bottom = 9
	theme.set_stylebox(&"panel", &"PanelContainer", panel)

	_label_variation(theme, &"TitleLabel", "IBMPlexSansCondensed-SemiBold", 20, UiPalette.TEXT, 0)
	_label_variation(theme, &"CaptionLabel", "IBMPlexMono-Medium", 10, UiPalette.TEXT_SECONDARY, 2)
	_label_variation(theme, &"ValueLabel", "IBMPlexMono-Medium", 13, UiPalette.TEXT, 0)
	_label_variation(theme, &"UnitTagLabel", "IBMPlexMono-SemiBold", 9, UiPalette.TEXT, 1)
	_label_variation(theme, &"MonoLabel", "IBMPlexMono-Regular", 11, UiPalette.TEXT_MUTED, 0)

	var button := StyleBoxFlat.new()
	button.set_corner_radius_all(0)
	button.bg_color = Color(0, 0, 0, 0)
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		theme.set_stylebox(state, &"Button", button)
	theme.set_font(&"font", &"Button", _font("IBMPlexSansCondensed-Bold"))
	theme.set_font_size(&"font_size", &"Button", 15)
	return theme


## Public font access for code-built HUD widgets; `spacing` is extra glyph spacing in px.
static func font(file: String, spacing: int = 0) -> Font:
	return _spaced_font(file, spacing)


## Chakra Petch (HUD v3 display face and description body); `weight` is one of
## DISPLAY_WEIGHTS (400 body, 600/700 display), `spacing` extra glyph spacing in px.
static func display(weight: int, spacing: int = 0) -> Font:
	var name: String = _DISPLAY_NAMES.get(weight, "Regular")
	return _spaced_font("ChakraPetch-" + name, spacing)


## JetBrains Mono (HUD v3 data face), a variable font: `weight` 100..800 sets the wght axis.
static func mono(weight: int = 400, spacing: int = 0) -> Font:
	var key := "%d:%d" % [weight, spacing]
	if not _mono.has(key):
		var base := load(MONO_FILE) as FontFile
		if base == null:
			push_error("HudTheme: missing font %s" % MONO_FILE)
		var variation := FontVariation.new()
		variation.base_font = base
		variation.variation_opentype = {
			TextServerManager.get_primary_interface().name_to_tag("wght"): weight
		}
		variation.spacing_glyph = spacing
		_mono[key] = variation
	return _mono[key]


## True when `font` (or one of its fallback fonts) has a glyph for the character `ch`.
static func has_glyph(font: Font, ch: String) -> bool:
	var code := ch.unicode_at(0)
	if font is FontVariation:
		return has_glyph((font as FontVariation).base_font, ch)
	if font.has_char(code):
		return true
	for fallback in font.fallbacks:
		if has_glyph(fallback, ch):
			return true
	return false


static func _label_variation(
	theme: Theme, name: StringName, file: String, size: int, color: Color, spacing: int
) -> void:
	theme.set_type_variation(name, &"Label")
	theme.set_font(&"font", name, _spaced_font(file, spacing))
	theme.set_font_size(&"font_size", name, size)
	theme.set_color(&"font_color", name, color)


static func _font(file: String) -> FontFile:
	if not _fonts.has(file):
		var dir := DISPLAY_DIR if file.begins_with("ChakraPetch") else FONT_DIR
		var font := load(dir + file + ".ttf") as FontFile
		if font == null:
			push_error("HudTheme: missing font %s" % file)
		elif file.begins_with("ChakraPetch"):
			# Symbols such as "▸" are not in Chakra Petch: take them from the data face.
			font.fallbacks = [mono(400).base_font]
		_fonts[file] = font
	return _fonts[file]


static func _spaced_font(file: String, spacing: int) -> Font:
	if spacing == 0:
		return _font(file)
	var key := "%s:%d" % [file, spacing]
	if not _spaced.has(key):
		var variation := FontVariation.new()
		variation.base_font = _font(file)
		variation.spacing_glyph = spacing
		_spaced[key] = variation
	return _spaced[key]
