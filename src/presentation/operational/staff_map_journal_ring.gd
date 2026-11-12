class_name StaffMapJournalRing
extends Control
## The amber ring the journal puts on a hex when an entry is clicked (TASK-148b): a circle on the
## HUD layer at the hex's screen point, fading out over 2 s. `tick` follows the camera; it does
## nothing while no ring is shown.

const SECONDS := 2.0
const RADIUS := 30.0
const WIDTH := 2.0

var hex := Vector2i.ZERO

var _left := 0.0


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
	return _left > 0.0


## Per frame while active: follows the hex (`screen_of` maps a hex to a screen point) and fades.
func tick(delta: float, screen_of: Callable) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	if _left <= 0.0:
		hide()
		return
	position = screen_of.call(hex)
	queue_redraw()


func _draw() -> void:
	var alpha := clampf(_left / SECONDS * 1.6, 0.0, 1.0)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 48, Color(UiPalette.AMBER, alpha), WIDTH, true)
