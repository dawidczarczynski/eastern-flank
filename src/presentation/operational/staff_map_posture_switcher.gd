class_name StaffMapPostureSwitcher
extends Control
## The posture strip under (or above) the selected own counter (TASK-158, docs/design/
## operational_map/posture_badge_switcher.html variant A): MARCH / ADVANCE / DEFEND segments, the
## active one amber, the caption "MARCH · 100 %" and a tooltip after 250 ms. Screen space, fixed
## pixel size. It only shows what StaffMap hands to present() and reports a click as
## `posture_picked`; the rules live in the commands and the model.

signal posture_picked(posture: StringName)

const CHAMFER := 9.0
const HOVER_LIGHTEN := 0.1
const DISABLED_ALPHA := 0.35
const FADE_SECONDS := 0.12
const TOOLTIP_DELAY := 0.25
const TOOLTIP_HEIGHT := 38.0
const TOOLTIP_MIN_WIDTH := 150.0
const INK := Color("#2a1d05")
const NAME_SIZE := 8
const CAPTION_SIZE := 11
const TIP_TITLE_SIZE := 11
const TIP_BODY_SIZE := 10

var _palette: StaffMapPalette
var _segments: Array[Dictionary] = []
var _flipped := false
var _enabled := true
var _hover := -1
var _tip_hover := -1
var _timer: Timer
var _fade_target := 1.0


func _init() -> void:
	name = "PostureSwitcher"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	size = StaffMapPostureSwitcherModel.strip_rect(false).size


func setup(palette: StaffMapPalette) -> void:
	_palette = palette
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = TOOLTIP_DELAY
	_timer.timeout.connect(_on_tooltip_timer)
	add_child(_timer)


## Shows the strip around the tile at screen point `centre` with `active` highlighted.
func present(centre: Vector2, active: StringName, flipped: bool, enabled: bool) -> void:
	var was_shown := visible
	var segments := StaffMapPostureSwitcherModel.segments(active)
	if (
		was_shown
		and flipped == _flipped
		and enabled == _enabled
		and segments == _segments
		and position == centre + StaffMapPostureSwitcherModel.strip_rect(flipped).position
	):
		return
	_segments = segments
	_flipped = flipped
	_enabled = enabled
	position = centre + StaffMapPostureSwitcherModel.strip_rect(flipped).position
	visible = true
	if not enabled:
		_set_hover(-1)
	var target := 1.0 if enabled else DISABLED_ALPHA
	if not was_shown:
		modulate.a = 0.0
		_animate(target)
	elif not is_equal_approx(_fade_target, target):
		_animate(target)
	queue_redraw()


func clear() -> void:
	if not visible:
		return
	set_process(false)
	visible = false
	_set_hover(-1)


func is_enabled() -> bool:
	return visible and _enabled


func is_flipped() -> bool:
	return _flipped


func hovered_index() -> int:
	return _hover


## True while the tooltip is up (tests).
func tooltip_shown() -> bool:
	return _tip_hover >= 0


## The tile centre in this control's local space.
func _centre() -> Vector2:
	return -StaffMapPostureSwitcherModel.strip_rect(_flipped).position


func _animate(target: float) -> void:
	_fade_target = target
	set_process(true)


func _process(delta: float) -> void:
	modulate.a = move_toward(modulate.a, _fade_target, delta / FADE_SECONDS)
	if is_equal_approx(modulate.a, _fade_target):
		set_process(false)


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_set_hover(_index_at(motion.position))
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		var index := _index_at(button.position)
		if _enabled and index >= 0 and index < _segments.size():
			posture_picked.emit(_segments[index]["posture"])


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hover(-1)


func _index_at(local: Vector2) -> int:
	return StaffMapPostureSwitcherModel.segment_at(local - _centre(), _flipped)


func _set_hover(index: int) -> void:
	if not _enabled:
		index = -1
	if index == _hover:
		return
	_hover = index
	_tip_hover = -1
	if _timer != null:
		if index >= 0:
			_timer.start()
		else:
			_timer.stop()
	queue_redraw()


func _on_tooltip_timer() -> void:
	_tip_hover = _hover
	queue_redraw()


func _draw() -> void:
	if _palette == null or _segments.is_empty():
		return
	var seg_size := StaffMapPostureSwitcherModel.SEGMENT_SIZE
	var active := &""
	for i in _segments.size():
		var active_seg: bool = _segments[i]["active"]
		if active_seg:
			active = _segments[i]["posture"]
		_draw_segment(i, active_seg)
	if active != &"":
		_draw_caption(active)
	if _tip_hover >= 0 and _tip_hover < _segments.size():
		_draw_tooltip(_tip_hover, seg_size)


