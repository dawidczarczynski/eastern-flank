extends SceneTree
## Renders the battle scene in a window, saves the viewport as PNG and quits.
## Run via tools/screenshot.sh. Manually:
##   godot --path . --resolution 1280x720 --script res://tools/screenshot.gd -- /abs/out.png
## Exit codes: 0 saved, 1 blank image / render or save failure, 2 invalid arguments.

const ScreenshotOptions := preload("res://tools/screenshot_options.gd")
const ScreenshotImage := preload("res://tools/screenshot_image.gd")
const SCENE_PATH := "res://scenes/battle/battle.tscn"
const USAGE := "Usage: tools/screenshot.sh [out.png] [--frames=N]"
const EXPECTED_SIZE := Vector2i(1280, 720)

var _output := ""
var _frames_left := 0
var _battle: Node
var _finished := false  # capture started or run failed – quit() only takes effect after this frame
## Frame-time probe (SCREENSHOT_MEASURE_FRAMES): frames still to time after the warm-up, and the
## frame durations measured so far (microseconds between _process calls).
var _measure_left := 0
var _measure_last_usec := 0
var _measure_samples: Array[int] = []


func _initialize() -> void:
	var options := ScreenshotOptions.parse(OS.get_cmdline_user_args())
	if options["error"] != "":
		_fail("invalid arguments (%s). %s" % [options["error"], USAGE], 2)
		return
	_output = String(options["output"]).simplify_path()
	if _output == "" or not _output.is_absolute_path():
		_fail(
			"the output path must be absolute (tools/screenshot.sh resolves it): '%s'" % _output, 2
		)
		return
	_frames_left = options["frames"]
	_measure_left = ScreenshotOptions.parse_measure_frames(
		OS.get_environment("SCREENSHOT_MEASURE_FRAMES")
	)
	if _measure_left > 0:
		# Uncapped frames, otherwise the probe only measures the vsync interval.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	# No simulated input: stray events from the real mouse/keyboard must not change the scene.
	root.gui_disable_input = true
	root.set_disable_input(true)
	# Visual scale study (TASK-059): the preset must be active before the battle is built.
	var scale_preset := OS.get_environment("SCREENSHOT_SCALE_PRESET")
	if scale_preset != "":
		VisualScale.apply(StringName(scale_preset))
	# Colour look study (TASK-071): likewise before the battle is built.
	var look_preset := OS.get_environment("SCREENSHOT_LOOK")
	if look_preset != "":
		LookPreset.apply(StringName(look_preset))
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		_fail("could not load %s" % SCENE_PATH, 1)
		return
	_battle = scene.instantiate()
	root.add_child(_battle)
	# The scene is set up in _ready; stop its processing so that polled input (Input singleton,
	# mouse position) can't move the camera or add a hover highlight. Rendering continues.
	_battle.process_mode = Node.PROCESS_MODE_DISABLED


func _process(_delta: float) -> bool:
	if _finished:
		return false
	_frames_left -= 1
	if _frames_left == 3:
		# Decals need a few frames in the renderer's cluster before they show.
		var marks_unit := OS.get_environment("SCREENSHOT_MARKS")
		if marks_unit.is_valid_int():
			_battle.call("debug_marks_demo", marks_unit.to_int())
	if _frames_left == 1:
		_apply_debug_selection()
	if _frames_left <= 0:
		if _measure_left > 0:
			_measure_frame()
			return false
		_finished = true
		_capture()
	return false


## Times one frame (the wall time since the previous _process call); prints the summary after the
## last one: "Frame time: avg X ms, max Y ms over N frames".
func _measure_frame() -> void:
	var now := Time.get_ticks_usec()
	if _measure_last_usec > 0:
		_measure_samples.append(now - _measure_last_usec)
		_measure_left -= 1
	_measure_last_usec = now
	if _measure_left > 0:
		return
	var total := 0
	var worst := 0
	for sample in _measure_samples:
		total += sample
		worst = maxi(worst, sample)
	print(
		(
			"Frame time: avg %.2f ms, max %.2f ms over %d frames"
			% [total / 1000.0 / _measure_samples.size(), worst / 1000.0, _measure_samples.size()]
		)
	)
	print(
		(
			"Render: %d draws, %d k tris"
			% [
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			]
		)
	)


