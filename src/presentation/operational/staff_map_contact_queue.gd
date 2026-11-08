class_name StaffMapContactQueue
extends FramedPanel
## Contact queue of the staff map (TASK-094a, mockup 03 "CONTACTS"): at the left edge one row per
## pending battle – the place and NOW / NEXT / LATER; the active one is marked with an arrow.

const WIDTH := 200.0
const ROW_SIZE := 11

var _column: VBoxContainer
var _rows: Array[Label] = []


func _init() -> void:
	super()
	name = "ContactQueue"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 12, 0, 12)
	padding = Vector2(12, 10)
	tab_color = StaffMapContactNotice.ALERT
	line_color = Color(StaffMapContactNotice.ALERT, 0.45)
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override(&"separation", 4)
	add_child(_column)
	hide()


## One row per hex in `places` (axial coordinates of the defenders' hexes, first = active).
func show_places(places: Array[Vector2i]) -> void:
	for row in _rows:
		_column.remove_child(row)
		row.queue_free()
	_rows.clear()
	tab_text = tr("CONTACTS").to_upper()
	tab_right_text = str(places.size())
	for i in places.size():
		var key := "CONTACT_NOW" if i == 0 else ("CONTACT_NEXT" if i == 1 else "CONTACT_LATER")
		var text := (
			"%s HEX %s  -  %s"
			% ["▸" if i == 0 else " ", StaffMapContactNotice.hex_text(places[i]), tr(key)]
		)
		var colour := UiPalette.HUD_TEXT if i == 0 else UiPalette.HUD_MUTED
		var row := MenuStyle.label(text.to_upper(), HudTheme.mono(500, 0), ROW_SIZE, colour)
		_column.add_child(row)
		_rows.append(row)
	show()
	reset_size()


func row_count() -> int:
	return _rows.size()


func row_text(index: int) -> String:
	return _rows[index].text
