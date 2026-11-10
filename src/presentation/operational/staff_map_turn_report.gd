class_name StaffMapTurnReport
extends FramedPanel
## Turn report of the staff map (TASK-092e), HUD v3 panel like the formation panel: one row per
## ordered formation of the viewed side after its move – arrived / halted on contact / order
## dropped (with the reason in words) / still on the way – and the hex. Clicking a row emits
## `entry_chosen` (the staff map centres on the formation and selects it). Closable (close button or
## key R, reopened with R). No design reference exists for the report (TASK-095 has the
## after-action one), so it only reuses HUD v3 parts.

signal entry_chosen(formation_id: StringName, coord: Vector2i)
signal closed

const WIDTH := 300
const ROW_SIZE := 11

var _column: VBoxContainer
var _rows: Array[Button] = []
var _close_button: Button


func _init() -> void:
	super()
	name = "TurnReport"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	chamfers = Vector4(0, 12, 0, 12)
	padding = Vector2(14, 12)
	tab_text = " "
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override(&"separation", 4)
	add_child(_column)
	_close_button = MenuStyle.button("")
	_close_button.name = "Close"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.add_theme_font_size_override(&"font_size", ROW_SIZE)
	_close_button.pressed.connect(close)
	hide()


## Words for an entry kind (`reason` refines an interruption).
static func kind_text(kind: StringName, reason: StringName) -> String:
	if kind == StaffMapTurnMarks.INTERRUPTED:
		return TranslationServer.translate("REPORT_INTERRUPTED_" + String(reason).to_upper())
	return TranslationServer.translate("REPORT_" + String(kind).to_upper())


## The words of a report entry; a contact the border rule forbids names the country (TASK-116).
static func entry_text(entry: Dictionary, state: OperationalState) -> String:
	if entry["kind"] == StaffMapTurnMarks.HALTED and entry["reason"] == &"forbidden":
		return StaffMapBorders.forbidden_text(state, entry["country"])
	return kind_text(entry["kind"], entry["reason"])


## "HEX 12,5" style place text of a coordinate.
static func place_text(coord: Vector2i) -> String:
	return TranslationServer.translate("HEX %s") % ("%d,%d" % [coord.x, coord.y])


## Fills the rows from `entries` (StaffMapTurnMarks.report_of); formation names come from `state`.
## Does not change the visibility.
func show_report(state: OperationalState, entries: Array[Dictionary]) -> void:
	for row in _rows:
		row.queue_free()
	_rows.clear()
	tab_text = tr("TURN REPORT").to_upper()
	_close_button.text = ("%s [R]" % tr("CLOSE")).to_upper()
	if _close_button.get_parent() != null:
		_column.remove_child(_close_button)
	for entry in entries:
		var formation := state.get_formation(entry["id"])
		if formation == null:
			continue
		var text := (
			"%s  -  %s  -  %s"
			% [
				StaffMapFormations.designation(formation.display_name, formation.parent),
				entry_text(entry, state).to_upper(),
				place_text(entry["at"]),
			]
		)
		var row := MenuStyle.button(text)
		row.name = String(entry["id"])
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.add_theme_font_size_override(&"font_size", ROW_SIZE)
		row.add_theme_color_override(&"font_color", _kind_colour(entry["kind"]))
		row.pressed.connect(entry_chosen.emit.bind(entry["id"], entry["at"]))
		_column.add_child(row)
		_rows.append(row)
	if entries.is_empty():
		var empty := MenuStyle.label(
			tr("REPORT_EMPTY"), HudTheme.mono(500, 0), ROW_SIZE, UiPalette.HUD_MUTED
		)
		empty.name = "Empty"
		_column.add_child(empty)
	_column.add_child(_close_button)
	reset_size()


func entry_count() -> int:
	return _rows.size()


## Text of row `index`.
func row_text(index: int) -> String:
	return _rows[index].text


func click_row(index: int) -> void:
	_rows[index].pressed.emit()


func close() -> void:
	if visible:
		hide()
		closed.emit()


static func _kind_colour(kind: StringName) -> Color:
	match kind:
		StaffMapTurnMarks.HALTED, StaffMapTurnMarks.INTERRUPTED:
			return UiPalette.DISABLED
		StaffMapTurnMarks.ARRIVED:
			return UiPalette.AMBER
	return UiPalette.HUD_TEXT
