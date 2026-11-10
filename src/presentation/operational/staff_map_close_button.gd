class_name StaffMapCloseButton
extends Button
## The X of a strike window (TASK-097b): a flat 24 px square with the glyph ✕ (mono 700 13) at the
## top-right of a frame, 18 px from the right edge and 1 px from the top (the chamfer stays clear).
## `attach` puts it on a FramedPanel without the panel's margin layout stretching it: the button
## lives under a Node2D holder (containers only lay out Controls) and follows the panel's size.

const SIZE := 24.0
const RIGHT := 18.0
const TOP := 1.0


func _init() -> void:
	name = "Close"
	text = "✕"
	flat = true
	focus_mode = Control.FOCUS_NONE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_override(&"font", HudTheme.mono(700, 0))
	add_theme_font_size_override(&"font_size", 13)
	add_theme_color_override(&"font_color", UiPalette.HUD_MUTED)
	add_theme_color_override(&"font_hover_color", UiPalette.AMBER)
	add_theme_color_override(&"font_pressed_color", UiPalette.AMBER)


## Creates the button, adds it to `panel` and keeps it at the top-right corner.
static func attach(panel: FramedPanel) -> StaffMapCloseButton:
	var holder := Node2D.new()
	holder.name = "CloseHolder"
	panel.add_child(holder)
	var button := StaffMapCloseButton.new()
	holder.add_child(button)
	panel.resized.connect(func() -> void: button.place(panel.size))
	panel.tab_right_inset = SIZE + 6.0
	button.place(panel.size)
	return button


func place(panel_size: Vector2) -> void:
	position = Vector2(panel_size.x - RIGHT - SIZE, TOP)
