class_name StaffMapContactPanel
extends FramedPanel
## Debug "Contact map" panel of the staff map (TASK-094b, F9, only with --debug), HUD v3 frame like
## the politics panel: the lines of StaffMapContactPreview (picked hexes, formations, cut size,
## deployment counts, build time, chunks) and the "Open battle map" button.

signal open_pressed

const WIDTH := 300

var _column: VBoxContainer
var _open: Button
var _lines: Array[Label] = []


func _init() -> void:
	super()
	name = "StaffMapContactPanel"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 12, 0, 12)
	padding = Vector2(12, 10)
	tab_text = "CONTACT MAP (DEBUG)"
	_column = VBoxContainer.new()
	_column.add_theme_constant_override(&"separation", 4)
	add_child(_column)
	_open = MenuStyle.button("Open battle map")
	_open.focus_mode = Control.FOCUS_NONE
	_open.pressed.connect(open_pressed.emit)
	_column.add_child(_open)
	hide()


## Shows `lines` (the first one muted as the instruction when nothing is built) and enables the
## button when the cut can be opened.
func show_lines(lines: PackedStringArray, can_open: bool) -> void:
	for label in _lines:
		label.queue_free()
	_lines.clear()
	for i in lines.size():
		var label := MenuStyle.label(lines[i], HudTheme.mono(500, 0), 11, UiPalette.HUD_TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(WIDTH - 24, 0)
		_column.add_child(label)
		_column.move_child(label, i)
		_lines.append(label)
	_open.disabled = not can_open
	reset_size()


func line_texts() -> PackedStringArray:
	var result := PackedStringArray()
	for label in _lines:
		result.append(label.text)
	return result


func open_enabled() -> bool:
	return not _open.disabled


## Presses the button as a click would (tests).
func press_open() -> void:
	if not _open.disabled:
		open_pressed.emit()
