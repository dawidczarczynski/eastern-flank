class_name StaffMapStrikeReport
extends StaffMapWindow
## The strike result report card (TASK-097b, variant A of docs/design/operational_map/
## strike-result-report.html): the contact-notice frame with a side-coloured tab, the weapon, the
## target, one pictogram per missile (disc with a cross = hit, ring with a bar = intercepted,
## dashed ring = missed), the integrity / strength change, the interceptor sites, the escalation
## ticks and lines and, for own strikes, stock and strikes left. Pure view: StaffMapStrikeReports
## feeds it with StaffMapStrikeText.report_model(); everything is drawn in code and only rebuilt in
## `present`, so an idle card costs nothing per frame.

const WIDTH := 420.0
const INK := Color("#0a0c09")
const OK_GREEN := Color("#b9d38a")
const WARN := Color("#e2c069")
const SKEW := 0.364  # tan(20 degrees): the slanted segments of the counter / chip ticks

var _palette: StaffMapPalette
var _column: VBoxContainer
var _marker: Control
var _name_text := ""
var _footer_text := ""


func _init(palette: StaffMapPalette = null) -> void:
	super(" ", WIDTH)
	_palette = palette if palette != null else StaffMapPalette.new()
	name = "StrikeReport"
	padding = Vector2(16, 12)
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override(&"separation", 3)
	add_child(_column)
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.custom_minimum_size = Vector2(14, 14)
	_marker.size = Vector2(14, 14)
	_close.get_parent().add_child(_marker)
	hide()


func name_text() -> String:
	return _name_text


func footer_text() -> String:
	return _footer_text


## All label texts of the card (tests), top to bottom.
func texts() -> Array[String]:
	var result: Array[String] = []
	_collect_texts(_column, result)
	return result


func _collect_texts(node: Node, result: Array[String]) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Label:
			result.append((child as Label).text)
		_collect_texts(child, result)


## Fills the card for a StaffMapStrikeText.report_model(): `index` (0-based) of `total` reports,
## `has_next` (kept for callers) whether another report is queued.
func present(model: Dictionary, index := 0, total := 1, has_next := false) -> void:
	var threshold: bool = model["threshold"]
	var own: bool = model["own"]
	var side := StaffMapFormations.side_colour(_palette, model["striker"])
	tab_text = "      " + (model["tab"] as String).to_upper()
	tab_color = _palette.ui_alert if threshold else side
	line_color = Color(_palette.ui_alert, 0.6) if threshold else UiPalette.LINE
	tooltip_text = model["fallback"]
	_place_marker(own, StaffMapFormations.side_ink(_palette, model["striker"]))
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	_name_text = (model["name"] as String).to_upper()
	_column.add_child(_header(model))
	_column.add_child(_target_line(model))
	_column.add_child(_pictograms(model["outcomes"], 24.0))
	_column.add_child(_counts(model))
	_column.add_child(_target_section(model["target"]))
	if model.get("suppressed_line", "") != "":
		var silenced := MenuStyle.label(
			"▲ " + (model["suppressed_line"] as String),
			HudTheme.mono(700, 0),
			12,
			_palette.ui_amber
		)
		silenced.name = "Suppressed"
		_column.add_child(silenced)
	if not (model["interceptors"] as Array).is_empty():
		_column.add_child(_interceptors(model))
	_column.add_child(_escalation(model["escalation"]))
	if threshold:
		_column.add_child(_threshold_tags(model))
	_column.add_child(_footer(model, index, total, has_next))
	show()
	reset_size()


# --- parts ---


func _header(model: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 2)
	var title := MenuStyle.label(_name_text, HudTheme.display(700, 1), 21, UiPalette.HUD_TEXT)
	title.name = "Weapon"
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 6)
	box.add_child(row)
	if model["designation"] != "":
		var designation := MenuStyle.label(
			(model["designation"] as String).to_upper(), HudTheme.mono(600, 0), 11, UiPalette.AMBER
		)
		row.add_child(designation)
		row.add_child(MenuStyle.label("·", HudTheme.mono(500, 0), 11, UiPalette.HUD_MUTED))
	row.add_child(
		MenuStyle.label(
			(model["detail"] as String).to_upper(), HudTheme.mono(500, 0), 11, UiPalette.HUD_MUTED
		)
	)
	return box


func _target_line(model: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 6)
	var target := MenuStyle.label(
		"→ " + (model["target_name"] as String), HudTheme.display(600, 0), 13, UiPalette.HUD_TEXT
	)
	target.name = "Target"
	row.add_child(target)
	if model["target_place"] != "":
		row.add_child(
			MenuStyle.label(
				"· " + (model["target_place"] as String),
				HudTheme.display(600, 0),
				13,
				UiPalette.HUD_MUTED
			)
		)
	return row


