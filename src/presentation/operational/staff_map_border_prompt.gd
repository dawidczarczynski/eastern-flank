class_name StaffMapBorderPrompt
extends Control
## One-key confirmation before an order that causes border incidents (TASK-116, design
## docs/design/operational_map/border_warnings.html, confirmation variant A): the map dims 28 %
## 360 px chamfered plate above the hint line lists one row per incident (chip + text) with the
## keys "Enter Confirm" / "Esc Cancel". The edge turns ui.alert when an incident ends the
## operation. Holds the pending order; StaffMap executes it on Enter (the same IssueOrderCommand
## path) and drops it on Esc.

const WIDTH := 360.0
const DIM := 0.28
const CHAMFER := 9.0

var _pending := {}  # {formation_id, destination, posture} while open
var _palette: StaffMapPalette
var _plate: FramedPanel
var _header: Label
var _rows: VBoxContainer
var _row_texts: PackedStringArray = []
var _ends := false


## `bottom_offset`: distance (px) from the screen bottom to the plate's lower edge.
func _init(palette: StaffMapPalette = null, bottom_offset := 140.0) -> void:
	_palette = palette if palette != null else StaffMapPalette.new()
	name = "BorderPrompt"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_plate = FramedPanel.new()
	_plate.chamfers = Vector4(0, CHAMFER, 0, CHAMFER)
	_plate.fill = _palette.map_void
	_plate.padding = Vector2(12, 9)
	_plate.anchor_left = 0.5
	_plate.anchor_right = 0.5
	_plate.anchor_top = 1.0
	_plate.anchor_bottom = 1.0
	_plate.offset_left = -WIDTH / 2.0
	_plate.offset_right = WIDTH / 2.0
	_plate.offset_bottom = -bottom_offset
	_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_plate)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	_plate.add_child(column)
	_header = Label.new()
	_header.add_theme_font_override(&"font", HudTheme.display(700, 2))
	_header.add_theme_font_size_override(&"font_size", 11)
	column.add_child(_header)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 4)
	column.add_child(_rows)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override(&"separation", 8)
	keys.add_child(_key("↵", "Confirm", true))
	keys.add_child(_key("Esc", "Cancel", false))
	column.add_child(keys)
	hide()


## Opens the prompt for the order and the warnings (StaffMapBorders.warnings) of its route.
func ask(
	formation_id: StringName,
	destination: Vector2i,
	posture: StringName,
	warnings: Array[Dictionary]
) -> void:
	_pending = {"formation_id": formation_id, "destination": destination, "posture": posture}
	_ends = false
	_row_texts = PackedStringArray()
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for warning in warnings:
		var ends: bool = warning["ends"]
		_ends = _ends or ends
		_row_texts.append(warning["text"])
		_rows.add_child(_row(warning["chip"], warning["text"], ends))
	var accent := _palette.ui_alert if _ends else _palette.ui_amber
	var key := (
		"CONFIRM ORDER · %d INCIDENTS" if warnings.size() != 1 else "CONFIRM ORDER · 1 INCIDENT"
	)
	var header := TranslationServer.translate(key)
	_header.text = header % warnings.size() if "%d" in header else header
	_header.add_theme_color_override(&"font_color", accent)
	_plate.line_color = accent
	show()
	queue_redraw()


func is_open() -> bool:
	return not _pending.is_empty()


## The order waiting for the answer ({} when closed).
func pending() -> Dictionary:
	return _pending


## Closes the prompt and returns the pending order ({} when none).
func take() -> Dictionary:
	var order := _pending
	_pending = {}
	hide()
	return order


## The incident texts shown (tests).
func row_texts() -> PackedStringArray:
	return _row_texts


func header_text() -> String:
	return _header.text


## True when the edge is drawn in ui.alert (an incident ends the operation).
func is_alert() -> bool:
	return _ends


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, DIM))


func _row(chip: String, text: String, ends: bool) -> Control:
	var accent := _palette.ui_alert if ends else _palette.ui_amber
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var chip_label := Label.new()
	chip_label.text = chip
	chip_label.custom_minimum_size = Vector2(34, 0)
	chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	chip_label.add_theme_font_override(&"font", HudTheme.mono(700))
	chip_label.add_theme_font_size_override(&"font_size", 10)
	chip_label.add_theme_color_override(&"font_color", _palette.map_void)
	chip_label.add_theme_stylebox_override(&"normal", _box(accent, accent, 2))
	row.add_child(chip_label)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override(&"font", HudTheme.display(700))
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", _palette.ui_text)
	row.add_child(label)
	return row


## "↵ Confirm" (filled amber, primary) or "Esc Cancel" (outline).
func _key(glyph: String, word: String, primary: bool) -> Control:
	var label := Label.new()
	label.text = "%s %s" % [glyph, TranslationServer.translate(word)]
	label.add_theme_font_override(&"font", HudTheme.display(700))
	label.add_theme_font_size_override(&"font_size", 12)
	var amber := _palette.ui_amber
	label.add_theme_color_override(
		&"font_color", _palette.map_void if primary else _palette.ui_text
	)
	label.add_theme_stylebox_override(
		&"normal",
		_box(amber if primary else Color(0, 0, 0, 0), amber if primary else _palette.ui_muted, 5)
	)
	return label


static func _box(fill: Color, edge: Color, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.content_margin_left = pad + 3
	box.content_margin_right = pad + 3
	box.content_margin_top = pad - 3
	box.content_margin_bottom = pad - 3
	return box
