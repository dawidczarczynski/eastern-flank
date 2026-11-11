class_name StaffMapLadderWindow
extends Control
## Escalation ladder window of the staff map (TASK-143, docs/design/operational_map/
## escalation_ladder_window.html variant B): a 1320 x 660 plate (at 1440 x 900) over the dimmed
## map. A horizontal axis with the seven levels (big number, name, node), under it a matrix of
## what may be struck per level (tick, "tick NEW" where it is unlocked, dashed dash where not),
## trigger chips (sanctuary, allies, cap, end), a collapse strip per side and a tooltip with the
## condition of the hovered / focused level (left / right keys). Closes with the X button, Esc
## and a click on the dimmed map; the map below takes no input. Read-only: everything comes from
## `state.ladder` and StaffMapEscalation; the plate is drawn from a model built on open and on a
## state change (never per frame).

signal close_requested

const DESIGN_SIZE := Vector2(1440, 900)
const PLATE_SIZE := Vector2(1320, 660)
const FADE_SECONDS := 0.15
const LABEL_WIDTH := 150.0
const COL_W := 160.0
const AXIS_Y := 170.0
const ROW_Y := 210.0
const ROW_H := 34.0
const FOOT_Y := 500.0
const NODE_HIT := 24.0
const TIP_SIZE := Vector2(260, 84)
const PLATE_EDGE := Color("#3a3f33")
const ABOVE_NUMBER := Color("#5a6153")
const CLASS_ORDER: Array[StringName] = [&"formation", &"air_defence", &"depot", &"airfield", &"c2"]
const GATE_DASH := 6.0

var _state: OperationalState
var _palette: StaffMapPalette
var _plate := Control.new()
var _close := StaffMapCloseButton.new()
var _columns: Array[Dictionary] = []
var _strips: Array[Dictionary] = []
var _hover := -1
var _focus := -1
var _fade: Tween


func _init() -> void:
	name = "LadderWindow"
	mouse_filter = Control.MOUSE_FILTER_STOP  # the dimmed map takes no input
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UiPalette.SCRIM_SCREEN
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	_plate.name = "Plate"
	_plate.mouse_filter = Control.MOUSE_FILTER_STOP
	_plate.custom_minimum_size = PLATE_SIZE
	_plate.size = PLATE_SIZE
	_plate.draw.connect(_draw_plate)
	_plate.gui_input.connect(_on_plate_input)
	_plate.mouse_exited.connect(_set_hover.bind(-1))
	add_child(_plate)
	_close.place(PLATE_SIZE)
	_close.pressed.connect(close_requested.emit)
	_plate.add_child(_close)
	resized.connect(_layout)
	hide()


## Builds the model from `state` and shows the window (fade-in).
func show_state(state: OperationalState, palette: StaffMapPalette) -> void:
	_state = state
	_palette = palette
	_hover = -1
	_focus = -1
	_close.tooltip_text = tr("CLOSE")
	_build_model()
	_layout()
	show()
	_plate.queue_redraw()
	if _fade != null:
		_fade.kill()
	modulate.a = 0.0
	if is_inside_tree():
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0, FADE_SECONDS)
	else:
		modulate.a = 1.0


## Ends the fade-in at once (screenshots, where the tree does not process).
func finish_fade() -> void:
	if _fade != null:
		_fade.kill()
	modulate.a = 1.0


## Rebuilds in place when open (the state changed).
func refresh() -> void:
	if visible and _state != null:
		_build_model()
		_plate.queue_redraw()


func close() -> bool:
	var was_open := visible
	hide()
	return was_open


## Keys while open (the map takes none): Esc closes, left / right move the focus ring across
## the levels. Always consumes the key; false when closed.
func handle_key(keycode: Key) -> bool:
	if not visible:
		return false
	match keycode:
		KEY_ESCAPE:
			close_requested.emit()
		KEY_LEFT:
			move_focus(-1)
		KEY_RIGHT:
			move_focus(1)
	return true


## Moves the focus ring by `step` levels (starts at the current level).
func move_focus(step: int) -> void:
	if _columns.is_empty():
		return
	var from := _state.escalation_level if _focus < 0 else _focus
	_focus = clampi(from + step, 0, _columns.size() - 1)
	_plate.queue_redraw()