func _pictograms(outcomes: Array, px: float) -> Control:
	var row := HBoxContainer.new()
	row.name = "Pictograms"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 5)
	for outcome: StringName in outcomes:
		row.add_child(_glyph(outcome, px))
	return row


func _counts(model: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Counts"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 12)
	var entries := [
		[StaffMapStrikeTrail.HIT, model["hits"], "Hit"],
		[StaffMapStrikeTrail.INTERCEPTED, model["intercepted"], "Intercepted"],
		[StaffMapStrikeTrail.MISSED, model["misses"], "Missed"],
	]
	for entry: Array in entries:
		var cell := HBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override(&"separation", 5)
		cell.add_child(_glyph(entry[0], 15.0))
		cell.add_child(
			MenuStyle.label(str(entry[1]), HudTheme.mono(600, 0), 12, UiPalette.HUD_TEXT)
		)
		cell.add_child(
			MenuStyle.label(
				tr(entry[2]).to_upper(), HudTheme.display(600, 1), 10, UiPalette.HUD_MUTED
			)
		)
		row.add_child(cell)
	return row


func _section() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 3)
	var rule := ColorRect.new()
	rule.color = UiPalette.CARD_EDGE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gap)
	return box


func _label_row(left: String, right: Control) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := MenuStyle.label(left.to_upper(), HudTheme.display(600, 2), 10, UiPalette.HUD_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	if right != null:
		row.add_child(right)
	return row


func _value(text: String, colour: Color, size_px := 13) -> Label:
	return MenuStyle.label(text, HudTheme.mono(600, 0), size_px, colour)


func _tag(text: String, colour: Color, filled := false) -> Control:
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = colour if filled else Color(0, 0, 0, 0)
	box.set_border_width_all(1)
	box.border_color = colour
	box.content_margin_left = 7
	box.content_margin_right = 7
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	tag.add_theme_stylebox_override(&"panel", box)
	tag.add_child(
		MenuStyle.label(text.to_upper(), HudTheme.display(700, 1), 11, INK if filled else colour)
	)
	return tag


func _target_section(target: Dictionary) -> Control:
	var section := _section()
	var delta := int(target["delta"])
	var before := int(target["before"])
	var after := int(target["after"])
	var maximum := maxi(int(target["max"]), 1)
	var heading: String = target["label"]
	if target["name"] != "" and target["kind"] == &"strength":
		heading += " · " + (target["name"] as String)
	var right: Control = null
	if target["destroyed"]:
		right = _tag("✕ " + tr("Destroyed"), _palette.ui_alert, true)
	elif target["no_damage"]:
		right = _tag(tr("No damage"), _palette.ui_amber)
	else:
		right = _value("−%d" % -delta, _palette.ui_alert)
	section.add_child(_label_row(heading, right))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", 6)
	line.add_child(_value("%d →" % before, UiPalette.HUD_TEXT))
	line.add_child(
		_value(str(after), _palette.ui_alert if target["destroyed"] else UiPalette.HUD_TEXT)
	)
	if target["destroyed"]:
		line.add_child(_value("(−%d)" % -delta, _palette.ui_alert))
	elif target["no_damage"]:
		line.add_child(_value("(±0)", UiPalette.HUD_MUTED, 12))
	elif target["kind"] == &"strength":
		line.add_child(_value("/ %d" % maximum, UiPalette.HUD_MUTED, 12))
	section.add_child(line)
	if target["kind"] == &"integrity":
		section.add_child(_bar(before, after, maximum, target["destroyed"]))
	else:
		section.add_child(_segments(before, after, maximum))
	return section


func _interceptors(model: Dictionary) -> Control:
	var section := _section()
	section.name = "Interceptors"
	section.add_child(
		_label_row(tr("Intercepted by"), _value(str(model["intercepted"]), UiPalette.HUD_TEXT))
	)
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override(&"h_separation", 6)
	var first := true
	for site: Dictionary in model["interceptors"]:
		if not first:
			flow.add_child(MenuStyle.label("·", HudTheme.mono(500, 0), 11, UiPalette.HUD_MUTED))
		first = false
		flow.add_child(MenuStyle.label(site["name"], HudTheme.mono(500, 0), 11, UiPalette.HUD_TEXT))
		flow.add_child(
			MenuStyle.label(
				"×%d" % site["count"], HudTheme.mono(500, 0), 11, _palette.outcome_intercepted
			)
		)
	section.add_child(flow)
	return section


func _escalation(escalation: Dictionary) -> Control:
	var section := _section()
	section.name = "Escalation"
	var changed: bool = escalation["changed"]
	var level := int(escalation["level"])
	var top := int(escalation["top"])
	var hot := level >= 3
	var colour := _palette.ui_alert if hot else _palette.ui_amber
	var right := (
		_value("▲ +%d" % escalation["delta"], colour, 13)
		if changed
		else _value(tr("No change").to_upper(), UiPalette.HUD_MUTED, 13)
	)
	section.add_child(_label_row(tr("Escalation"), right))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	row.add_child(_ticks(level, top))
	var text := (
		"%d → %d · %s" % [escalation["previous"], level, escalation["level_name"]]
		if changed
		else "%d · %s" % [level, escalation["level_name"]]
	)
	row.add_child(
		MenuStyle.label(
			text.to_upper(), HudTheme.mono(500, 0), 11, colour if changed else UiPalette.HUD_MUTED
		)
	)
	section.add_child(row)
	for line: Dictionary in escalation["lines"]:
		var label := MenuStyle.label(
			line["text"],
			HudTheme.mono(700 if line["danger"] else 500, 0),
			11,
			_palette.ui_alert if line["danger"] else _palette.ui_amber
		)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(WIDTH - 36.0, 0)
		section.add_child(label)
	return section


func _threshold_tags(_model: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 6)
	row.add_child(_tag("▲ " + tr("Operation ends"), _palette.ui_alert, true))
	row.add_child(_tag(tr("Strategic threshold reached"), _palette.ui_alert))
	return row


func _footer(model: Dictionary, index: int, total: int, _has_next: bool) -> Control:
	var section := _section()
	var row := HBoxContainer.new()
	row.name = "Footer"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 14)
	var parts: Array[String] = []
	var stock: Dictionary = model["stock"]
	var stock_text := (
		"%d → %d" % [stock["before"], stock["after"]] if stock["known"] else tr("unknown")
	)
	row.add_child(_stat(tr("STOCK"), stock_text))
	parts.append("%s %s" % [tr("STOCK"), stock_text])
	if model["own"]:
		var left := "%d / %d" % [model["strikes_left"], model["strikes_max"]]
		row.add_child(_stat(tr("Strikes left"), left))
		parts.append("%s %s" % [tr("Strikes left"), left])
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var keys := "↵ %s" % tr("Log")
	if total > 1:
		keys = "%s · %s" % [tr("%d of %d") % [index + 1, total], keys]
	row.add_child(MenuStyle.label(keys.to_upper(), HudTheme.mono(600, 0), 11, UiPalette.AMBER))
	_footer_text = (" ".join(parts) + " " + keys).to_upper()
	section.add_child(row)
	return section


