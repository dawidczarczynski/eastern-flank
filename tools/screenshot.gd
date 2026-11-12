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
const STAFF_MAP_SCENE_PATH := "res://scenes/operational/staff_map.tscn"
const USAGE := "Usage: tools/screenshot.sh [out.png] [--frames=N]"
const DEFAULT_RESOLUTION := "1280x720"  # SCREENSHOT_RESOLUTION (tools/screenshot.sh) overrides it
const GALLERY_SETTLE_FRAMES := 4

var _output := ""
var _frames_left := 0
var _battle: Node
var _catalog_spec := ""  # SCREENSHOT_CATALOG, applied once the scene is ready
var _is_battle := true  # false for the menu, catalog and staff map scenes (SCREENSHOT_SCENE)
var _is_staff_map := false
var _first_frame := true
var _finished := false  # capture started or run failed – quit() only takes effect after this frame
## Frame-time probe (SCREENSHOT_MEASURE_FRAMES): frames still to time after the warm-up, and the
## frame durations measured so far (microseconds between _process calls).
var _measure_left := 0
var _measure_last_usec := 0
var _measure_samples: Array[int] = []
## Viewport render time (RenderingServer measure_render_time) summed over the timed frames, ms.
var _measure_gpu_ms := 0.0
var _measure_cpu_ms := 0.0


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
		"staff_map":
			scene_path = STAFF_MAP_SCENE_PATH
		"", "battle":
			pass
		_:
			_fail(
				"unknown SCREENSHOT_SCENE '%s' (battle, menu, catalog or staff_map)" % scene_name, 2
			)
			return
	_is_battle = scene_path == SCENE_PATH
	_is_staff_map = scene_path == STAFF_MAP_SCENE_PATH
	var scene: PackedScene = load(scene_path)
	if scene == null:
		_fail("could not load %s" % scene_path, 1)
		return
	var locale := OS.get_environment("SCREENSHOT_LOCALE")
	_battle = scene.instantiate()
	var battle_problem := _apply_battle_start()
	if battle_problem != "":
		_fail(battle_problem, 2)
		return
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
	if (_is_battle or _is_staff_map) and not bool(_battle.get("is_built")):
		return false  # these scenes show a loading screen for a frame before building
	if _first_frame and _is_staff_map:
		_first_frame = false
		_apply_staff_map_state(OS.get_environment("SCREENSHOT_STAFF_MAP"))
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
		var move := OS.get_environment("SCREENSHOT_MOVE").split(",")
		if (
			move.size() == 3
			and move[0].is_valid_int()
			and move[1].is_valid_int()
			and move[2].is_valid_int()
		):
			_battle.call("debug_move", move[0].to_int(), move[1].to_int(), move[2].to_int())
		elif OS.get_environment("SCREENSHOT_MOVE") != "":
			printerr("ERROR: invalid SCREENSHOT_MOVE (expected <unit id>,<direction 0-5>,<tiles>)")
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
	# The battle's FramePacing caps a focused window at 60 FPS (and an unfocused one at 5) from its
	# _ready and on focus changes; keep the probe uncapped or it only measures the cap.
	Engine.max_fps = 0
	var now := Time.get_ticks_usec()
	if _measure_last_usec == 0:
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	if _measure_last_usec > 0:
		_measure_samples.append(now - _measure_last_usec)
		var rid := root.get_viewport_rid()
		_measure_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		_measure_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(rid)
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
			"Render: %d draws, %d k tris, GPU %.2f ms, render CPU %.2f ms (avg)"
			% [
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
				_measure_gpu_ms / _measure_samples.size(),
				_measure_cpu_ms / _measure_samples.size(),
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
		"tag", "ring", "ring_attack", "ring_info", "ring_blocked", "ring_own":
			return _apply_target_state(state, argument)
		"result":
			_battle.call("debug_result", argument if argument != "" else "victory")
		"briefing":
			_battle.call("debug_campaign", "")
		"report":
			_battle.call("debug_campaign", argument if argument != "" else "victory")
		_:
			return false
	return true


## Target tag / ring states (TASK-089b), argument "<attacker id>-<target id>": selects the
## attacker and hovers the target (tag), then opens the unit ring (ring: nothing hovered,
## ring_attack / ring_blocked: ATTACK hovered, ring_info: INFO triggered – the unit's card,
## ring_own: the same on an own unit as the target). All but ring_blocked and ring_own first move
## the target next to the attacker (a debug-only state change), so it is in range.
func _apply_target_state(state: String, argument: String) -> bool:
	var ids := argument.split("-")
	if ids.size() != 2 or not ids[0].is_valid_int() or not ids[1].is_valid_int():
		printerr("ERROR: SCREENSHOT_SHOTS %s needs <attacker id>-<target id>" % state)
		return false
	var attacker := ids[0].to_int()
	var target := ids[1].to_int()
	if state != "ring_blocked" and state != "ring_own":
		_battle.call("debug_place_next_to", attacker, target)
	_battle.call("debug_select_and_hover", attacker)
	_battle.call("debug_hover_unit", target)
	var ring := _battle.find_child("TargetRing", true, false)
	var slots := {"ring": -1, "ring_attack": 0, "ring_info": 1, "ring_blocked": 0, "ring_own": 1}
	if state == "tag":
		ring.call("close")
	else:
		ring.call("debug_open", attacker, target, slots[state])
	return true


## Waits for the current frame to be drawn, then validates and saves it. Fails the run on error.
func _grab_and_save(path: String) -> bool:
	# Wait until the current frame has really been drawn, otherwise the texture may be stale.
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("could not read the viewport texture", 1)
		return false
	var expected := _expected_size()
	if image.get_size() != expected:
		_fail("screenshot is %s, expected %s" % [image.get_size(), expected], 1)
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


func _expected_size() -> Vector2i:
	var spec := OS.get_environment("SCREENSHOT_RESOLUTION")
	var parts := (spec if spec != "" else DEFAULT_RESOLUTION).split("x")
	return Vector2i(parts[0].to_int(), parts[1].to_int()) if parts.size() == 2 else Vector2i.ZERO


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
## SCREENSHOT_FOV=<degrees> narrows the camera's field of view (a tele close-up of effects that are
## tiny at the closest camera distance, e.g. salvo backblast; the default is the game's fov).
## SCREENSHOT_PITCH_OFFSET=<radians> adds a camera tilt offset (needs SCREENSHOT_CAMERA).
## SCREENSHOT_SCALE_PRESET=<current|balanced|realistic|true> is applied in _initialize (`true`:
## units, trees, scrub, rocks and grass at 1:1 of MapScale, TASK-110 study).
## SCREENSHOT_MIN_DISTANCE=<world units, 0.05-7> lets SCREENSHOT_CAMERA / SCREENSHOT_FOCUS go
## closer than the game's zoom limit (CameraMath.MIN_DISTANCE); below it the camera looks at the
## ground under the target (TASK-110 real-scale close-ups, e.g. SCREENSHOT_MIN_DISTANCE=1
## SCREENSHOT_CAMERA=2,-40,1.5).
## SCREENSHOT_LOOK=<current|muted_summer|early_autumn|overcast> is applied in _initialize.
## SCREENSHOT_MARKS=<unit id> draws demo ground decals (tracks, craters, scorch) around that
## unit's tile (TASK-058), without animation.
## SCREENSHOT_WRECK=<unit id> destroys that unit's view on the first frame (TASK-065: burnt hulk,
## turret askew, smoke; use --frames=200 or more to see the column).
## SCREENSHOT_SALVO=<attacker id>,<target id> plays that rocket launcher's volley at the target
## view-only from the first frame (TASK-074: aim, ripple salvo, HP steps; no command, no state
## change); --frames=N picks the moment (≈ N / 60 s in, the aim takes 2-3 s before the first
## launch), e.g. SCREENSHOT_SALVO=4,9 SCREENSHOT_FOCUS=... tools/screenshot.sh --frames=200.
## SCREENSHOT_MOVE=<unit id>,<direction 0-5>,<tiles> plays a view-only move of that unit from the
## first frame (TASK-064 dust and exhaust, tracks; no command, no state change); --frames=N picks
## the moment (≈ N / 60 s in), e.g. SCREENSHOT_MOVE=2,0,3 tools/screenshot.sh --frames=120.
## SCREENSHOT_HOVER_UNIT=<unit id> hovers that unit's tile (the target tag over a valid target of
## the selected unit; there is no hover card since TASK-089b – the card shows via the ring's INFO).
## SCREENSHOT_NOTICE=<toast|targeting|banner|loading> shows that HUD notice (TASK-080).
## SCREENSHOT_SHOTS=<state>[:<unit id>],... captures several HUD states in one run (one PNG each,
## <out>_<state>.png): hover:<id>, select:<id>, toast, targeting, banner,
## result:<victory|defeat|draw> (the held result banner with its reason line), briefing and
## report:<victory|defeat|draw> (TASK-094c campaign battle: the commander's briefing on a demo
## mission, the mission line, the end screen as a report with Report to staff),
## tag:<attacker>-<target>, ring:…, ring_attack:…, ring_info:…, ring_blocked:…, ring_own:…
## (TASK-089b target tag and unit ring, see _apply_target_state) – e.g.
## SCREENSHOT_SHOTS=hover:2,select:2,toast,banner tools/screenshot.sh .screenshots/hud.png
## SCREENSHOT_SCENARIO=<one of Scenario.NAMES> starts that scenario (like the game's
## `--scenario=` user argument), e.g. the TASK-088 objective markers and turn
## limit: SCREENSHOT_SCENARIO=objective_battle tools/screenshot.sh .screenshots/objectives.png
## SCREENSHOT_SCENE=<battle|menu|catalog|staff_map> renders another scene (default battle);
## SCREENSHOT_LOCALE=<pl|en> switches the language first.
## SCREENSHOT_CATALOG=<unit id>[:<animation>[+<animation>...][:<yaw>,<pitch>,<distance>]] picks
## the catalog unit, plays the animations to their end (finish_pose; "fire" is left running, so
## --frames=N decides which moment of the salvo is captured) and sets the orbit camera (degrees),
## e.g. SCREENSHOT_SCENE=catalog SCREENSHOT_CATALOG=homar_k:deploy+raise+traverse
## tools/screenshot.sh.
## SCREENSHOT_STAFF_MAP=<token>,... sets up the staff map (TASK-093a): zoom:<factor> (clamped to
## the map's limits; "min"/"max" allowed), focus:<col>:<row> (centre on that hex), grid (G),
## hover:<col>:<row> (the hover card), pitch:<degrees> (camera tilt, 0 = flat; default 35,
## TASK-125), side:<player> (view as player 0 / 1, TASK-092b), select:<formation id> (formation
## panel), hovercounter:<formation id> (counter hover), route:<col>:<row> (route preview of the
## selected formation to that hex, TASK-092c), posture:<1-3> (posture of the selected formation,
## TASK-092d) and order:<formation id>:<col>:<row>:<1-3> (gives that formation an order in that
## posture; view as the side to play), ring:<col>:<row>[:<slot 1-6>] (the order ring of the
## selected formation on that hex, optionally with a slot hovered; needs select:), e.g.
## nohud (hides the whole HUD, the map and counters stay: the main menu backdrop),
## cover (the air defence cover overlay), suppress:<installation id>[:<rounds>] (silences a site),
## country:<id> (the country card, TASK-114), options (the map options window),
## journal[:<strikes|battles|moves|politics>] (the journal window with that chip, TASK-148b),
## politics (the --debug panel),
## strike:<means>[:<target id>[:fire]] (strike mode with that means; with a target its confirm
## card, with fire the strike is made, TASK-097b),
## escalate:<steps> (raises the escalation level by NATO, TASK-115; stops at the cap, TASK-140),
## collapse:<player> (halves that side's fielded strength in the state so it counts as collapsing,
## TASK-140), nuclear:<player> (that player's nuclear attack: the end notice, TASK-140),
## turn:<player> (hands the turn to that player in the state, a still-image shortcut),
## decisions[:confirm[:<card key 1-6>]] (the Politics screen, optionally with the
## confirmation of that card, default 1), ladder[:<level>] (removed)
## the tooltip of that level), endturn (after the orders:
## ends the move, skips the slide, TASK-092e),
## contact:<attacker id>:<defender id> (moves the attacker next to the defender and starts the
## battle, TASK-094a: dimmed map and contact notice; repeat for a queue),
## contactmap:<col>:<row>:<col>:<row> (the debug contact-map panel with that attacker / defender
## hex pair picked and its cut outlined, TASK-094b), result (after contact:… – resolves the
## first battle as a demo win of the attacker and shows the short result notice, TASK-094c;
## resulttab:<0|1> selects that side's tab, 0 = attacker),
## e.g. SCREENSHOT_SCENE=staff_map SCREENSHOT_STAFF_MAP=pitch:0,zoom:max,focus:30:20,grid.
## SCREENSHOT_SELECT_UNIT=<unit id> selects that unit (reach wash) and hovers a
## tile two columns right of it (path dots). Runs once the scene's _ready has finished.
func _apply_debug_selection() -> void:
	_battle.call("debug_build_grass")
	var min_distance := ScreenshotOptions.parse_min_distance(
		OS.get_environment("SCREENSHOT_MIN_DISTANCE")
	)
	if min_distance < 0.0:
		printerr("ERROR: invalid SCREENSHOT_MIN_DISTANCE (expected world units, 0.05-7)")
	elif min_distance > 0.0:
		_battle.call("debug_min_camera_distance", min_distance)
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
	var fov := OS.get_environment("SCREENSHOT_FOV")
	if fov.is_valid_float() and get_root().get_camera_3d() != null:
		get_root().get_camera_3d().fov = clampf(fov.to_float(), 5.0, 120.0)
	var notice := OS.get_environment("SCREENSHOT_NOTICE")
	if notice != "":
		_battle.call("debug_notice", notice)
	var select_id := OS.get_environment("SCREENSHOT_SELECT_UNIT")
	if select_id.is_valid_int():
		_battle.call("debug_select_and_hover", select_id.to_int())
	var hover_id := OS.get_environment("SCREENSHOT_HOVER_UNIT")
	if hover_id.is_valid_int():
		_battle.call("debug_hover_unit", hover_id.to_int())


## SCREENSHOT_SCENARIO / SCREENSHOT_CONTACT: what the battle scene starts; "" or the problem.
func _apply_battle_start() -> String:
	var scenario := OS.get_environment("SCREENSHOT_SCENARIO")
	if scenario != "":
		if not _is_battle or scenario not in Scenario.NAMES:
			return "unknown SCREENSHOT_SCENARIO '%s' (%s)" % [scenario, ", ".join(Scenario.NAMES)]
		_battle.set("scenario_name", scenario)
	var contact := OS.get_environment("SCREENSHOT_CONTACT")
	if contact != "":
		var setup := _contact_setup(contact) if _is_battle else null
		if setup == null:
			return "invalid SCREENSHOT_CONTACT '%s' (<col>:<row>:<col>:<row>)" % contact
		_battle.set("setup", setup)
	return ""


## SCREENSHOT_CONTACT=<col>:<row>:<col>:<row> (battle scene, TASK-094b): the contact battle of
## that attacker / defender hex pair of the suwalki_gap start, as the staff map's debug "Open
## battle map" starts it; null when the hexes are invalid or the cut fails.
func _contact_setup(spec: String) -> BattleSetup:
	var parts := spec.split(":")
	if parts.size() != 4:
		return null
	var state := Operation.build(&"suwalki_gap", 1)
	var preview := StaffMapContactPreview.new(state, ImportedMap.find(state.map_id))
	var picked := preview.pick_pair(
		MapGenerator.offset_to_axial(parts[0].to_int(), parts[1].to_int()),
		MapGenerator.offset_to_axial(parts[2].to_int(), parts[3].to_int())
	)
	print("Contact map: ", " | ".join(preview.lines()))
	return preview.setup if picked else null


## Staff map scene: tokens of SCREENSHOT_STAFF_MAP; processing stops afterwards so that the real
## mouse can't pan the camera or move the hover card.
func _apply_staff_map_state(spec: String) -> void:
	var map: StaffMap = _battle
	map.card().hide()  # a card from the real mouse position before processing stopped
	map.view().highlight(StaffMapView.NO_HEX)
	var zoom_spec := "min"
	var centre := map.view().world_bounds().get_center() / StaffMapView.UNIT
	var hover := Vector2i(-1, -1)
	var show_hover := false
	var select_id := &""
	var hover_counter := &""
	var route_hex := Vector2i(-1, -1)
	var show_route := false
	var route_posture := 0
	var orders: Array = []
	var ring: Array = []
	var end_turn_after := false
	var joins: Array = []
	var contacts: Array = []
	var contact_map: Array = []
	var show_result := false
	var result_tab := -1
	var no_hud := false
	var journal_filter: Variant = null
	for token in spec.split(",", false):
		var parts := token.strip_edges().split(":")
		match parts[0]:
			"zoom":
				zoom_spec = parts[1] if parts.size() > 1 else ""
			"focus", "hover":
				if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
					printerr("ERROR: invalid SCREENSHOT_STAFF_MAP token '%s'" % token)
					continue
				var axial := MapGenerator.offset_to_axial(parts[1].to_int(), parts[2].to_int())
				if parts[0] == "focus":
					var w := Hex.to_world(axial, 1.0)
					centre = Vector2(w.x, w.z)
				else:
					hover = axial
					show_hover = true
			"route":
				if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
					printerr("ERROR: invalid SCREENSHOT_STAFF_MAP token '%s'" % token)
					continue
				route_hex = MapGenerator.offset_to_axial(parts[1].to_int(), parts[2].to_int())
				show_route = true
			"posture":
				route_posture = parts[1].to_int() if parts.size() > 1 else 0
			"order":
				if parts.size() != 5:
					printerr("ERROR: invalid SCREENSHOT_STAFF_MAP token '%s'" % token)
					continue
				orders.append(parts)
			"ring":
				if parts.size() < 3:
					printerr("ERROR: invalid SCREENSHOT_STAFF_MAP token '%s'" % token)
					continue
				ring = parts
			"endturn":
				end_turn_after = true
			"join":  # join:<country id>:<side> – the country turns belligerent (TASK-118)
				if parts.size() != 3:
					printerr("ERROR: invalid SCREENSHOT_STAFF_MAP token '%s'" % token)
					continue
				joins.append(parts)
			"contact":
				if parts.size() != 3:
					printerr("ERROR: invalid SCREENSHOT_STAFF_MAP token '%s'" % token)
					continue
				contacts.append(parts)
			"result":
				show_result = true
			"resulttab":
				result_tab = int(parts[1]) if parts.size() == 2 else 0
			"contactmap":
				if parts.size() != 5:
					printerr("ERROR: invalid SCREENSHOT_STAFF_MAP token '%s'" % token)
					continue
				contact_map = parts
			"grid":
				map.view().set_grid_visible(true)
			"cover":  # the air defence cover overlay (key C, TASK-098b)
				map.toggle_air_defence_cover()
				map.air_defence_cover().settle()
			"suppress":  # suppress:<installation id>[:<rounds>] – a silenced air-defence site
				var site := map.simulation().state.get_installation(StringName(parts[1]))
				site.suppressed_rounds = int(parts[2]) if parts.size() > 2 else 2
				map.installations().refresh()
				map.air_defence_cover().set_zones(StaffMapAirDefence.zones(map.simulation().state))
			"country":
				map.open_country_card(StringName(parts[1]) if parts.size() > 1 else &"")
			"politics":
				map.politics_hud().toggle_panel()
			"options":  # the map options window
				map.toggle_options()
			"journal":  # journal[:<strikes|battles|moves|politics>] – the journal window, TASK-148b
				journal_filter = parts[1] if parts.size() > 1 else ""
			"escalate":
				var steps := parts[1].to_int() if parts.size() > 1 else 1
				for event in EscalationRules.raise(
					map.simulation().state, 0, &"sanctuary_breach", steps
				):
					map.simulation().event_emitted.emit(event)
			"nuclear":
				var user := parts[1].to_int() if parts.size() > 1 else 1
				for event in EscalationRules.nuclear_use(map.simulation().state, user):
					map.simulation().event_emitted.emit(event)
				if parts.size() > 2:  # nuclear:<player>:<seconds> freezes the end notice's fade at that time
					map.escalation_hud().end_notice().seek(parts[2].to_float())
					map.escalation_hud().end_notice().set_process(false)
			"turn":
				map.simulation().state.current_player = parts[1].to_int() if parts.size() > 1 else 1
			"collapse":
				var who := parts[1].to_int() if parts.size() > 1 else 1
				var state := map.simulation().state
				state.fielded_strength[who] = CollapseRules.present_strength(state, who) * 2
			"strike":  # strike:<means>[:<target id>[:fire]] – strike mode, TASK-097b
				map.toggle_strike_mode()
				var strike := map.strike_hud()
				strike.pick_means(StringName(parts[1]) if parts.size() > 1 else &"jassm_er")
				map.air_defence_cover().settle()  # no frames run: finish the cover's fade
				if parts.size() > 2:
					strike.click(StringName(parts[2]))
					if parts.size() > 3 and parts[3] == "fire":
						strike.confirm()
						var trail := strike.trail()  # no frames run: arcs done, effects playing
						trail.clock += trail.seconds_to_last_impact() + 0.3
						strike.layer().layout()
						strike.tick(30.0)  # the result report card appears after the impact
						strike.tick(0.2)
						if parts.size() > 4 and parts[4] == "chip":
							strike.tick(10.0)  # the collapsed chip instead of the card
			"decisions":
				map.toggle_decisions()
				var sheet := map.decisions_hud().panel()
				if parts.size() > 1 and parts[1] == "confirm":  # a card asks its confirmation
					var card_key := parts[2].to_int() if parts.size() > 2 else 1
					sheet.handle_key((KEY_1 + card_key - 1) as Key)
					sheet.handle_key(KEY_ENTER)
				sheet.finish_fade()
			"side":
				map.set_viewer(parts[1].to_int() if parts.size() > 1 else 0)
			"select":
				select_id = StringName(parts[1]) if parts.size() > 1 else &""
			"hovercounter":
				hover_counter = StringName(parts[1]) if parts.size() > 1 else &""
			"nohud":
				no_hud = true
			"pitch":
				if parts.size() != 2 or not parts[1].is_valid_float():
					printerr("ERROR: invalid SCREENSHOT_STAFF_MAP token '%s'" % token)
					continue
				map.debug_pitch(parts[1].to_float())
			_:
				printerr("ERROR: unknown SCREENSHOT_STAFF_MAP token '%s'" % token)
	var limits := map.zoom_limits()  # after the pitch: the minimum zoom depends on it
	var zoom := (
		limits.x
		if zoom_spec == "min"
		else (limits.y if zoom_spec == "max" else zoom_spec.to_float())
	)
	map.debug_focus(centre, zoom)
	if show_hover:
		map.debug_hover(hover)
	for order in orders:
		map.select_formation(StringName(order[1]))
		map.issue_order(
			MapGenerator.offset_to_axial(order[2].to_int(), order[3].to_int()),
			StaffMapRoute.posture_for_key(order[4].to_int())
		)
	for join in joins:
		var state := map.simulation().state
		for event in CountryRules.set_stance(
			state, StringName(join[1]), &"belligerent", join[2].to_int(), &"screenshot", -1
		):
			map.simulation().event_emitted.emit(event)
	for contact in contacts:
		_start_contact(map, StringName(contact[1]), StringName(contact[2]))
	if show_result:
		map.debug_result_notice()
		if result_tab >= 0:
			map.result_notice().select_side(result_tab)
	if end_turn_after:  # the orders run, the slide is skipped, the mover's report is shown
		var mover := map.simulation().state.current_player
		map.end_turn()
		map.skip_slide()
		map.set_viewer(mover)
	if journal_filter != null:
		map.open_journal()
		var chip := {
			"strikes": &"strike", "battles": &"battle", "moves": &"move", "politics": &"politics"
		}
		map.journal_window().set_filter(chip.get(journal_filter, &""))
	if select_id != &"" or not orders.is_empty():
		map.select_formation(select_id)
	if route_posture > 0:
		map.set_posture_number(route_posture)
	if show_route:
		map.route_preview().set_hex(route_hex)
		map.route_preview().rebuild()
		map.view().highlight(route_hex)
	if not ring.is_empty():
		var ring_hex := MapGenerator.offset_to_axial(ring[1].to_int(), ring[2].to_int())
		map.right_click_at(map.hex_screen_position(ring_hex))
		if ring.size() > 3:
			map.order_ring().ring().hovered = ring[3].to_int() - 1
			map.order_ring().ring().slot_hovered.emit(ring[3].to_int() - 1)
		map.view().highlight(ring_hex)
	if not contact_map.is_empty():
		var debug := map.contact_debug()
		debug.toggle(Vector2(16, 130))
		debug.pick_pair(
			MapGenerator.offset_to_axial(contact_map[1].to_int(), contact_map[2].to_int()),
			MapGenerator.offset_to_axial(contact_map[3].to_int(), contact_map[4].to_int())
		)
		print("Contact map: ", " | ".join(debug.preview().lines()))
	if hover_counter != &"" and map.counters() != null:
		map.counters().set_hovered(hover_counter)
	if no_hud:  # the counters, front and map stay: a backdrop (tools/menu_backdrop.sh)
		(map.get("_hud") as CanvasLayer).visible = false
	map.process_mode = Node.PROCESS_MODE_DISABLED


## Moves `attacker_id` next to `defender_id` and lets ContactRules start the battle like the end
## of a turn would (the events reach the map as real ones).
func _start_contact(map: StaffMap, attacker_id: StringName, defender_id: StringName) -> void:
	var state := map.simulation().state
	var attacker := state.get_formation(attacker_id)
	var defender := state.get_formation(defender_id)
	if attacker == null or defender == null:
		printerr("ERROR: unknown formation in contact:%s:%s" % [attacker_id, defender_id])
		return
	for neighbor in Hex.neighbors(defender.coord):
		if state.formation_at(neighbor) == null:
			attacker.coord = neighbor
			break
	var events: Array[Dictionary] = [
		{
			"type": &"formation_halted",
			"formation_id": attacker.id,
			"at": attacker.coord,
			"reason": &"contact",
		}
	]
	ContactRules.start_battles(state, events)
	for event in events:
		map.simulation().event_emitted.emit(event)


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
