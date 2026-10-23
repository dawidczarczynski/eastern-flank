class_name TickRuler
extends Control
## The 300 x 10 tick ruler under the turn bar (61 ticks, 5 px apart, heights 8 / 5 / 3).

const SIZE := Vector2(300, 10)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE


func _draw() -> void:
	draw_multiline(HudShapes.ruler_ticks(), UiPalette.LINE, 1.0)