func _stat(title: String, value: String) -> Control:
	var cell := HBoxContainer.new()
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_theme_constant_override(&"separation", 5)
	cell.add_child(
		MenuStyle.label(title.to_upper(), HudTheme.mono(600, 0), 11, UiPalette.HUD_MUTED)
	)
	cell.add_child(MenuStyle.label(value, HudTheme.mono(700, 0), 11, UiPalette.HUD_TEXT))
	return cell


# --- drawn pieces (rebuilt in `present` only) ---


func _place_marker(own: bool, ink: Color) -> void:
	for connection in _marker.draw.get_connections():
		_marker.draw.disconnect(connection["callable"])
	_marker.position = Vector2(11, 6)
	_marker.draw.connect(
		func() -> void:
			if own:
				_marker.draw_rect(Rect2(0, 2.5, 14, 9), ink)
			else:
				_marker.draw_set_transform(Vector2(7, 7), PI / 4.0)
				_marker.draw_rect(Rect2(-5, -5, 10, 10), ink)
	)
	_marker.queue_redraw()


func _glyph(outcome: StringName, px: float) -> Control:
	var glyph := Control.new()
	glyph.name = String(outcome).capitalize()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.custom_minimum_size = Vector2(px, px)
	glyph.draw.connect(func() -> void: draw_glyph(glyph, outcome, px, _palette))
	return glyph


