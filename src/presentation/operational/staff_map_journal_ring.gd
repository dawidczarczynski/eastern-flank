class_name StaffMapJournalRing
extends Control
## The amber ring the journal puts on a hex when an entry is clicked (TASK-148b): a circle on the
## HUD layer at the hex's screen point, fading out over 2 s. `tick` follows the camera; it does
## nothing while no ring is shown.

const SECONDS := 2.0
const RADIUS := 30.0
const WIDTH := 2.0

const OUTLINE_WIDTH := 1.6

var hex := Vector2i.ZERO
## Vertical squash of the outline (cos of the camera pitch) so it lies on the tilted ground.
var y_scale := 1.0

var _left := 0.0
var _outline: Array[Vector2i] = []  # hexes outlined while an objectives row is selected
var _outline_points: Array[Vector2] = []
var _hex_radius := 0.0


func _init() -> void:
	name = "JournalRing"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


## Rings `coord`; `screen` is its screen point.
func show_at(coord: Vector2i, screen: Vector2) -> void:
	hex = coord
	position = screen
	_left = SECONDS
	show()
	queue_redraw()


func is_active() -> bool:
	return _left > 0.0 or not _outline.is_empty()


## Pulses at `pulse` and keeps a hex outline on every hex of `hexes` until `clear_outline`.
func show_selection(hexes: Array[Vector2i], pulse: Vector2i, screen: Vector2) -> void:
	_outline = hexes.duplicate()
	show_at(pulse, screen)


## Removes the outline (and a pulse still running).
func clear_outline() -> void:
	_outline.clear()
	_outline_points.clear()
	_left = 0.0
	hide()


func outline_hexes() -> Array[Vector2i]:
	return _outline


## Per frame while active: follows the hex (`screen_of` maps a hex to a screen point) and fades.
func tick(delta: float, screen_of: Callable) -> void:
	if not is_active():
		return
	if _left > 0.0:
		_left -= delta
	if _left <= 0.0 and _outline.is_empty():
		hide()
		return
	position = screen_of.call(hex)
	_outline_points.clear()
	for coord in _outline:
		_outline_points.append((screen_of.call(coord) as Vector2) - position)
	if not _outline.is_empty():
		_hex_radius = (
			(screen_of.call(hex + Vector2i(1, 0)) as Vector2).distance_to(position) / sqrt(3.0)
		)
	queue_redraw()


func _draw() -> void:
	if _left > 0.0:
		var alpha := clampf(_left / SECONDS * 1.6, 0.0, 1.0)
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(UiPalette.AMBER, alpha), WIDTH, true)
	for centre in _outline_points:
		var corners := PackedVector2Array()
		for i in 7:
			var angle := deg_to_rad(60.0 * i - 30.0)
			corners.append(centre + Vector2(cos(angle), sin(angle) * y_scale) * _hex_radius)
		draw_polyline(corners, UiPalette.AMBER, OUTLINE_WIDTH, true)
