extends SceneTree
## Renders the battle scene in a window, saves the viewport as PNG and quits.
## Run via tools/screenshot.sh. Manually:
##   godot --path . --resolution 1280x720 --script res://tools/screenshot.gd -- /abs/out.png
## Exit codes: 0 saved, 1 blank image / render or save failure, 2 invalid arguments.

const ScreenshotOptions := preload("res://tools/screenshot_options.gd")
const ScreenshotImage := preload("res://tools/screenshot_image.gd")
const SCENE_PATH := "res://scenes/battle/battle.tscn"
const MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const CATALOG_SCENE_PATH := "res://scenes/ui/unit_catalog.tscn"
const USAGE := "Usage: tools/screenshot.sh [out.png] [--frames=N]"
const EXPECTED_SIZE := Vector2i(1280, 720)
const GALLERY_SETTLE_FRAMES := 4

var _output := ""
var _frames_left := 0
var _battle: Node
var _catalog_spec := ""  # SCREENSHOT_CATALOG, applied once the scene is ready
var _is_battle := true  # false for the menu and catalog scenes (SCREENSHOT_SCENE)
var _first_frame := true
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
	var scene_name := OS.get_environment("SCREENSHOT_SCENE")
	var scene_path := SCENE_PATH
	match scene_name:
		"menu":
			scene_path = MENU_SCENE_PATH
		"catalog":
			scene_path = CATALOG_SCENE_PATH
		"", "battle":
			pass
		_:
			_fail("unknown SCREENSHOT_SCENE '%s' (battle, menu or catalog)" % scene_name, 2)
			return
	_is_battle = scene_path == SCENE_PATH
	var scene: PackedScene = load(scene_path)
	if scene == null:
		_fail("could not load %s" % scene_path, 1)
		return
	var locale := OS.get_environment("SCREENSHOT_LOCALE")
	_battle = scene.instantiate()
	root.add_child(_battle)
	if locale != "":
		TranslationServer.set_locale(locale)
		if not _is_battle and _battle.has_method("refresh_texts"):
			_battle.call("refresh_texts")
	if not _is_battle:
		_catalog_spec = OS.get_environment("SCREENSHOT_CATALOG") if not _is_battle else ""
		return  # menu and catalog keep processing (the catalog's camera and tweens need it)
	# The scene is set up in _ready; stop its processing so that polled input (Input singleton,
	# mouse position) can't move the camera or add a hover highlight. Rendering continues.
	_battle.process_mode = Node.PROCESS_MODE_DISABLED


func _process(_delta: float) -> bool:
	if _finished:
		return false
	if _is_battle and not bool(_battle.get("is_built")):
		return false  # the battle scene shows its loading screen for a frame before building
	if _first_frame and not _is_battle:
		_first_frame = false
		if _battle.has_method("select_unit"):
			_apply_catalog_state(_catalog_spec)
	if _first_frame and _is_battle:
		_first_frame = false
		var wreck_unit := OS.get_environment("SCREENSHOT_WRECK")
		if wreck_unit.is_valid_int():  # early, so the smoke has the other frames to rise
			_battle.call("debug_wreck_demo", wreck_unit.to_int())
		var salvo := OS.get_environment("SCREENSHOT_SALVO").split(",")
		if salvo.size() == 2 and salvo[0].is_valid_int() and salvo[1].is_valid_int():
			_battle.call("debug_salvo", salvo[0].to_int(), salvo[1].to_int())
		elif OS.get_environment("SCREENSHOT_SALVO") != "":
			printerr("ERROR: invalid SCREENSHOT_SALVO (expected <attacker id>,<target id>)")
	_frames_left -= 1
	if _frames_left == 3 and _is_battle:
		# Decals need a few frames in the renderer's cluster before they show.
		var marks_unit := OS.get_environment("SCREENSHOT_MARKS")
		if marks_unit.is_valid_int():
			_battle.call("debug_marks_demo", marks_unit.to_int())
	if _frames_left == 1 and _is_battle:
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
	var shots := OS.get_environment("SCREENSHOT_SHOTS").strip_edges()
	if shots == "":
		if await _grab_and_save(_output):
			quit(0)
		return
	# Gallery: one process, one PNG per state (<output without .png>_<state>.png). The states
	# accumulate in the listed order, so put replacing ones (banner, targeting) last.
	var base := _output.get_basename()
	for shot in shots.split(","):
		var parts := shot.strip_edges().split(":")
		var state := parts[0]
		var argument := parts[1] if parts.size() > 1 else ""
		if not _apply_gallery_state(state, argument):
			_fail("unknown SCREENSHOT_SHOTS state '%s' (see the header)" % state, 2)
			return
		for _i in GALLERY_SETTLE_FRAMES:
			await process_frame
		if not await _grab_and_save("%s_%s.png" % [base, state]):
			return
	quit(0)


