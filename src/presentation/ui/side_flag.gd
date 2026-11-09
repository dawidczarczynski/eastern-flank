class_name SideFlag
extends Control
## Flat flag of a side (TASK-127) with a 1 px frame in the side colour; drawn from
## `SideDefinition.flag`. Hidden and out of the layout when the side has no flag.

const SMALL := Vector2(24, 18)
const LARGE := Vector2(40, 30)
## Turn bar: replaces the faction badge.
const BAR := Vector2(48, 36)

var texture: Texture2D
var frame_colour := UiPalette.LINE


func _init(p_size := SMALL) -> void:
	name = "Flag"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = p_size
	hide()


## Shows `side`'s flag framed in `colour`; hides when there is none.
func setup(side: SideDefinition, colour := UiPalette.LINE) -> void:
	texture = side.flag if side != null else null
	frame_colour = colour
	visible = texture != null
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
	draw_rect(Rect2(Vector2.ZERO, size), frame_colour, false, 1.0)
