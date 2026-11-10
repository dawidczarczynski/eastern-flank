class_name StaffMapPlaceLayer
extends Control
## Place-name labels of the staff map (TASK-112) in screen space, drawn in one pass with a dark
## halo. The visible set (StaffMapPlaceFilter) is recomputed only when the camera, the viewport,
## the zoom level or the toggle changed; idle frames cost nothing. Sits below the counters.

const FONT_FILE := "IBMPlexSansCondensed-SemiBold"
const TEXT := Color("eef2e6")
const LATIN_SCALE := 0.85
const HALO := Color("111411")
const HALO_PX := 3

## How many times the visible set was recomputed (tests).
var rebuild_count := 0

var _font: Font
var _names := PackedStringArray()
var _latin := PackedStringArray()  # transliteration of a Cyrillic name, else ""
var _ranks := PackedInt32Array()
var _anchors := PackedVector3Array()  # on the relief
var _sizes := PackedVector2Array()
var _shown := PackedInt32Array()
var _points := PackedVector2Array()  # label centres on screen
var _enabled := true
var _key: Variant = null


func _init() -> void:
	name = "PlaceNames"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## IBM Plex Sans Condensed has no Cyrillic, so the data face (JetBrains Mono) backs it up for
## Belarusian / Russian names.
static func label_font() -> Font:
	var font := FontVariation.new()
	font.base_font = HudTheme.font(FONT_FILE)
	font.fallbacks = [HudTheme.mono(500).base_font]
	return font


## Reads the map's places; `relief` gives the height under each anchor.
func build(map: ImportedMap, relief: StaffMapRelief) -> void:
	_font = label_font()
	for i in map.place_count():
		var place := map.place_at(i)
		var rank: int = place["rank"]
		var text: String = place["name"]
		var latin := PlaceTransliteration.latin(text)
		_names.append(text)
		_latin.append(latin)
		_ranks.append(rank)
		_anchors.append(relief.surface_point(place["position"]))
		var size := _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, StaffMapPlaceFilter.FONT_SIZES[rank]
		)
		var height := _font.get_height(StaffMapPlaceFilter.FONT_SIZES[rank])
		if not latin.is_empty():
			var small := _latin_size(rank)
			size.x = maxf(size.x, _font.get_string_size(latin, 0, -1, small).x)
			height += _font.get_height(small)
		_sizes.append(Vector2(size.x, height))
	_key = null


static func _latin_size(rank: int) -> int:
	return maxi(int(StaffMapPlaceFilter.FONT_SIZES[rank] * LATIN_SCALE), 9)


func place_count() -> int:
	return _names.size()


func is_enabled() -> bool:
	return _enabled


func set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	if not value:
		_key = null  # recompute on the next layout


## Indices of the labels currently drawn.
func shown() -> PackedInt32Array:
	return _shown


func label_text(index: int) -> String:
	return _names[index]


## Recomputes the visible set when `camera_key` (anything that changes with the camera),
## `viewport`, `zoom_level` or the `obstacles` (screen rects of counters) differ from the last
## call. `project` maps a relief point (Vector3) to the screen.
func layout(
	project: Callable,
	viewport: Vector2,
	zoom_level: int,
	camera_key: Variant,
	obstacles: Array[Rect2] = []
) -> void:
	if not _enabled or _names.is_empty():
		return
	var key := [camera_key, viewport, zoom_level, obstacles]
	if key == _key:
		return
	_key = key
	rebuild_count += 1
	var screen := PackedVector2Array()
	screen.resize(_anchors.size())
	for i in _anchors.size():
		screen[i] = project.call(_anchors[i])
	var shifts := {}
	_shown = StaffMapPlaceFilter.visible_places(
		_ranks, screen, _sizes, zoom_level, Rect2(Vector2.ZERO, viewport), obstacles, shifts
	)
	for i in shifts:
		screen[i] += shifts[i]
	_points = screen
	queue_redraw()


func _draw() -> void:
	for i in _shown:
		var size := StaffMapPlaceFilter.FONT_SIZES[_ranks[i]]
		var top := _points[i] - _sizes[i] * 0.5
		_text_line(_names[i], size, top, _sizes[i].x)
		if not _latin[i].is_empty():
			var small := _latin_size(_ranks[i])
			var second := top + Vector2(0.0, _font.get_height(size))
			_text_line(_latin[i], small, second, _sizes[i].x)


## One centred line of text whose top-left box corner is `top`, with the halo underneath.
func _text_line(text: String, size: int, top: Vector2, width: float) -> void:
	var line_w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := top + Vector2((width - line_w) * 0.5, _font.get_ascent(size))
	draw_string_outline(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, HALO_PX, HALO)
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, TEXT)
