class_name StaffMapObjectivesLayer
extends Control
## The objectives layer of the staff map (TASK-175b, key M; variant A of
## docs/design/operational_map/objectives_window.html): per hex objective a dashed amber ring (r 19)
## with the holder glyph
## (own rectangle / enemy diamond / neutral circle), a points plate 48 x 16 and, from zoom Z1 up
## (always for the selected one), the name; the Gap chain as a ribbon (the part held by the
## attacker solid in its side colour, the rest dotted amber) with the tag "THE GAP ▪ n/13 +10".
## Fixed screen size like counters, ignores the mouse (the owner asks `marker_at` on a click) and
## is read-only (rule 3).
##
## The texts and holders are cached from StaffMapObjectivesModel; they are recomputed only by
## `refresh` (an `objective_changed` event), a zoom level change or a new selection
## (`redraw_count`). The camera moving only re-projects the cached rows (`layout`).

const RING_RADIUS := 19.0
const RING_WIDTH := 1.6
const DASH_COUNT := 14  # 5 / 4 px dashes round r 19
const PLATE_SIZE := Vector2(48, 16)
const PLATE_GAP := 4.0
const NAME_SIZE := 11
const POINTS_SIZE := 11
const TAG_SIZE := 11
const RIBBON_WIDTH := 5.0
const RIBBON_HALO := 7.0
const DOT_SPACING := 9.0
const DOT_RADIUS := 2.0
const CAP_RADIUS := 6.0
const DISC_ALPHA := 0.7
const PLATE_LINE_ALPHA := 0.6
const GLYPH_HALF := Vector2(7, 5.5)
const PANEL_STRONG := Color("#0a0d0a")

var _palette: StaffMapPalette
var _screen_of_hex: Callable  # (Vector2i hex) -> Vector2 screen point
var _rows: Array[Dictionary] = []
var _selected := -1
var _level := 1
var _enabled := true
var _forced := false
var _redraws := 0


func _init() -> void:
	name = "ObjectivesLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_apply_visibility()


## `screen_of_hex`: maps a hex to its screen point.
func setup(palette: StaffMapPalette, screen_of_hex: Callable) -> void:
	_palette = palette
	_screen_of_hex = screen_of_hex


## Recomputes the rows for `viewer` from `state` (a call per `objective_changed`, and at build).
func refresh(state: OperationalState, viewer: int) -> void:
	_rows = StaffMapObjectivesModel.rows(state, viewer)
	_invalidate()


## The zoom level 0 … 2: names show from Z1.
func set_level(level: int) -> void:
	if level == _level:
		return
	_level = level
	_invalidate()


## The row selected in the objectives window (-1: none); its name is always shown.
func set_selected(index: int) -> void:
	if index == _selected:
		return
	_selected = index
	_invalidate()


## The player's toggle (key M, Map options).
func set_enabled(value: bool) -> void:
	_enabled = value
	_apply_visibility()


func is_enabled() -> bool:
	return _enabled


## True while the objectives window is open: the layer shows whatever the toggle says.
func set_forced(value: bool) -> void:
	_forced = value
	_apply_visibility()


func is_forced() -> bool:
	return _forced


func is_shown() -> bool:
	return visible


## The camera moved: the cached rows are projected again (not counted as a redraw).
func layout() -> void:
	if visible:
		queue_redraw()


## Recomputations of the cached rows so far (tests: nothing redraws without a matching change).
func redraw_count() -> int:
	return _redraws


## Cached model rows (tests).
func rows() -> Array[Dictionary]:
	return _rows


## Whether the name of row `index` is drawn at the current zoom level.
func name_shown(index: int) -> bool:
	return _level >= 1 or index == _selected


## The row whose marker plate (or ring; the Gap: its tag) lies under `screen`, -1 for none.
func marker_at(screen: Vector2) -> int:
	if not visible or not _screen_of_hex.is_valid():
		return -1
	for i in _rows.size():
		if _hit_rect(i).has_point(screen):
			return i
	return -1


## Screen rectangle that opens row `index` when clicked.
func hit_rect(index: int) -> Rect2:
	return _hit_rect(index)


func _apply_visibility() -> void:
	var was := visible
	visible = _enabled or _forced
	if visible and not was:
		queue_redraw()


func _invalidate() -> void:
	_redraws += 1
	queue_redraw()


func _is_gap(row: Dictionary) -> bool:
	return row["tier"] == StaffMapObjectivesModel.MAIN


func _centre(row: Dictionary) -> Vector2:
	return _screen_of_hex.call(row["hex"])


func _hit_rect(index: int) -> Rect2:
	var row := _rows[index]
	var centre := _centre(row)
	if _is_gap(row):
		return _tag_rect(centre, _tag_text(row))
	var ring := Rect2(centre - Vector2.ONE * RING_RADIUS, Vector2.ONE * RING_RADIUS * 2.0)
	return ring.merge(_plate_rect(centre))


func _plate_rect(centre: Vector2) -> Rect2:
	return Rect2(
		Vector2(centre.x - PLATE_SIZE.x / 2.0, centre.y + RING_RADIUS + PLATE_GAP), PLATE_SIZE
	)


