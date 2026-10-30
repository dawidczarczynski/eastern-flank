extends SceneTree
## One-off promo tool: records a ~16 s teaser video of the Homar-K firing a salvo at the T-72B3 in
## the default battle, with a scripted cinematic camera. Run it through tools/teaser.sh, which
## starts Godot in Movie Maker mode (--write-movie, --fixed-fps): every frame advances the game by
## exactly 1 / fps seconds, so the video is smooth however slow the render is.
## Manually: godot --path . --resolution 1920x1080 --write-movie out.avi --fixed-fps 60
##   --script res://tools/teaser.gd -- [--attacker=4] [--target=6] [--seconds=17]
##   [--spin=<pitch deg>,<distance>,<focus blend>]
##
## What the video shows (times from the salvo start; the battle's own loading frames come first,
## hidden behind black):
##   -0.6 s  fade in from black; the camera orbits low around the launcher from its front right
##           while it deploys, raises and traverses the pod (the battle's aim steps)
##    2.6 s  the ripple salvo (12 rockets, 0.5 s apart) seen from the launcher's side, away from the
##           backblast cloud; the camera pulls back and rises
##    5.8 s  a quick crane up and over the forest to the target
##    8.2 s  slow orbit high over the target while the rockets land (its HP bar steps down)
##   ~10.5 s the target dies the battle's way: fireball, burnt-out wreck, smoke, scorched ground
##    13.4 s the picture dims and the game logo (assets/branding/logo_light.png) with SUBTITLE
##           fades in; the last FADE_OUT seconds fade to black
##
## How: the battle scene is instanced with its processing disabled (like tools/screenshot.gd, so
## no polled mouse/keyboard input can move the game camera or hover a tile); this script owns a
## separate Camera3D. The attack is a view-only unit_attacked event (VolleyPlayback.show_attack
## with target_hp 0) played through BattleController._annotate / _play_event – the battle's real
## volley playback and salvo effects. After the last rocket lands it calls
## BattleController._on_unit_died for the target. Nothing goes through GameSimulation: no command,
## no game state change. The HUD and the faction rings under the units are hidden.
##
## The camera path (KEYS) is hand-tuned for the default scenario's Homar-K (4) and T-72B3 (6): the
## angles are relative to the launcher -> target line, but they were chosen around the trees near
## these two units and the timing follows the Homar-K's salvo. Other pairs work (--attacker,
## --target; the attacker must be a rocket launcher) but need a new path; --spin is the location
## scout for that: one full camera turn around the launcher (blend 0) or the target (blend 1) over
## --seconds, without a salvo and without the overlay (render at --fps=1 and look at the frames).

const SCENE_PATH := "res://scenes/battle/battle.tscn"
const PRE_ROLL := 0.6  # seconds of camera move before the salvo event starts
const FOV := 40.0
const MIN_CLEARANCE := 0.12  # the camera never goes closer than this to the ground
const FADE_IN := 1.0
const TITLE_IN := 0.8
const TITLE_START := 3.0  # seconds before the end
const FADE_OUT := 0.7
const LOGO := "res://assets/branding/logo_light.png"  # light letters on a transparent background
const LOGO_WIDTH := 0.46  # of the window width
const DEATH_DELAY := 0.25  # seconds after the last impact
const SUBTITLE := "HOMAR-K  ·  SALVO"

## Camera keyframes: time (s from the salvo start), focus blend (0 = launcher, 1 = target), yaw
## (degrees, relative to the launcher -> target direction; 0 = behind the launcher looking at the
## target, 90 = on its right side), pitch (degrees above the ground), distance (world units) and
## look_up (world units the look point is raised above the focus). The first launch is at ~2.6 s,
## the launches end at ~8 s, the impacts run from ~4.8 s to ~10.3 s, then the target dies.
const KEYS := [
	[-0.6, 0.0, 135.0, 6.0, 1.5, 0.08],
	[1.2, 0.0, 105.0, 8.0, 1.3, 0.10],
	[2.8, 0.0, 88.0, 10.0, 1.35, 0.16],
	[4.4, 0.0, 80.0, 13.0, 2.0, 0.35],
	[5.8, 0.0, 70.0, 16.0, 2.8, 0.5],
	[7.0, 0.6, 80.0, 24.0, 5.5, 0.3],
	[8.2, 1.0, 100.0, 28.0, 4.4, 0.15],
	[11.0, 1.0, 130.0, 26.0, 3.8, 0.15],
	[14.4, 1.0, 160.0, 24.0, 3.6, 0.2],
	[16.4, 1.0, 175.0, 23.0, 3.8, 0.2],
]

