class_name FpsOverlay
extends Label
## Devtools FPS overlay (TASK-186b): a corner label "NN FPS  X.X ms", refreshed at most 4 times a
## second. Visible only while `DevTunables.fps_overlay` is on (one switch shared by the arena panel
## and the DEVTOOLS page); it reads that every frame, so a toggle elsewhere shows at once.

const REFRESH_MSEC := 250

var _last_refresh := -REFRESH_MSEC  # real time: slow motion must not slow the readout


func _init() -> void:
	name = "FpsOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_theme_color_override("font_color", Color(0.9, 1.0, 0.6))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)
	visible = DevTunables.fps_overlay


## "NN FPS  X.X ms" (the frame time is the reciprocal of the frame rate).
static func format(fps: float) -> String:
	var ms := 1000.0 / fps if fps > 0.0 else 0.0
	return "%d FPS  %.1f ms" % [roundi(fps), ms]


func _process(_delta: float) -> void:
	visible = DevTunables.fps_overlay
	var now := Time.get_ticks_msec()
	if not visible or now - _last_refresh < REFRESH_MSEC:
		return
	_last_refresh = now
	text = format(Engine.get_frames_per_second())