func _apply_gallery_state(state: String, argument: String) -> bool:
	if not _is_battle:
		return false
	match state:
		"hover":
			_battle.call("debug_hover_unit", argument.to_int())
		"select":
			_battle.call("debug_select_and_hover", argument.to_int())
		"toast", "targeting", "banner":
			_battle.call("debug_notice", state)
		_:
			return false
	return true


## Waits for the current frame to be drawn, then validates and saves it. Fails the run on error.
func _grab_and_save(path: String) -> bool:
	# Wait until the current frame has really been drawn, otherwise the texture may be stale.
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("could not read the viewport texture", 1)
		return false
	if image.get_size() != EXPECTED_SIZE:
		_fail("screenshot is %s, expected %s" % [image.get_size(), EXPECTED_SIZE], 1)
		return false
	if ScreenshotImage.is_blank(image):
		_fail("blank screenshot", 1)
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	if error != OK:
		_fail("could not save '%s' (%s)" % [path, error_string(error)], 1)
		return false
	print("Screenshot saved: ", path)
	return true


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
## SCREENSHOT_WRECK=<unit id> destroys that unit's view on the first frame (TASK-065: burnt hulk,
## turret askew, smoke; use --frames=200 or more to see the column).
## SCREENSHOT_SALVO=<attacker id>,<target id> plays that rocket launcher's volley at the target
## view-only from the first frame (TASK-074: aim, ripple salvo, HP steps; no command, no state
## change); --frames=N picks the moment (≈ N / 60 s in, the aim takes 2-3 s before the first
## launch), e.g. SCREENSHOT_SALVO=4,9 SCREENSHOT_FOCUS=... tools/screenshot.sh --frames=200.
## SCREENSHOT_HOVER_UNIT=<unit id> hovers that unit's tile (hover card with portrait).
## SCREENSHOT_NOTICE=<toast|targeting|banner|loading> shows that HUD notice (TASK-080).
## SCREENSHOT_SHOTS=<state>[:<unit id>],... captures several HUD states in one run (one PNG each,
## <out>_<state>.png): hover:<id>, select:<id>, toast, targeting, banner – e.g.
## SCREENSHOT_SHOTS=hover:2,select:2,toast,banner tools/screenshot.sh .screenshots/hud.png
## SCREENSHOT_SCENE=<battle|menu|catalog> renders another scene (default battle);
## SCREENSHOT_LOCALE=<pl|en> switches the language first.
## SCREENSHOT_CATALOG=<unit id>[:<animation>[+<animation>...][:<yaw>,<pitch>,<distance>]] picks
## the catalog unit, plays the animations to their end (finish_pose; "fire" is left running, so
## --frames=N decides which moment of the salvo is captured) and sets the orbit camera (degrees),
## e.g. SCREENSHOT_SCENE=catalog SCREENSHOT_CATALOG=homar_k:deploy+raise+traverse
## tools/screenshot.sh.
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
	var notice := OS.get_environment("SCREENSHOT_NOTICE")
	if notice != "":
		_battle.call("debug_notice", notice)
	var select_id := OS.get_environment("SCREENSHOT_SELECT_UNIT")
	if select_id.is_valid_int():
		_battle.call("debug_select_and_hover", select_id.to_int())
	var hover_id := OS.get_environment("SCREENSHOT_HOVER_UNIT")
	if hover_id.is_valid_int():
		_battle.call("debug_hover_unit", hover_id.to_int())


## Catalog scene: "<unit id>[:<animations joined by +>[:<yaw>,<pitch>,<distance>]]".
func _apply_catalog_state(spec: String) -> void:
	if spec.strip_edges() == "":
		return
	var parts := spec.split(":")
	var definition: UnitDefinition
	for candidate in CatalogUnits.definitions():
		if String(candidate.id) == parts[0]:
			definition = candidate
	if definition == null:
		printerr("ERROR: unknown unit '%s' in SCREENSHOT_CATALOG" % parts[0])
		return
	_battle.call("select_unit", definition)
	var stage: CatalogStage = _battle.call("stage")
	if parts.size() > 1 and parts[1] != "":
		for animation in parts[1].split("+"):
			stage.play(StringName(animation))
			if animation != "fire":
				stage.finish_pose()
	if parts.size() > 2:
		var orbit := parts[2].split(",")
		if orbit.size() == 3:
			_battle.call(
				"set_orbit",
				deg_to_rad(orbit[0].to_float()),
				deg_to_rad(orbit[1].to_float()),
				orbit[2].to_float()
			)
