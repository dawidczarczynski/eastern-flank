class_name StaffMapDecisionParts
extends RefCounted
## Small widgets of the Politics screen (TASK-117, docs/design/operational_map/
## political_decisions.html variant B): bordered chips (solid or dashed), the 5-tick ladder,
## relation shapes, budget pips and the amber button. Pure drawing; texts come translated.

const SHAPE_SIZE := Vector2(12, 12)
const TICK_SIZE := Vector2(13, 9)
const TICK_GAP := 4.0
const TICK_SKEW := 0.2493  # tan(14 deg), the mock-up's skewX(-14deg)
const DASH := 3.0
const MUTED_EDGE := Color("#4a5043")
const DISABLED_TEXT := Color("#6d7466")
const WARN_EDGE := Color("#6e5627")
const DANGER_EDGE := Color("#8a4a38")
const OFF_TEXT := Color("#9aa292")
const BODY_TEXT := Color("#c9cfc0")


## Bordered chip (key chip, cost chip, country chip, tags). `dashed` draws a dashed border.
class Chip:
	extends PanelContainer

	signal clicked

	var edge := UiPalette.HUD_MUTED
	var wash := Color(0, 0, 0, 0)
	var dashed := false

	func _init(clickable := false) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_IGNORE
		auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var style := StyleBoxEmpty.new()
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		add_theme_stylebox_override(&"panel", style)
		if clickable:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()

	func _draw() -> void:
		if wash.a > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), wash)
		var rect := Rect2(Vector2(0.5, 0.5), size - Vector2.ONE)
		if not dashed:
			draw_rect(rect, edge, false, 1.0)
			return
		var corners := [
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
			rect.position,
		]
		for i in 4:
			var from: Vector2 = corners[i]
			var to: Vector2 = corners[i + 1]
			var length := from.distance_to(to)
			var at := 0.0
			while at < length:
				var a := from.lerp(to, at / length)
				var b := from.lerp(to, minf(at + DASH, length) / length)
				draw_line(a, b, edge, 1.0)
				at += DASH * 2.0


## The escalation ladder ticks (one per level): ticks up to `from` filled, the tick `to` (-1 =
## none) hatched as the new level; the last tick has a red outline (the nuclear attack).
class Ticks:
	extends Control

	var count := 5
	var from := 0
	var to := -1
	var alert := UiPalette.DISABLED

	func _init(
		level_count: int, from_level: int, to_level := -1, alert_colour: Color = UiPalette.DISABLED
	) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		count = level_count
		from = from_level
		to = to_level
		alert = alert_colour
		custom_minimum_size = Vector2(
			count * TICK_SIZE.x + (count - 1) * TICK_GAP + TICK_SIZE.y * TICK_SKEW,
			TICK_SIZE.y + 2.0
		)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		for i in count:
			var top := i == count - 1
			var x := i * (TICK_SIZE.x + TICK_GAP)
			var skew := TICK_SIZE.y * TICK_SKEW
			var poly := PackedVector2Array(
				[
					Vector2(x + skew, 1.0),
					Vector2(x + skew + TICK_SIZE.x, 1.0),
					Vector2(x + TICK_SIZE.x, 1.0 + TICK_SIZE.y),
					Vector2(x, 1.0 + TICK_SIZE.y),
				]
			)
			var edge := alert if top else UiPalette.HUD_MUTED
			var is_new := i == to
			if is_new:
				edge = alert if top else UiPalette.AMBER
				draw_colored_polygon(poly, alert if top else Color(UiPalette.AMBER, 0.55))
			elif i <= from:
				draw_colored_polygon(poly, UiPalette.HUD_MUTED)
			var outline := poly.duplicate()
			outline.append(poly[0])
			draw_polyline(outline, edge, 1.0)