func focused_level() -> int:
	return _focus


## A click on the dimmed map (outside the plate) closes the window.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not Rect2(_plate.position, PLATE_SIZE * _plate.scale).has_point(button.position):
		close_requested.emit()


# --- model (tests read it) ---


## Per level (0 .. top): {level, name, colour, kind (&"reached" / &"current" / &"above" / &"end"),
## cells (texts per strike class), new (bool per class), triggers (array of {chip, text, end})}.
func columns() -> Array[Dictionary]:
	return _columns


## The matrix cell texts of strike class row `row`, one per level: "✓", "✓ NEW", "—" or "" (top).
func row_texts(row: int) -> PackedStringArray:
	var texts := PackedStringArray()
	for column in _columns:
		texts.append(String(column["cells"][row]))
	return texts


## The chip labels of level `level` ("SANCTUARY OPENS", ...), empty for none.
func trigger_chips(level: int) -> PackedStringArray:
	var chips := PackedStringArray()
	for trigger in _columns[level]["triggers"]:
		chips.append(String(trigger["chip"]))
	return chips


## Collapse strips as shown per player: {name, strength, readiness, collapse, text}.
func strips() -> Array[Dictionary]:
	return _strips


func sub_text() -> String:
	return _sub_text()


## The tooltip {title, text} of `level` (hover / focus).
func tip_of(level: int) -> Dictionary:
	var top := _state.ladder.top()
	if level == top:
		return {
			"title": tr("ESC_WIN_REQUIRES"),
			"text": tr("level %d · %s in collapse · %s's own decision") % _requirement_args(),
		}
	var lines: Array[String] = [
		"%s: %s" % [tr("ESC_ROE"), StaffMapEscalation.roe_text(_state, level)]
	]
	for trigger in _columns[level]["triggers"]:
		lines.append(String(trigger["text"]))
	return {
		"title": "%d · %s" % [level, StaffMapEscalation.level_name(_state, level)],
		"text": "\n".join(lines),
	}


func tip_level() -> int:
	return _hover if _hover >= 0 else _focus


func _build_model() -> void:
	var ladder := _state.ladder
	var top := ladder.top()
	var current := _state.escalation_level
	_columns.clear()
	for level in top + 1:
		var allowed := ladder.strike_classes_at(level)
		var before: Array[StringName] = []
		if level > 0:
			before = ladder.strike_classes_at(level - 1)
		var cells: Array[String] = []
		var fresh: Array[bool] = []
		for strike_class in CLASS_ORDER:
			var ok := level < top and allowed.has(strike_class)
			var is_new := ok and not before.has(strike_class)
			fresh.append(is_new)
			if level == top:
				cells.append("")
			elif ok:
				cells.append("✓ " + tr("ESC_WIN_NEW").to_upper() if is_new else "✓")
			else:
				cells.append("—")
		var kind := &"reached"
		if level == current:
			kind = &"current"
		elif level > current:
			kind = &"end" if level == top else &"above"
		(
			_columns
			. append(
				{
					"level": level,
					"name": StaffMapEscalation.level_name(_state, level),
					"colour": StaffMapEscalation.level_colour(level, top, _palette),
					"kind": kind,
					"cells": cells,
					"new": fresh,
					"triggers": _triggers_of(level),
				}
			)
		)
	_strips.clear()
	for player in _state.player_sides.size():
		var strip := StaffMapEscalation.collapse_strip(_state, player)
		_strips.append(strip)


func _triggers_of(level: int) -> Array[Dictionary]:
	var ladder := _state.ladder
	var out: Array[Dictionary] = []
	if level == ladder.sanctuary_open_level:
		out.append(_trigger("ESC_CHIP_SANCTUARY", "ESC_MARK_SANCTUARY", false))
	if level == ladder.allies_join_level:
		out.append(_trigger("ESC_CHIP_ALLIES", "ESC_MARK_ALLIES", false))
	if level == ladder.cap():
		out.append(_trigger("ESC_CHIP_CAP", "ESC_MARK_CAP", false, "▲ "))
	if level == ladder.top():
		out.append(_trigger("ESC_CHIP_END", "ESC_MARK_END", true, "✕ "))
	return out


