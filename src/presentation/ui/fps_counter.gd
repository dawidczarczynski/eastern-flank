class_name FpsCounter
extends Label
## Frames-per-second readout in the top-right corner, refreshed a few times a second, with the
## render cost behind it: CPU and GPU time of the frame, draw calls and thousands of triangles.

const REFRESH_SECONDS := 0.25
const MARGIN := 8

var _elapsed := 0.0


func _ready() -> void:
	name = "FpsCounter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_theme_color_override(&"font_color", UiPalette.TEXT_SECONDARY)
	add_theme_color_override(&"font_outline_color", UiPalette.BACKGROUND)
	add_theme_constant_override(&"outline_size", 4)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	var rid := get_viewport().get_viewport_rid()
	text = (
		"%d FPS\nCPU %.1f ms  GPU %.1f ms\n%d draws  %d k tris"
		% [
			Engine.get_frames_per_second(),
			RenderingServer.viewport_get_measured_render_time_cpu(rid),
			RenderingServer.viewport_get_measured_render_time_gpu(rid),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
		]
	)