func _capture() -> void:
	# The FPS readout is a dev aid; keep it out of screenshots (it shows zeros without a frame loop).
	var fps := _battle.find_child("FpsCounter", true, false) as Control
	if fps != null:
		fps.visible = false
	# Wait until the current frame has really been drawn, otherwise the texture may be stale.
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("could not read the viewport texture", 1)
		return
	if image.get_size() != EXPECTED_SIZE:
		_fail("screenshot is %s, expected %s" % [image.get_size(), EXPECTED_SIZE], 1)
		return
	if ScreenshotImage.is_blank(image):
		_fail("blank screenshot", 1)
		return
	DirAccess.make_dir_recursive_absolute(_output.get_base_dir())
	var error := image.save_png(_output)
	if error != OK:
		_fail("could not save '%s' (%s)" % [_output, error_string(error)], 1)
		return
	print("Screenshot saved: ", _output)
	quit(0)


func _fail(message: String, exit_code: int) -> void:
	_finished = true
	printerr("ERROR: ", message)
	quit(exit_code)


## Debug aid: SCREENSHOT_CAMERA=<unit id>,<yaw degrees>,<distance> points the camera at a unit's
## tile (e.g. the README shot, tools/readme_screenshot.sh); unset = the default overview camera.
## SCREENSHOT_FOCUS=<x>,<z>,<yaw degrees>,<distance> points the camera at a world point instead
## (ignored when SCREENSHOT_CAMERA is set).
## SCREENSHOT_MEASURE_FRAMES=<N> times N frames after the warm-up (vsync off) and prints
## "Frame time: avg X ms, max Y ms over N frames" before the capture.
## SCREENSHOT_PITCH_OFFSET=<radians> adds a camera tilt offset (needs SCREENSHOT_CAMERA).
## SCREENSHOT_SCALE_PRESET=<current|balanced|realistic> is applied in _initialize.
## SCREENSHOT_LOOK=<current|muted_summer|early_autumn|overcast> is applied in _initialize.
## SCREENSHOT_MARKS=<unit id> draws demo ground decals (tracks, craters, scorch) around that
## unit's tile (TASK-058), without animation.
## SCREENSHOT_HOVER_UNIT=<unit id> hovers that unit's tile (hover card with portrait).
## SCREENSHOT_SELECT_UNIT=<unit id> selects that unit (reach wash) and hovers a
## tile two columns right of it (path dots). Runs once the scene's _ready has finished.
func _apply_debug_selection() -> void:
	_battle.call("debug_build_grass")
	var camera := ScreenshotOptions.parse_camera(OS.get_environment("SCREENSHOT_CAMERA"))
	if camera["error"] == "":
		_battle.call(
			"debug_focus_camera",
			camera["unit_id"],
			deg_to_rad(camera["yaw_degrees"]),
			camera["distance"],
			OS.get_environment("SCREENSHOT_PITCH_OFFSET").to_float()
		)
	elif camera["error"] != "none":
		printerr("ERROR: invalid SCREENSHOT_CAMERA (expected <unit id>,<yaw degrees>,<distance>)")
	else:
		var focus := ScreenshotOptions.parse_focus(OS.get_environment("SCREENSHOT_FOCUS"))
		if focus["error"] == "":
			_battle.call(
				"debug_focus_point",
				focus["target"],
				deg_to_rad(focus["yaw_degrees"]),
				focus["distance"]
			)
		elif focus["error"] != "none":
			printerr("ERROR: invalid SCREENSHOT_FOCUS (expected <x>,<z>,<yaw degrees>,<distance>)")
	var select_id := OS.get_environment("SCREENSHOT_SELECT_UNIT")
	if select_id.is_valid_int():
		_battle.call("debug_select_and_hover", select_id.to_int())
	var hover_id := OS.get_environment("SCREENSHOT_HOVER_UNIT")
	if hover_id.is_valid_int():
		_battle.call("debug_hover_unit", hover_id.to_int())
