class_name StaffMapMenuButton
extends Button
## The hamburger of the staff map (top-left corner, where the Back button used to be): a flat
## square with three bars that open the operation menu (Save, Exit operation). The bars are drawn,
## not a glyph, so they stay crisp at any scale; they light amber on hover and while the menu is
## open (`set_lit`). Same frame as the other HUD buttons (MenuStyle.button).

const SIZE := 44.0
const BAR_WIDTH := 20.0
const BAR_HEIGHT := 2.0
const BAR_GAP := 6.0

var _lit := false


func _init() -> void:
	name = "MenuButton"
	var base := MenuStyle.button("")
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
		add_theme_stylebox_override(style_name, base.get_theme_stylebox(style_name))
	base.free()
	focus_mode = Control.FOCUS_NONE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	position = Vector2(16, 16)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = tr("MENU")


## Lights the bars while the menu window is open.
func set_lit(lit: bool) -> void:
	_lit = lit
	queue_redraw()


func is_lit() -> bool:
	return _lit


func _draw() -> void:
	var colour := UiPalette.AMBER if _lit or is_hovered() else UiPalette.HUD_TEXT
	var left := (size.x - BAR_WIDTH) / 2.0
	var top := (size.y - (3.0 * BAR_HEIGHT + 2.0 * BAR_GAP)) / 2.0
	for i in 3:
		draw_rect(Rect2(left, top + i * (BAR_HEIGHT + BAR_GAP), BAR_WIDTH, BAR_HEIGHT), colour)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		queue_redraw()