func _trigger(chip_key: String, text_key: String, end: bool, mark := "") -> Dictionary:
	return {"chip": mark + tr(chip_key).to_upper(), "text": tr(text_key), "end": end}


func _sub_text() -> String:
	var args := [_state.escalation_level, _state.ladder.top(), _state.ladder.cap()]
	return tr("Shared by both sides · level %d of %d · ordinary play stops at %d") % args


func _requirement_args() -> Array:
	var side := _nuclear_side()
	return [_state.ladder.cap(), side, side]


func _power_index() -> int:
	for player in _state.may_use_nuclear.size():
		if _state.may_use_nuclear[player]:
			return player
	return _state.player_sides.size() - 1


func _nuclear_side() -> String:
	return StaffMapTurnBar.side_name(_state, _power_index())


# --- layout and input ---


## The plate scales with the viewport (design 1440 x 900) and is centred on it.
func _layout() -> void:
	var view := size if size.x > 1.0 and size.y > 1.0 else DESIGN_SIZE
	var factor := minf(view.x / DESIGN_SIZE.x, view.y / DESIGN_SIZE.y)
	_plate.scale = Vector2(factor, factor)
	_plate.position = (view - PLATE_SIZE * factor) * 0.5


func _on_plate_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_set_hover(_node_at(motion.position))


func _node_at(point: Vector2) -> int:
	if _columns.is_empty() or absf(point.y - AXIS_Y) > NODE_HIT:
		return -1
	for column in _columns:
		var level: int = column["level"]
		if absf(point.x - _node_x(level)) <= NODE_HIT:
			return level
	return -1


func _set_hover(level: int) -> void:
	if level != _hover:
		_hover = level
		_plate.queue_redraw()


static func _node_x(level: int) -> float:
	return LABEL_WIDTH + COL_W * level + COL_W / 2.0


# --- drawing ---


func _draw_plate() -> void:
	if _state == null or _columns.is_empty():
		return
	var plate := _plate
	var cut := Vector4(0, 12, 0, 12)
	plate.draw_colored_polygon(
		HudShapes.chamfer(PLATE_SIZE, cut.x, cut.y, cut.z, cut.w), PLATE_EDGE
	)
	plate.draw_colored_polygon(
		HudShapes.chamfer_inset(PLATE_SIZE, 1.0, cut.x, cut.y, cut.z, cut.w), UiPalette.PANEL_STRONG
	)
	_draw_header()
	for column in _columns:
		_draw_column(column)
	_draw_axis()
	for column in _columns:
		_draw_node(column)
	_draw_row_labels()
	plate.draw_rect(Rect2(0, FOOT_Y, PLATE_SIZE.x, 1), UiPalette.LINE)
	for player in _strips.size():
		_draw_strip(_strips[player], player)
	_text(
		Vector2(34, 610),
		tr("ESC_WIN_HINT"),
		HudTheme.mono(500, 0),
		11,
		UiPalette.HUD_MUTED,
		PLATE_SIZE.x - 68.0
	)
	var tip := tip_level()
	if tip >= 0:
		_draw_tip(tip)


func _draw_header() -> void:
	var current := _state.escalation_level
	var colour := StaffMapEscalation.level_colour(current, _state.ladder.top(), _palette)
	var font := HudTheme.display(700, 2)
	var title := tr("ESC_CARD_TITLE").to_upper()
	var tab_w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 44.0
	_plate.draw_colored_polygon(
		PackedVector2Array(
			[Vector2(1, 1), Vector2(tab_w, 1), Vector2(tab_w - 12, 31), Vector2(1, 31)]
		),
		colour
	)
	_text(Vector2(16, 8), title, font, 12, UiPalette.INK)
	_text(
		Vector2(maxf(200.0, tab_w + 14.0), 8),
		_sub_text(),
		HudTheme.mono(400, 0),
		12,
		UiPalette.HUD_MUTED,
		PLATE_SIZE.x - 300.0
	)
	_plate.draw_rect(Rect2(0, 34, PLATE_SIZE.x, 1), UiPalette.LINE)


