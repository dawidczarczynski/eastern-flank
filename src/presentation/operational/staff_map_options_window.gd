class_name StaffMapOptionsWindow
extends StaffMapWindow
## Map options window of the staff map: a StaffMapWindow (left dock) with a toggle row per map
## layer (grid, names, borders, politics, flat view), each with its key cap, and the hint
## "Esc or ✕ closes". Holds no rules: a row emits `option_toggled(id)` and the owner acts;
## `set_active` lights the rows without emitting. Opened by the MAP OPTIONS button of the bottom
## bar; closed by it, by the X, by Esc and by a click on the map (the owner calls `close()`).

signal option_toggled(id: StringName)

var _rows: Dictionary = {}  # id -> ToggleRow
var _column: VBoxContainer


func _init() -> void:
	super(tr("MAP OPTIONS").to_upper())
	name = "MapOptionsWindow"
	_column = VBoxContainer.new()
	_column.name = "Rows"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override(&"separation", 4)
	add_child(_column)
	_column.add_child(StaffMapWindow.hint_line(tr("Esc or ✕ closes")))


## Adds a toggle row above the hint; `label` is the already translated name, `key_text` the key
## cap, `on_text` / `off_text` the state words (default ON / OFF).
func add_option(
	id: StringName, label: String, key_text: String, on_text := "", off_text := ""
) -> void:
	var row := StaffMapWindow.toggle_row(
		label.to_upper(),
		key_text,
		on_text if on_text != "" else tr("ON"),
		off_text if off_text != "" else tr("OFF")
	)
	row.name = String(id)
	row.pressed.connect(func() -> void: option_toggled.emit(id))
	_column.add_child(row)
	_column.move_child(row, _column.get_child_count() - 2)
	_rows[id] = row


func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_rows.keys())
	return result


func option(id: StringName) -> StaffMapWindow.ToggleRow:
	return _rows.get(id) as StaffMapWindow.ToggleRow


## Lights or dims a row without emitting.
func set_active(id: StringName, active: bool) -> void:
	var row := option(id)
	if row != null:
		row.set_on(active)
