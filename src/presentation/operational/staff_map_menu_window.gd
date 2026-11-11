class_name StaffMapMenuWindow
extends StaffMapWindow
## The operation menu of the staff map (opened by the hamburger in the top-left corner): a
## StaffMapWindow centred on the screen with two rows, SAVE (F5) and EXIT OPERATION. Holds no rules:
## the rows emit `save_pressed` / `exit_pressed` and the owner acts. Closed by the X, Esc, the
## hamburger and a click on the map.

signal save_pressed
signal exit_pressed

var _save: Button
var _exit: Button


func _init() -> void:
	super(tr("MENU").to_upper())
	name = "MenuWindow"
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 8)
	add_child(column)
	_save = _row(tr("SAVE"), "F5")
	_save.name = "Save"
	_save.tooltip_text = tr("TIP_SAVE_OPERATION")
	_save.pressed.connect(func() -> void: save_pressed.emit())
	column.add_child(_save)
	_exit = _row(tr("EXIT OPERATION"), "")
	_exit.name = "Exit"
	_exit.pressed.connect(func() -> void: exit_pressed.emit())
	column.add_child(_exit)
	column.add_child(StaffMapWindow.hint_line(tr("Esc or ✕ closes")))


## Shows the menu centred in a viewport of size `viewport` (not on the left dock).
func open_centered(viewport: Vector2) -> void:
	show()
	reset_size()
	position = ((viewport - size) / 2.0).floor()


func save_button() -> Button:
	return _save


func exit_button() -> Button:
	return _exit


## A menu row: the same button as the rest of the HUD, label left, key cap right.
func _row(label: String, key_text: String) -> Button:
	var b := MenuStyle.button(label)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, StaffMapWindow.ROW_HEIGHT + 4.0)
	if key_text != "":
		var cap := MenuStyle.label(key_text, HudTheme.mono(600, 0), 11, UiPalette.HUD_MUTED)
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		cap.offset_right = -10
		cap.offset_left = -10 - 28
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_child(cap)
	return b