func _draw_column(column: Dictionary) -> void:
	var level: int = column["level"]
	var kind: StringName = column["kind"]
	var colour: Color = column["colour"]
	var left := LABEL_WIDTH + COL_W * level
	var current := kind == &"current"
	if current:
		var frame := Rect2(left + 3, 44, COL_W - 6, 440)
		_plate.draw_rect(frame, Color(UiPalette.AMBER, 0.07))
		_plate.draw_rect(frame, UiPalette.AMBER, false, 1.0)
	var beyond := kind == &"above" or kind == &"end"
	_text(
		Vector2(left, 50),
		str(level),
		HudTheme.display(700, 0),
		44,
		ABOVE_NUMBER if beyond else colour,
		COL_W,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	var name_font := HudTheme.display(700, 1)
	var title := String(column["name"]).to_upper()
	_text(
		Vector2(left + 6, 100),
		title,
		name_font,
		_fit(title, name_font, 13, COL_W - 12.0),
		UiPalette.HUD_DESC if beyond else UiPalette.HUD_TEXT,
		COL_W - 12.0,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	if current:
		_chip(
			Vector2(left + COL_W / 2.0, 124),
			"◆ " + tr("ESC_WIN_NOW").to_upper(),
			UiPalette.AMBER,
			true
		)
	for row in CLASS_ORDER.size():
		_draw_cell(column, row, left)
	var y := ROW_Y + 5.0 * ROW_H + 14.0
	for trigger in column["triggers"]:
		var end: bool = trigger["end"]
		var tint := _palette.ui_alert if end else UiPalette.AMBER
		_chip(Vector2(left + COL_W / 2.0, y), trigger["chip"], tint, end)
		var lines := _text(
			Vector2(left + 6, y + 24),
			trigger["text"],
			HudTheme.font("IBMPlexSansCondensed-Medium"),
			12,
			_palette.ui_alert if end else UiPalette.HUD_DESC,
			COL_W - 12.0,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		y += 24.0 + lines + 8.0


func _draw_cell(column: Dictionary, row: int, left: float) -> void:
	var text: String = column["cells"][row]
	var rect := Rect2(left + 20, ROW_Y + row * ROW_H, COL_W - 40, 26)
	var colour: Color = column["colour"]
	var fresh: bool = column["new"][row]
	if text == "":
		return
	if text == "—":
		_dashed_rect(rect, UiPalette.CARD_EDGE)
		_text(
			rect.position + Vector2(0, 6),
			text,
			HudTheme.mono(700, 0),
			11,
			StaffMapDecisionParts.MUTED_EDGE,
			rect.size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		return
	_plate.draw_rect(rect, Color(colour, 0.133))
	_plate.draw_rect(rect, UiPalette.AMBER if fresh else PLATE_EDGE, false, 1.0)
	var ink := UiPalette.AMBER if fresh else UiPalette.HUD_TEXT
	_text(
		rect.position + Vector2(0, 3),
		text,
		HudTheme.mono(700, 0),
		17 if not fresh else 14,
		ink,
		rect.size.x,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_axis() -> void:
	var current := _state.escalation_level
	var top := _state.ladder.top()
	var x0 := _node_x(0)
	var calm := StaffMapEscalation.CALM_COLOUR
	var faint := Rect2(x0, AXIS_Y - 1, COL_W * (top - 1), 3)
	_plate.draw_rect(faint, Color(calm.lerp(_columns[top]["colour"], 0.5), 0.3))
	_plate.draw_rect(
		Rect2(x0, AXIS_Y - 1, COL_W * current, 3), calm.lerp(_columns[current]["colour"], 0.5)
	)
	var gate_x := _node_x(top - 1)
	var x := gate_x
	while x < _node_x(top):
		_plate.draw_rect(
			Rect2(x, AXIS_Y - 1, minf(GATE_DASH, _node_x(top) - x), 3), _palette.ui_alert
		)
		x += GATE_DASH * 2.0


func _draw_node(column: Dictionary) -> void:
	var level: int = column["level"]
	var colour: Color = column["colour"]
	var centre := Vector2(_node_x(level), AXIS_Y)
	match column["kind"]:
		&"current":
			var half := 15.0
			var diamond := _diamond(centre, half)
			_plate.draw_colored_polygon(diamond, colour)
			var ring := _diamond(centre, half + 5.0)
			ring.append(ring[0])
			_plate.draw_polyline(ring, UiPalette.HUD_TEXT, 2.0)
		&"reached":
			_plate.draw_circle(centre, 11.0, colour)
		&"end":
			var shape := _diamond(centre, 11.0)
			_plate.draw_colored_polygon(shape, UiPalette.PANEL_STRONG)
			shape.append(shape[0])
			_plate.draw_polyline(shape, colour, 2.0)
		_:
			_plate.draw_circle(centre, 11.0, colour)
			_plate.draw_circle(centre, 9.0, Color("#0b0d0b"))
	if level == _focus and tip_level() == _focus:
		var ring := _diamond(centre, 24.0)
		ring.append(ring[0])
		_plate.draw_polyline(ring, UiPalette.AMBER, 1.5)


static func _diamond(centre: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array(
		[
			centre + Vector2(0, -half * 1.4),
			centre + Vector2(half * 1.4, 0),
			centre + Vector2(0, half * 1.4),
			centre + Vector2(-half * 1.4, 0),
		]
	)


func _draw_row_labels() -> void:
	var mono := HudTheme.mono(400, 0)
	_text(Vector2(24, AXIS_Y - 8), tr("ESC_WIN_SCALE").to_upper(), mono, 10, UiPalette.HUD_MUTED)
	_text(Vector2(24, ROW_Y - 20), tr("ESC_ROE").to_upper(), mono, 10, UiPalette.HUD_MUTED)
	_text(
		Vector2(24, ROW_Y + 5.0 * ROW_H + 14.0),
		tr("ESC_WIN_TRIGGERS").to_upper(),
		mono,
		10,
		UiPalette.HUD_MUTED
	)
	for row in CLASS_ORDER.size():
		var label := tr("ESC_ROW_" + String(CLASS_ORDER[row]).to_upper()).to_upper()
		var width := LABEL_WIDTH - 30.0
		var size := _fit(label, mono, 11, width)
		_text(Vector2(24, ROW_Y + 6.0 + row * ROW_H), label, mono, size, UiPalette.HUD_DESC, width)


func _draw_strip(strip: Dictionary, player: int) -> void:
	var own := player == 0
	var width := (PLATE_SIZE.x - 68.0) / maxf(_strips.size(), 1.0)
	var x := 34.0 + player * width
	var w := width - 14.0
	var y := 522.0
	var tint := _palette.side_own if own else _palette.side_enemy
	if own:
		_plate.draw_rect(Rect2(x, y + 4, 14, 9), tint)
	else:
		var diamond := _diamond(Vector2(x + 7, y + 9), 4.0)
		_plate.draw_colored_polygon(diamond, tint)
	var name_font := HudTheme.display(700, 1)
	var label := String(strip["name"]).to_upper()
	_text(Vector2(x + 24, y), label, name_font, 12, UiPalette.HUD_TEXT)
	var collapse: bool = strip["collapse"]
	var right := x + w
	if collapse:
		var chip_text := "▲ " + tr("ESC_COLLAPSE").to_upper()
		var chip_w := _chip_width(chip_text)
		_chip(Vector2(right - chip_w / 2.0, y - 1), chip_text, _palette.ui_alert, true)
		right -= chip_w + 8.0
	var numbers := tr("strength %d %% · readiness %d") % [strip["strength"], strip["readiness"]]
	_text(
		Vector2(x, y + 1),
		numbers,
		HudTheme.mono(400, 0),
		11,
		UiPalette.HUD_MUTED,
		right - x,
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	var gauge := Rect2(x, y + 24, w, 10)
	_plate.draw_rect(gauge, Color("#23271f"))
	var pct: int = strip["strength"]
	var fill := UiPalette.HP_HIGH
	if collapse or pct < _state.ladder.collapse_strength_pct + 1:
		fill = _palette.ui_alert
	elif pct < 75:
		fill = UiPalette.HP_MID
	_plate.draw_rect(Rect2(gauge.position, Vector2(w * clampf(pct / 100.0, 0.0, 1.0), 10)), fill)
	var mark := x + w * _state.ladder.collapse_strength_pct / 100.0
	_plate.draw_rect(Rect2(mark - 1, y + 20, 2, 18), UiPalette.HUD_TEXT)
	_text(
		Vector2(mark - 40, y + 40),
		tr("collapse at ≤ %d %%") % _state.ladder.collapse_strength_pct,
		HudTheme.mono(400, 0),
		10,
		UiPalette.HUD_MUTED,
		w
	)


func _draw_tip(level: int) -> void:
	var tip := tip_of(level)
	var end := level == _state.ladder.top()
	var edge := _palette.ui_alert if end else PLATE_EDGE
	var body_font := HudTheme.font("IBMPlexSansCondensed-Medium")
	var text_h := (
		body_font
		. get_multiline_string_size(tip["text"], HORIZONTAL_ALIGNMENT_LEFT, TIP_SIZE.x - 22.0, 12)
		. y
	)
	var box := Vector2(TIP_SIZE.x, maxf(TIP_SIZE.y, 38.0 + text_h + 8.0))
	var pos := Vector2(
		clampf(_node_x(level) - 110.0, 8.0, PLATE_SIZE.x - box.x - 8.0), AXIS_Y + 30.0
	)
	var shape := HudShapes.chamfer(box, 0, 9, 0, 9)
	var inner := HudShapes.chamfer_inset(box, 1.0, 0, 9, 0, 9)
	for i in shape.size():
		shape[i] += pos
	for i in inner.size():
		inner[i] += pos
	_plate.draw_colored_polygon(shape, edge)
	_plate.draw_colored_polygon(inner, UiPalette.PANEL_STRONG)
	_text(
		pos + Vector2(10, 7),
		String(tip["title"]).to_upper(),
		HudTheme.display(700, 1),
		12,
		_palette.ui_alert if end else UiPalette.HUD_TEXT
	)
	_text(pos + Vector2(10, 28), tip["text"], body_font, 12, UiPalette.HUD_DESC, TIP_SIZE.x - 22.0)


# --- drawing helpers ---


## Draws `text` with its top edge at `at.y`; wraps at `width` (-1 = one line). Returns the height.
func _text(
	at: Vector2,
	text: String,
	font: Font,
	size: int,
	colour: Color,
	width := -1.0,
	align := HORIZONTAL_ALIGNMENT_LEFT
) -> float:
	var baseline := Vector2(at.x, at.y + font.get_ascent(size))
	if width > 0.0 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		_plate.draw_multiline_string(font, baseline, text, align, width, size, -1, colour)
		return font.get_multiline_string_size(text, align, width, size).y
	_plate.draw_string(font, baseline, text, align, width, size, colour)
	return font.get_height(size)


static func _fit(text: String, font: Font, size: int, width: float) -> int:
	var fitted := size
	while (
		fitted > 9 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > width
	):
		fitted -= 1
	return fitted


func _chip_width(text: String) -> float:
	return HudTheme.mono(700, 1).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0


## A chip centred on `at.x` with its top at `at.y`; `fill` = solid with ink text.
func _chip(at: Vector2, text: String, tint: Color, fill: bool) -> void:
	var font := HudTheme.mono(700, 1)
	var w := _chip_width(text)
	var rect := Rect2(at.x - w / 2.0, at.y, w, 17)
	if fill:
		_plate.draw_rect(rect, tint)
	else:
		_plate.draw_rect(rect, tint, false, 1.0)
	_text(
		rect.position + Vector2(0, 2.5),
		text,
		font,
		10,
		UiPalette.INK if fill else tint,
		w,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _dashed_rect(rect: Rect2, colour: Color) -> void:
	var corners := [
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.end,
		rect.position + Vector2(0, rect.size.y),
	]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		_plate.draw_dashed_line(a, b, colour, 1.0, 3.0)
