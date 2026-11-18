class_name StaffMapObjectivesLayer
extends Control
## The objectives layer of the staff map (TASK-175b, key M; variant A of
## docs/design/operational_map/objectives_window.html): per hex objective a dashed amber ring (r 19)
## with the holder glyph
## (own rectangle / enemy diamond / neutral circle), a points plate 48 x 16 and, from zoom Z1 up
## (always for the selected one), the name. The viewer's main objective (TASK-177, a connection by
## any route, so no route is drawn): a marker on each of the link's two ends (dark disc, amber
## ring, status dot) and between them the status tag ("SUWAŁKI ↔ KAUNAS ▪ CONNECTED +10",
## "KALININGRAD ↔ BELARUS ▪ 2/5"), its text `ui.alert` while the link hurts NATO (cut / connected).
## Only the viewer's own and neutral objectives are drawn (StaffMapObjectivesModel.rows).
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
const END_RADIUS := 19.0
const END_DOT := 5.5
const TAG_LIFT := 12.0
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


## The row whose marker plate (or ring; the main objective: its tag or an end) lies under `screen`,
## -1 for none.
func marker_at(screen: Vector2) -> int:
	if not visible or not _screen_of_hex.is_valid():
		return -1
	for i in _rows.size():
		if _hit_rect(i).has_point(screen):
			return i
		if _is_main(_rows[i]):
			for end in _ends(_rows[i]):
				if end.distance_to(screen) <= END_RADIUS:
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


func _is_main(row: Dictionary) -> bool:
	return row["tier"] == StaffMapObjectivesModel.MAIN


func _centre(row: Dictionary) -> Vector2:
	return _screen_of_hex.call(row["hex"])


## Screen points of the main objective's two ends.
func _ends(row: Dictionary) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for hex: Vector2i in row["hexes"]:
		points.append(_screen_of_hex.call(hex))
	return points


## Where the main objective's tag hangs: halfway between the two ends.
func _tag_anchor(row: Dictionary) -> Vector2:
	var ends := _ends(row)
	if ends.is_empty():
		return Vector2.ZERO
	return (ends[0] + ends[ends.size() - 1]) * 0.5


func _hit_rect(index: int) -> Rect2:
	var row := _rows[index]
	if _is_main(row):
		return _tag_rect(_tag_anchor(row), row["tag"])
	var centre := _centre(row)
	var ring := Rect2(centre - Vector2.ONE * RING_RADIUS, Vector2.ONE * RING_RADIUS * 2.0)
	return ring.merge(_plate_rect(centre))


func _plate_rect(centre: Vector2) -> Rect2:
	return Rect2(
		Vector2(centre.x - PLATE_SIZE.x / 2.0, centre.y + RING_RADIUS + PLATE_GAP), PLATE_SIZE
	)


func _tag_rect(anchor: Vector2, text: String) -> Rect2:
	var width := HudTheme.mono(700).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x
	var size := Vector2(width + 14.0, PLATE_SIZE.y)
	return Rect2(Vector2(anchor.x - size.x / 2.0, anchor.y - TAG_LIFT - size.y), size)


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
	for i in _rows.size():
		if _is_main(_rows[i]):
			_draw_link(_rows[i], i == _selected)
		else:
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


## The main objective: a marker on each end and the status tag between them.
func _draw_link(row: Dictionary, selected: bool) -> void:
	var dot := _status_colour(row["status"])
	for end in _ends(row):
		draw_circle(end, END_RADIUS, Color(_palette.map_void, DISC_ALPHA))
		draw_arc(end, END_RADIUS, 0.0, TAU, 24, _palette.ui_amber, RING_WIDTH, true)
		draw_circle(end, END_DOT, dot)
	var text: String = row["tag"]
	var rect := _tag_rect(_tag_anchor(row), text)
	draw_rect(rect, PANEL_STRONG)
	var edge := _palette.ui_amber if selected else Color(_palette.ui_amber, PLATE_LINE_ALPHA)
	draw_rect(rect, edge, false, 1.0)
	var colour := _palette.ui_alert if row["alert"] else _palette.ui_amber
	_centred(rect, text, HudTheme.mono(700), TAG_SIZE, colour)


func _centred(rect: Rect2, text: String, font: Font, size: int, colour: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := (font.get_ascent(size) - font.get_descent(size)) * 0.5
	var at := Vector2(rect.get_center().x - width / 2.0, rect.get_center().y + baseline)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)
