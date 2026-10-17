class_name HudTheme
extends RefCounted
## Builds the HUD Theme in code (IBM Plex fonts, palette, dark translucent panels).

const FONT_DIR := "res://assets/fonts/ibm_plex/"

static var _fonts: Dictionary = {}  # file name -> FontFile
static var _spaced: Dictionary = {}  # "file:spacing" -> FontVariation


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


static func _label_variation(
	theme: Theme, name: StringName, file: String, size: int, color: Color, spacing: int
) -> void:
	theme.set_type_variation(name, &"Label")
	theme.set_font(&"font", name, _spaced_font(file, spacing))
	theme.set_font_size(&"font_size", name, size)
	theme.set_color(&"font_color", name, color)


static func _font(file: String) -> FontFile:
	if not _fonts.has(file):
		var font := load(FONT_DIR + file + ".ttf") as FontFile
		if font == null:
			push_error("HudTheme: missing font %s" % file)
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
