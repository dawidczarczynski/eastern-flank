class_name CrosshairCursor
extends RefCounted
## The amber crosshair mouse cursor shown over a valid attack target (TASK-089b): a ring with four
## ticks and a centre dot, dark outlined, drawn into an image once.

const SIZE := 32
const RING_RADIUS := 7.0
const TICK_FROM := 10.0
const TICK_TO := 15.0
const STROKE := 0.8  # half width of the amber strokes
const OUTLINE := 1.0  # dark border around them
const OUTLINE_COLOR := Color(0.04, 0.05, 0.035, 0.85)

static var _texture: ImageTexture
static var _active := false


## Shows (true) or restores (false) the normal cursor; cheap when nothing changes.
static func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	if active:
		Input.set_custom_mouse_cursor(texture(), Input.CURSOR_ARROW, Vector2.ONE * SIZE * 0.5)
	else:
		Input.set_custom_mouse_cursor(null)


static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(_draw())
	return _texture


static func _draw() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2.ONE * SIZE * 0.5
	for y in SIZE:
		for x in SIZE:
			var d := _distance(Vector2(x + 0.5, y + 0.5) - center)
			var core := clampf(STROKE + 0.5 - d, 0.0, 1.0)
			var edge := clampf(STROKE + OUTLINE + 0.5 - d, 0.0, 1.0)
			var color := OUTLINE_COLOR
			color.a *= edge
			image.set_pixel(x, y, color.lerp(UiPalette.AMBER, core) if core > 0.0 else color)
	return image


## Distance from `p` (relative to the centre) to the nearest stroke of the crosshair.
static func _distance(p: Vector2) -> float:
	var d := absf(p.length() - RING_RADIUS)
	d = minf(d, p.length() - 0.7)  # centre dot
	for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		var along := clampf(p.dot(axis), TICK_FROM, TICK_TO)
		d = minf(d, p.distance_to(axis * along))
	return d