## One missile pictogram in a `px` square (24 px design units): hit = solid disc with a cross,
## intercepted = ring with a bar, missed = dashed ring. Shape differs, colour is a second cue.
static func draw_glyph(
	canvas: CanvasItem, outcome: StringName, px: float, palette: StaffMapPalette
) -> void:
	var k := px / 24.0
	var c := Vector2(12, 12) * k
	match outcome:
		StaffMapStrikeTrail.HIT:
			canvas.draw_circle(c, 10.0 * k, palette.outcome_hit)
			canvas.draw_line(Vector2(7.5, 7.5) * k, Vector2(16.5, 16.5) * k, INK, 2.6 * k, true)
			canvas.draw_line(Vector2(16.5, 7.5) * k, Vector2(7.5, 16.5) * k, INK, 2.6 * k, true)
		StaffMapStrikeTrail.INTERCEPTED:
			canvas.draw_arc(c, 9.5 * k, 0.0, TAU, 32, palette.outcome_intercepted, 2.4 * k, true)
			canvas.draw_line(
				Vector2(5, 12) * k, Vector2(19, 12) * k, palette.outcome_intercepted, 2.4 * k, true
			)
		_:
			var dash := 3.5 / 9.5
			var step := 6.5 / 9.5
			var angle := 0.0
			while angle < TAU - 0.01:
				canvas.draw_arc(
					c, 9.5 * k, angle, angle + dash, 4, palette.outcome_miss, 2.0 * k, true
				)
				angle += step


func _bar(before: int, after: int, maximum: int, destroyed: bool) -> Control:
	var bar := Control.new()
	bar.name = "Bar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0, 9)
	var alert := _palette.ui_alert
	bar.draw.connect(
		func() -> void:
			var w := bar.size.x
			var h := bar.size.y
			bar.draw_rect(Rect2(0, 0, w, h), UiPalette.TRACK)
			if destroyed:
				_hatch(bar, Rect2(0, 0, w, h), Color(alert, 0.5), 7.0)
				bar.draw_rect(Rect2(0, 0, w, h), alert, false, 1.0)
				return
			var solid := w * float(after) / maximum
			var colour := (
				OK_GREEN if after * 4 >= maximum * 3 else (WARN if after * 2 >= maximum else alert)
			)
			bar.draw_rect(Rect2(0, 0, solid, h), colour)
			var ghost := w * float(before - after) / maximum
			if ghost > 0.5:
				var rect := Rect2(solid, 0, ghost, h)
				_hatch(bar, rect, Color(alert, 0.55), 6.0)
				bar.draw_rect(rect, alert, false, 1.0)
	)
	return bar


func _segments(before: int, after: int, maximum: int) -> Control:
	var row := Control.new()
	row.name = "Segments"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, 8)
	var alert := _palette.ui_alert
	row.draw.connect(
		func() -> void:
			var solid := ceili(5.0 * after / maximum)
			var shown := ceili(5.0 * before / maximum)
			for i in 5:
				var x := i * 33.0
				var colour := UiPalette.TRACK
				if i < solid:
					colour = OK_GREEN
				elif i < shown:
					colour = Color(alert, 0.35)
				row.draw_colored_polygon(_slanted(x, 30.0, 8.0), colour)
				if solid <= i and i < shown:
					row.draw_polyline(_slanted(x, 30.0, 8.0, true), alert, 1.0)
	)
	return row


func _ticks(level: int, top: int) -> Control:
	var ticks := Control.new()
	ticks.name = "Ticks"
	ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticks.custom_minimum_size = Vector2((top + 1) * 19.0, 7)
	var palette := _palette
	ticks.draw.connect(
		func() -> void:
			for i in top + 1:
				var colour := (
					StaffMapEscalation.level_colour(i, top, palette)
					if i <= level
					else UiPalette.TRACK
				)
				ticks.draw_colored_polygon(_slanted(i * 19.0, 16.0, 7.0), colour)
	)
	return ticks


static func _slanted(x: float, width: float, height: float, closed := false) -> PackedVector2Array:
	var lean := height * SKEW
	var points := PackedVector2Array(
		[
			Vector2(x + lean, 0),
			Vector2(x + width + lean, 0),
			Vector2(x + width, height),
			Vector2(x, height)
		]
	)
	if closed:
		points.append(points[0])
	return points


## 45-degree hatch lines clipped to `rect` (diagonal stripes of the lost part).
static func _hatch(canvas: CanvasItem, rect: Rect2, colour: Color, step: float) -> void:
	var h := rect.size.y
	var offset := -h
	while offset < rect.size.x:
		var t0 := maxf(0.0, -offset / h)
		var t1 := minf(1.0, (rect.size.x - offset) / h)
		if t1 > t0:
			var a := rect.position + Vector2(offset + t0 * h, h - t0 * h)
			var b := rect.position + Vector2(offset + t1 * h, h - t1 * h)
			canvas.draw_line(a, b, colour, 1.5)
		offset += step
