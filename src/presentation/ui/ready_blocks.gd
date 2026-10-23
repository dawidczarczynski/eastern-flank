class_name ReadyBlocks
extends Control
## The ready-unit counter of the end-turn module: one 14 x 8 block per living unit, filled in
## the faction colour for a unit that can still act, a 1 px inset outline for one that is done.

const BLOCK := Vector2(14, 8)
const GAP := 3.0

var ready_count := 0
var total := 0
var color := UiPalette.NEUTRAL_FACTION


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows `ready_units` filled blocks out of `total_units` in `fill_color`.
func set_counts(ready_units: int, total_units: int, fill_color: Color) -> void:
	ready_count = clampi(ready_units, 0, maxi(total_units, 0))
	total = maxi(total_units, 0)
	color = fill_color
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	var width := maxf(total * (BLOCK.x + GAP) - GAP, 0.0)
	return Vector2(width, BLOCK.y)


func _draw() -> void:
	for i in total:
		var rect := Rect2(Vector2(i * (BLOCK.x + GAP), 0), BLOCK)
		if i < ready_count:
			draw_rect(rect, color)
		else:
			draw_rect(rect.grow(-0.5), UiPalette.READY_EMPTY, false, 1.0)