func _tag_text(row: Dictionary) -> String:
	var text := "%s ▪ %d/%d +%d" % [tr("THE GAP"), row["held"], row["total"], row["points"]]
	if int(row["held"]) == int(row["total"]):
		text += " · %s %d/%d" % [tr("CLOSED"), row["closed_rounds"], row["need"]]
	return text


func _tag_rect(centre: Vector2, text: String) -> Rect2:
	var width := HudTheme.mono(700).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x
	var size := Vector2(width + 14.0, PLATE_SIZE.y)
	return Rect2(Vector2(centre.x - size.x / 2.0, centre.y - CAP_RADIUS - 6.0 - size.y), size)


func _status_colour(status: StringName) -> Color:
	match status:
		StaffMapObjectivesModel.MINE:
			return _palette.side_own
		StaffMapObjectivesModel.THEIRS:
			return _palette.side_enemy
	return _palette.ui_muted


func _draw() -> void:
	if _palette == null or not _screen_of_hex.is_valid():
		return
	for i in _rows.size():  # ribbon first, markers over it
		if _is_gap(_rows[i]):
			_draw_ribbon(_rows[i], i == _selected)
	for i in _rows.size():
		if not _is_gap(_rows[i]):
			_draw_marker(_rows[i], i)


func _draw_marker(row: Dictionary, index: int) -> void:
	var centre := _centre(row)
	var status: StringName = row["status"]
	draw_circle(centre, RING_RADIUS, Color(_palette.map_void, DISC_ALPHA))
	_dashed_ring(centre, _palette.ui_amber)
	_glyph(centre, status)
	var plate := _plate_rect(centre)
	draw_rect(plate, PANEL_STRONG)
	draw_rect(plate, Color(_palette.ui_amber, PLATE_LINE_ALPHA), false, 1.0)
	var colour := _palette.ui_amber if row["yours"] else _palette.ui_muted
	_centred(plate, "+%d" % row["points"], HudTheme.mono(700), POINTS_SIZE, colour)
	if name_shown(index):
		var font := HudTheme.font("IBMPlexSansCondensed-Medium")
		var text: String = row["label"]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x
		var at := Vector2(centre.x - width / 2.0, plate.end.y + 13.0)
		draw_string_outline(
			font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, 3, _palette.label_halo
		)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, _palette.ui_text)


func _dashed_ring(centre: Vector2, colour: Color) -> void:
	var step := TAU / float(DASH_COUNT)
	for k in DASH_COUNT:
		var from := k * step
		draw_arc(centre, RING_RADIUS, from, from + step * 5.0 / 9.0, 6, colour, RING_WIDTH, true)


func _glyph(centre: Vector2, status: StringName) -> void:
	var colour := _status_colour(status)
	if status == StaffMapObjectivesModel.MINE:
		draw_rect(Rect2(centre - GLYPH_HALF, GLYPH_HALF * 2.0), colour)
	elif status == StaffMapObjectivesModel.THEIRS:
		var r := 7.5
		var diamond := PackedVector2Array(
			[
				centre + Vector2(0, -r),
				centre + Vector2(r, 0),
				centre + Vector2(0, r),
				centre + Vector2(-r, 0)
			]
		)
		draw_colored_polygon(diamond, colour)
	else:
		draw_circle(centre, 6.0, colour)


func _draw_ribbon(row: Dictionary, selected: bool) -> void:
	var chain: Array[Vector2i] = row["chain"]
	var held: Array[bool] = row["chain_held"]
	var points := PackedVector2Array()
	for hex in chain:
		points.append(_screen_of_hex.call(hex))
	if points.size() < 2:
		return
	var attacker := _status_colour(row["attacker_status"])
	for k in range(1, points.size()):  # halo under everything so the dots read on any ground
		draw_line(points[k - 1], points[k], Color(_palette.map_void, 0.8), RIBBON_HALO, true)
	for k in range(1, points.size()):
		if held[k - 1] and held[k]:
			draw_line(points[k - 1], points[k], attacker, RIBBON_WIDTH, true)
		else:
			_dots(points[k - 1], points[k])
	for end in [points[0], points[points.size() - 1]]:
		draw_circle(end, CAP_RADIUS, Color(_palette.map_void, DISC_ALPHA))
		draw_arc(end, CAP_RADIUS, 0.0, TAU, 20, _palette.ui_amber, RING_WIDTH, true)
	var text := _tag_text(row)
	var rect := _tag_rect(_centre(row), text)
	draw_rect(rect, PANEL_STRONG)
	var edge := _palette.ui_amber if selected else Color(_palette.ui_amber, PLATE_LINE_ALPHA)
	draw_rect(rect, edge, false, 1.0)
	var closed := int(row["held"]) == int(row["total"])
	_centred(
		rect, text, HudTheme.mono(700), TAG_SIZE, _palette.ui_alert if closed else _palette.ui_amber
	)


func _dots(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	var count := maxi(int(length / DOT_SPACING), 1)
	for k in count + 1:
		draw_circle(from.lerp(to, float(k) / float(count)), DOT_RADIUS, _palette.ui_amber)


func _centred(rect: Rect2, text: String, font: Font, size: int, colour: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := (font.get_ascent(size) - font.get_descent(size)) * 0.5
	var at := Vector2(rect.get_center().x - width / 2.0, rect.get_center().y + baseline)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)
