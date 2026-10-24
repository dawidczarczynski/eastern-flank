class_name HatchBar
extends Control
## Diagonal hatch stripes (135 degrees) in one colour: thin (2 px every 6 px, dividers and
## inactive bars) or wide (6 px every 9 px, active bars). Geometry from HudShapes.

const SCROLL_SPEED := 28.0  ## px per second

@export var color := UiPalette.AMBER:
	set(value):
		color = value
		queue_redraw()
@export var wide := false:
	set(value):
		wide = value
		_rebuild()

## Scroll the stripes left to right like a loader (only while visible).
var scrolling := false:
	set(value):
		scrolling = value
		clip_contents = value
		_rebuild()
		set_process(value)

var _stripes: Array[PackedVector2Array] = []
var _phase := 0.0


func _init(
	bar_color: Color = UiPalette.AMBER, bar_size: Vector2 = Vector2(150, 3), is_wide := false
) -> void:
	color = bar_color
	wide = is_wide
	custom_minimum_size = bar_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_rebuild)


func _ready() -> void:
	set_process(scrolling)
	_rebuild()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_phase = fposmod(_phase + SCROLL_SPEED * delta, _period_x())
	queue_redraw()


## Horizontal distance after which the stripe pattern repeats.
func _period_x() -> float:
	return (HudShapes.HATCH_WIDE_PERIOD if wide else HudShapes.HATCH_THIN_PERIOD) * sqrt(2.0)


func _rebuild() -> void:
	# A scrolling bar draws one extra period on the left that the shift slides into view.
	var area := size + Vector2(_period_x() if scrolling else 0.0, 0.0)
	_stripes = HudShapes.hatch_wide(area) if wide else HudShapes.hatch_thin(area)
	queue_redraw()


func _draw() -> void:
	if scrolling:
		draw_set_transform(Vector2(_phase - _period_x(), 0.0))
	for stripe in _stripes:
		draw_colored_polygon(stripe, color)
