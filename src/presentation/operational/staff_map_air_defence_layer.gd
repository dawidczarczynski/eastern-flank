class_name StaffMapAirDefenceLayer
extends Control
## The air defence coverage overlay of the staff map (TASK-098b, docs/design/operational_map/
## air_defence_overlay.html variant A "Glass zones"): per non-destroyed site a true circle of
## `radius_hexes` x 5 km on the ground, projected through the camera (an ellipse when tilted).
## Active zone: owner colour fill 11 %, solid ring 1.4 px; suppressed: `ui.muted` ring dashed 6 / 5
## and a 45 degree hatch 5 px at 28 %, no fill. Overlaps add up. It sits under the counters, ignores
## the mouse and fades in / out in 150 ms. The polygons, dashes and hatch lines are cached
## (`_shapes`) and rebuilt only when the zones change or the camera moved (`layout`), never per
## frame; the draw call only replays them.

const FILL_ALPHA := 0.11
const RING_WIDTH := 1.4
const RING_ALPHA := 0.9
const DASH_ON := 6.0
const DASH_OFF := 5.0
const HATCH_SPACING := 5.0
const HATCH_ALPHA := 0.28
const FADE_SECONDS := 0.15

var _palette: StaffMapPalette
var _ground_to_screen: Callable  # (Vector2 ground, hex units) -> Vector2 screen
var _zones: Array[Dictionary] = []
var _shapes: Array[Dictionary] = []  # per zone: {fill, ring, dashes, hatch, colour, suppressed}
var _dirty := true
var _shown := false
var _alpha := 0.0
var _rebuilds := 0


func _init() -> void:
	name = "AirDefenceCover"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	visible = false


## `ground_to_screen`: maps a ground point (hex units, x east / y south) to the screen.
func setup(palette: StaffMapPalette, ground_to_screen: Callable) -> void:
	_palette = palette
	_ground_to_screen = ground_to_screen


## The zones to draw (StaffMapAirDefence.zones); rebuilds the geometry only when they changed.
func set_zones(zones: Array[Dictionary]) -> void:
	if zones == _zones:
		return
	_zones = zones.duplicate()
	_dirty = true
	if _shown:
		_rebuild()


## Shows or hides the layer (a 150 ms fade).
func set_shown(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	if shown:
		visible = true
		if _dirty:
			_rebuild()
	set_process(true)


func is_shown() -> bool:
	return _shown


func zone_count() -> int:
	return _zones.size()


## Number of cached zone shapes (equals `zone_count` while shown).
func shape_count() -> int:
	return _shapes.size()


## How often the geometry was rebuilt (tests: no rebuild per frame).
func rebuild_count() -> int:
	return _rebuilds


## The cached zone shape at `index` (tests): {fill, ring, dashes, hatch, colour, suppressed}.
func shape(index: int) -> Dictionary:
	return _shapes[index]


## The camera moved or the window resized: the cached geometry is stale.
func layout() -> void:
	_dirty = true
	if _shown:
		_rebuild()


## Finishes the fade at once (screenshots and tests that run no frames).
func settle() -> void:
	_alpha = 1.0 if _shown else 0.0
	modulate.a = _alpha
	visible = _shown
	set_process(false)


func _process(delta: float) -> void:
	var target := 1.0 if _shown else 0.0
	_alpha = move_toward(_alpha, target, delta / FADE_SECONDS)
	modulate.a = _alpha
	if is_equal_approx(_alpha, target):
		set_process(false)
		visible = _shown


func _rebuild() -> void:
	_dirty = false
	_rebuilds += 1
	_shapes.clear()
	if _palette != null and _ground_to_screen.is_valid():
		for zone in _zones:
			_shapes.append(_build_shape(zone))
	queue_redraw()


func _build_shape(zone: Dictionary) -> Dictionary:
	var coord: Vector2i = zone["coord"]
	var w := Hex.to_world(coord, 1.0)
	var ground := StaffMapAirDefence.ring(
		Vector2(w.x, w.z), StaffMapAirDefence.radius_units(int(zone["radius_hexes"]))
	)
	var screen := PackedVector2Array()
	screen.resize(ground.size())
	for i in ground.size():
		screen[i] = _ground_to_screen.call(ground[i])
	var suppressed: bool = zone["suppressed"]
	var closed := screen.duplicate()
	closed.append(screen[0])
	return {
		"fill": screen,
		"ring": closed,
		"dashes": StaffMapAirDefence.dashes(screen, DASH_ON, DASH_OFF) if suppressed else [],
		"hatch":
		StaffMapAirDefence.hatch(screen, HATCH_SPACING) if suppressed else PackedVector2Array(),
		"colour": StaffMapFormations.side_colour(_palette, zone["owner"]),
		"suppressed": suppressed,
	}


func _draw() -> void:
	if _palette == null:
		return
	for shape in _shapes:
		var colour: Color = shape["colour"]
		if shape["suppressed"]:
			var muted := _palette.ui_muted
			draw_multiline(shape["hatch"], Color(muted, HATCH_ALPHA), 1.0)
			for dash: PackedVector2Array in shape["dashes"]:
				draw_polyline(dash, Color(muted, RING_ALPHA), RING_WIDTH, true)
		else:
			draw_colored_polygon(shape["fill"], Color(colour, FILL_ALPHA))
			draw_polyline(shape["ring"], Color(colour, RING_ALPHA), RING_WIDTH, true)
