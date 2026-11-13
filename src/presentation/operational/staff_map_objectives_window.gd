class_name StaffMapObjectivesWindow
extends StaffMapWindow
## The objectives window of the staff map (OBJECTIVES button, key O): a StaffMapWindow on the left
## dock listing what the operation is scored on – one info row per objective (points, who holds it
## now, lit green when the viewer's side does and red when the enemy does) and the round counter.
## Holds no rules: `show_objectives` rebuilds the rows from StaffMapObjectivesModel; it can be
## reopened at any time during the operation.

var _column: VBoxContainer
var _rows_box: VBoxContainer
var _round: Label


func _init() -> void:
	super(tr("OBJECTIVES").to_upper())
	name = "ObjectivesWindow"
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override(&"separation", 8)
	add_child(_column)
	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_box.add_theme_constant_override(&"separation", 6)
	_column.add_child(_rows_box)
	_round = MenuStyle.label("", HudTheme.mono(600, 1), 11, UiPalette.AMBER)
	_round.name = "Round"
	_column.add_child(_round)
	_column.add_child(StaffMapWindow.hint_line(tr("Esc or ✕ closes")))


## Rebuilds the rows for `viewer` from `state`.
func show_objectives(state: OperationalState, viewer: int) -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	for row in StaffMapObjectivesModel.rows(state, viewer):
		var line := StaffMapWindow.info_row("%s  +%d" % [row["label"], row["points"]])
		var value := StaffMapWindow.row_value(line)
		value.text = row["holder"]
		match row["status"]:
			StaffMapObjectivesModel.MINE:
				value.add_theme_color_override(&"font_color", UiPalette.HP_HIGH)
			StaffMapObjectivesModel.THEIRS:
				value.add_theme_color_override(&"font_color", UiPalette.HP_LOW)
		_rows_box.add_child(line)
	_round.text = StaffMapObjectivesModel.round_line(state)
	reset_size()


## The row nodes' count (tests).
func row_count() -> int:
	return _rows_box.get_child_count()