func _draw_segment(i: int, active: bool) -> void:
	var seg_size := StaffMapPostureSwitcherModel.SEGMENT_SIZE
	var origin := Vector2(seg_size.x * i, 0.0)
	var last := _segments.size() - 1
	var outer_left := CHAMFER if i == 0 else 0.0
	var outer_right := CHAMFER if i == last else 0.0
	var poly: PackedVector2Array
	if _flipped:
		poly = HudShapes.chamfer(seg_size, outer_left, outer_right, 0.0, 0.0)
	else:
		poly = HudShapes.chamfer(seg_size, 0.0, 0.0, outer_right, outer_left)
	poly = _moved(poly, origin)
	var fill := UiPalette.PANEL_STRONG
	if active:
		fill = _palette.ui_amber
	elif i == _hover:
		fill = fill.lightened(HOVER_LIGHTEN)
	draw_colored_polygon(poly, fill)
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, UiPalette.LINE, 1.0)
	var ink := INK if active else _palette.ui_text
	var posture: StringName = _segments[i]["posture"]
	var icon_at := origin + Vector2(seg_size.x * 0.5, 12.0)
	StaffMapPostureGlyphs.draw(self, posture, icon_at, 10.0, ink, 1.5)
	var font := HudTheme.display(700)
	var label := StaffMapPostureSwitcherModel.posture_name(posture)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
	var ink_label := INK if active else (_palette.ui_text if i == _hover else _palette.ui_muted)
	draw_string(
		font,
		origin + Vector2((seg_size.x - width) * 0.5, 27.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		NAME_SIZE,
		ink_label
	)


func _draw_caption(posture: StringName) -> void:
	var font := HudTheme.mono(600)
	var text := StaffMapPostureSwitcherModel.caption(posture)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x
	var x := (size.x - width) * 0.5
	var y := (
		-StaffMapPostureSwitcherModel.CAPTION_GAP - 3.0
		if _flipped
		else (size.y + StaffMapPostureSwitcherModel.CAPTION_GAP + font.get_ascent(CAPTION_SIZE))
	)
	draw_string_outline(
		font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, 3, _palette.map_void
	)
	draw_string(
		font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, _palette.ui_text
	)


## The tooltip plate (chamfered lower-left) on the far side of the caption.
func _draw_tooltip(i: int, seg_size: Vector2) -> void:
	var posture: StringName = _segments[i]["posture"]
	var tip := StaffMapPostureSwitcherModel.tooltip(posture)
	var title_font := HudTheme.display(700)
	var body_font := HudTheme.font("IBMPlexSansCondensed-Medium")
	var body_w := (
		body_font.get_string_size(tip["effect"], HORIZONTAL_ALIGNMENT_LEFT, -1, TIP_BODY_SIZE).x
	)
	var title_w := (
		title_font.get_string_size(tip["title"], HORIZONTAL_ALIGNMENT_LEFT, -1, TIP_TITLE_SIZE).x
	)
	var key_w := (
		body_font.get_string_size(tip["key"], HORIZONTAL_ALIGNMENT_LEFT, -1, TIP_BODY_SIZE).x
	)
	var width := maxf(TOOLTIP_MIN_WIDTH, maxf(body_w, title_w + key_w + 14.0) + 16.0)
	var clearance := (
		StaffMapPostureSwitcherModel.CAPTION_GAP + StaffMapPostureSwitcherModel.CAPTION_HEIGHT + 4.0
	)
	var y := -clearance - TOOLTIP_HEIGHT if _flipped else seg_size.y + clearance
	var x := seg_size.x * (i + 0.5) - width * 0.5
	var plate := Rect2(x, y, width, TOOLTIP_HEIGHT)
	var poly := _moved(HudShapes.chamfer(plate.size, 0.0, 0.0, 0.0, CHAMFER), plate.position)
	draw_colored_polygon(poly, UiPalette.PANEL_STRONG)
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, UiPalette.LINE, 1.0)
	draw_string(
		title_font,
		plate.position + Vector2(8.0, 15.0),
		tip["title"],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TIP_TITLE_SIZE,
		_palette.ui_amber
	)
	draw_string(
		body_font,
		plate.position + Vector2(width - key_w - 8.0, 14.0),
		tip["key"],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TIP_BODY_SIZE,
		_palette.ui_muted
	)
	draw_string(
		body_font,
		plate.position + Vector2(8.0, 29.0),
		tip["effect"],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TIP_BODY_SIZE,
		_palette.ui_text
	)


static func _moved(points: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points:
		result.append(p + by)
	return result
