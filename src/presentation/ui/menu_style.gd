class_name MenuStyle
extends RefCounted
## HUD v3 look of the main menu and the unit catalog widgets (buttons, panels, labels), built in
## code from UiPalette and HudTheme. Texts are set by the caller (already translated).

const BUTTON_HEIGHT := 44.0
const BUTTON_FONT_SIZE := 15


## Flat box with a 1 px border.
static func box(fill: Color, border: Color, border_width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


## Chamfer-free HUD button: dark panel with an amber line, filled amber when pressed (toggles).
static func button(text: String, toggle := false) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.toggle_mode = toggle
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override(&"font", HudTheme.display(600, 2))
	b.add_theme_font_size_override(&"font_size", BUTTON_FONT_SIZE)
	b.add_theme_color_override(&"font_color", UiPalette.HUD_TEXT)
	b.add_theme_color_override(&"font_hover_color", UiPalette.AMBER)
	b.add_theme_color_override(&"font_focus_color", UiPalette.AMBER)
	b.add_theme_color_override(&"font_pressed_color", UiPalette.INK)
	b.add_theme_color_override(&"font_hover_pressed_color", UiPalette.INK)
	b.add_theme_color_override(&"font_disabled_color", UiPalette.HUD_MUTED)
	var line := Color(UiPalette.AMBER, 0.34)
	b.add_theme_stylebox_override(&"normal", box(UiPalette.PANEL, line))
	b.add_theme_stylebox_override(
		&"hover", box(Color(UiPalette.AMBER, 0.12), Color(UiPalette.AMBER, 0.9))
	)
	b.add_theme_stylebox_override(&"pressed", box(UiPalette.AMBER, UiPalette.AMBER))
	b.add_theme_stylebox_override(
		&"hover_pressed", box(Color(UiPalette.AMBER, 0.9), UiPalette.AMBER)
	)
	b.add_theme_stylebox_override(&"focus", box(Color(0, 0, 0, 0), UiPalette.AMBER, 2))
	b.add_theme_stylebox_override(
		&"disabled", box(Color(UiPalette.PANEL, 0.5), Color(UiPalette.HUD_MUTED, 0.25))
	)
	return b


## Dark translucent panel with an amber border.
static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override(&"panel", box(UiPalette.PANEL_STRONG, UiPalette.LINE))
	return p


## Label with the given font, size and colour; the text is set verbatim (translated by the caller).
static func label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Small amber mono caption ("ANIMATIONS").
static func caption(text: String) -> Label:
	return label(text.to_upper(), HudTheme.mono(600, 3), 11, UiPalette.AMBER)