var _battle: Node
var _camera := Camera3D.new()
var _black := ColorRect.new()
var _title := VBoxContainer.new()
var _attacker := 4
var _target := 6
var _seconds := 17.0
var _spin := PackedFloat64Array()
var _time := -PRE_ROLL
var _started := false
var _fired := false
var _launcher_at := Vector3.ZERO
var _target_at := Vector3.ZERO


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--attacker="):
			_attacker = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--target="):
			_target = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--seconds="):
			_seconds = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--spin="):
			_spin = arg.get_slice("=", 1).split_floats(",")
	root.gui_disable_input = true
	root.set_disable_input(true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_battle = (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_battle)
	# Like tools/screenshot.gd: no polled input may move the game camera or hover a tile; the
	# volley tween runs with TWEEN_PAUSE_PROCESS.
	_battle.process_mode = Node.PROCESS_MODE_DISABLED
	_camera.fov = FOV
	_camera.far = 400.0
	root.add_child(_camera)
	_build_overlay()


func _process(delta: float) -> bool:
	Engine.max_fps = 0  # FramePacing drops an unfocused window to 5 FPS
	if not bool(_battle.get("is_built")):
		return false
	if not _started:
		_start()
	_time += delta
	_place_camera(_time)
	_update_overlay(_time)
	if _time >= _seconds - PRE_ROLL:
		quit(0)
		return true
	if _spin.is_empty() and _time >= 0.0 and not _fired:
		_fired = true
		_fire()
	return false


func _start() -> void:
	_started = true
	(_battle.get_node("HUD") as CanvasLayer).visible = false
	var views: Dictionary = _battle.get("_unit_views")
	for view: UnitView in views.values():
		for child in view.get_children():
			if child is MeshInstance3D:
				child.visible = false  # faction ring and fill
	# The scene is not processing (see _initialize): let the target's hit and death tweens, the
	# wreck's smoke and the burnt ground run.
	(views[_target] as UnitView).process_mode = Node.PROCESS_MODE_ALWAYS
	(_battle.get("_wrecks") as Node).process_mode = Node.PROCESS_MODE_ALWAYS
	(_battle.get("_marks") as Node).process_mode = Node.PROCESS_MODE_ALWAYS
	_launcher_at = (views[_attacker] as UnitView).global_position
	_target_at = (views[_target] as UnitView).global_position
	var middle := (_launcher_at + _target_at) * 0.5
	_battle.call("debug_focus_point", Vector2(middle.x, middle.z), 0.0, 20.0)  # builds the grass
	_camera.make_current()
	_build_title()


## The battle's volley playback of an attack that leaves the target at 0 HP (its HP bar steps
## down as the rockets land); the target dies just after the last impact.
func _fire() -> void:
	var event := VolleyPlayback.show_attack(_attacker, _target, 0)
	var tween: Tween = _battle.call("_play_event", _battle.call("_annotate", event))
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var volley := _battle.get_node("RocketVolley") as RocketVolley
	volley.rocket_impacted.connect(
		func(index: int, _point: Vector3) -> void:
			if index == volley.count - 1:
				create_timer(DEATH_DELAY, true).timeout.connect(_kill_target)
	)


func _kill_target() -> void:
	var death: Tween = _battle.call("_on_unit_died", _target)
	if death != null:
		death.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)


func _place_camera(t: float) -> void:
	var k := _sample(t)
	if not _spin.is_empty():
		k = [_spin[2], (t + PRE_ROLL) / _seconds * 360.0, _spin[0], _spin[1], 0.1]
	var focus := _launcher_at.lerp(_target_at, clampf(k[0], 0.0, 1.0))
	var to_target := _target_at - _launcher_at
	var base_yaw := atan2(-to_target.x, -to_target.z)  # OrbitMath yaw that looks along to_target
	var eye := OrbitMath.eye(focus, base_yaw + deg_to_rad(k[1]), deg_to_rad(k[2]), k[3])
	var map_view: MapView = _battle.get("_map_view")
	eye.y = maxf(eye.y, map_view.mesh_height_at(eye.x, eye.z) + MIN_CLEARANCE)
	_camera.global_position = eye
	_camera.look_at(focus + Vector3.UP * k[4], Vector3.UP)


## Catmull-Rom through the keyframes; returns [blend, yaw, pitch, distance, look_up].
func _sample(t: float) -> Array[float]:
	var last := KEYS.size() - 1
	var i := 0
	while i < last - 1 and t > float(KEYS[i + 1][0]):
		i += 1
	var t0 := float(KEYS[i][0])
	var t1 := float(KEYS[i + 1][0])
	var u := clampf((t - t0) / (t1 - t0), 0.0, 1.0)
	var result: Array[float] = []
	for c in range(1, 6):
		var p1 := float(KEYS[i][c])
		var p2 := float(KEYS[i + 1][c])
		var p0 := float(KEYS[maxi(i - 1, 0)][c])
		var p3 := float(KEYS[mini(i + 2, last)][c])
		result.append(
			(
				0.5
				* (
					2.0 * p1
					+ (-p0 + p2) * u
					+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u
				)
			)
		)
	return result


# --- Overlay: fade from black (it also hides the loading screen), title card -----------------


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	root.add_child(layer)
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_black)
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.alignment = BoxContainer.ALIGNMENT_CENTER
	_title.modulate.a = 0.0
	layer.add_child(_title)


## The title lines, sized to the window (its size is not known yet in _initialize).
func _build_title() -> void:
	var size := root.get_visible_rect().size
	var height := size.y
	var logo := TextureRect.new()
	logo.texture = load(LOGO) as Texture2D
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var aspect := float(logo.texture.get_height()) / logo.texture.get_width()
	logo.custom_minimum_size = Vector2(size.x * LOGO_WIDTH, size.x * LOGO_WIDTH * aspect)
	_title.add_child(logo)
	_title.add_theme_constant_override(&"separation", int(height * 0.03))
	_title.add_child(_label(SUBTITLE, HudTheme.mono(500, int(height * 0.004)), height * 0.028))


func _label(text: String, font: Font, size: float) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", int(size))
	label.add_theme_color_override(&"font_color", Color("#f2efe6"))
	label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	label.add_theme_constant_override(&"shadow_offset_y", int(size * 0.04))
	return label


func _update_overlay(t: float) -> void:
	if not _spin.is_empty():
		_black.color.a = 0.0
		return
	var end := _seconds - PRE_ROLL
	var title_from := end - TITLE_START
	var fade_in := 1.0 - clampf((t + PRE_ROLL) / FADE_IN, 0.0, 1.0)
	var title := clampf((t - title_from) / TITLE_IN, 0.0, 1.0)
	var fade_out := clampf((t - (end - FADE_OUT)) / FADE_OUT, 0.0, 1.0)
	_black.color.a = maxf(maxf(fade_in, title * 0.45), fade_out)
	_title.modulate.a = title * (1.0 - fade_out)
