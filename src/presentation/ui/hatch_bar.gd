class_name HatchBar
extends Control
## Diagonal hatch stripes (135 degrees) in one colour: thin (2 px every 6 px, dividers and
## inactive bars) or wide (6 px every 9 px, active bars). Geometry from HudShapes.

@export var color := UiPalette.AMBER:
	set(value):
		color = value
		queue_redraw()
@export var wide := false:
	set(value):
		wide = value
		_rebuild()

var _stripes: Array[PackedVector2Array] = []


func _init(
	bar_color: Color = UiPalette.AMBER, bar_size: Vector2 = Vector2(150, 3), is_wide := false
) -> void:
	color = bar_color
	wide = is_wide
	custom_minimum_size = bar_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_rebuild)


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	_stripes = HudShapes.hatch_wide(size) if wide else HudShapes.hatch_thin(size)
	queue_redraw()


func _draw() -> void:
	for stripe in _stripes:
		draw_colored_polygon(stripe, color)