## Relation shape of a country: own = rectangle, hostile = diamond, neutral = circle.
class Shape:
	extends Control

	var relation := &"neutral"
	var palette: StaffMapPalette

	func _init(relation_id: StringName, colours: StaffMapPalette) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		relation = relation_id
		palette = colours
		custom_minimum_size = SHAPE_SIZE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var centre := SHAPE_SIZE / 2.0
		match relation:
			&"own":
				draw_rect(
					Rect2(centre - Vector2(5.5, 3.5), Vector2(11, 7)), palette.side_own, false, 1.5
				)
			&"hostile":
				var r := 5.0
				var poly := PackedVector2Array(
					[
						centre + Vector2(0, -r),
						centre + Vector2(r, 0),
						centre + Vector2(0, r),
						centre + Vector2(-r, 0),
						centre + Vector2(0, -r),
					]
				)
				draw_polyline(poly, palette.side_enemy, 1.5)
			_:
				var points := PackedVector2Array()
				for step in 25:
					var angle := TAU * step / 24.0
					points.append(centre + Vector2(cos(angle) * 5.5, sin(angle) * 3.5))
				draw_polyline(points, palette.side_neutral, 1.5)


## Square budget pip: filled when `on`.
class Pip:
	extends Control

	var on := false
	var colour := UiPalette.HUD_TEXT

	func _init(filled: bool, tint: Color, side := 11.0) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		on = filled
		colour = tint
		custom_minimum_size = Vector2(side, side)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		if on:
			draw_rect(Rect2(Vector2.ZERO, size), colour)
		else:
			draw_rect(Rect2(Vector2(0.75, 0.75), size - Vector2(1.5, 1.5)), colour, false, 1.5)


## A chip with one label. `kind`: edge colour / text colour / wash / dashed come from the caller.
static func chip(
	text: String,
	font: Font,
	size: int,
	text_colour: Color,
	edge: Color,
	wash := Color(0, 0, 0, 0),
	dashed := false
) -> Chip:
	var chip_node := Chip.new()
	chip_node.edge = edge
	chip_node.wash = wash
	chip_node.dashed = dashed
	chip_node.add_child(MenuStyle.label(text, font, size, text_colour))
	return chip_node


static func body_font() -> Font:
	return HudTheme.font("IBMPlexSansCondensed-Medium")


## The amber action button (Take / Confirm); `ghost` = outline for Cancel; disabled = dim outline.
static func button(text: String, ghost := false) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(92, 28)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override(&"font", HudTheme.display(700, 2))
	b.add_theme_font_size_override(&"font_size", 12)
	var fill := Color(0, 0, 0, 0) if ghost else UiPalette.AMBER
	var edge := UiPalette.HUD_MUTED if ghost else UiPalette.AMBER
	var ink := UiPalette.HUD_TEXT if ghost else Color("#1a0f02")
	b.add_theme_color_override(&"font_color", ink)
	b.add_theme_color_override(&"font_hover_color", ink)
	b.add_theme_color_override(&"font_pressed_color", ink)
	b.add_theme_color_override(&"font_disabled_color", DISABLED_TEXT)
	b.add_theme_stylebox_override(&"normal", _button_box(fill, edge))
	b.add_theme_stylebox_override(
		&"hover",
		_button_box(
			UiPalette.NOTE_TEXT if not ghost else Color(UiPalette.AMBER, 0.12),
			UiPalette.NOTE_TEXT if not ghost else UiPalette.AMBER
		)
	)
	b.add_theme_stylebox_override(&"pressed", _button_box(UiPalette.NOTE_TEXT, UiPalette.NOTE_TEXT))
	b.add_theme_stylebox_override(&"disabled", _button_box(Color(0, 0, 0, 0), MUTED_EDGE))
	return b


## Repaints an action button red (the nuclear decision, TASK-140): filled `alert`, dark ink; the
## disabled look stays the dim outline.
static func paint_danger(b: Button, alert: Color) -> void:
	for colour in [&"font_color", &"font_hover_color", &"font_pressed_color"]:
		b.add_theme_color_override(colour, UiPalette.INK)
	b.add_theme_stylebox_override(&"normal", _button_box(alert, alert))
	b.add_theme_stylebox_override(
		&"hover", _button_box(alert.lightened(0.15), alert.lightened(0.15))
	)
	b.add_theme_stylebox_override(&"pressed", _button_box(alert.darkened(0.15), alert))


static func _button_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := MenuStyle.box(fill, edge)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
