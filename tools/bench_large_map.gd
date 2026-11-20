extends SceneTree
## Large-map benchmark (TASK-072a): builds the Suwalki battle map tiled to `scale` times its area
## (MapTiler: 1, 4 or 16) in a bare scene (map, camera, sun, environment; no units, no HUD), then
## prints the build cost and the frame time at fixed cameras and during a pan sweep.
## Run via tools/bench_large_map.sh. Manually:
##   godot --path . --script res://tools/bench_large_map.gd -- --scale=4 --quality=high
## Output lines (the shell wrapper collects them into tables):
##   BUILD <scale> <hexes> <build s> <grass s> <static MB> <video MB> <instances> <tris k> <draws>
##   FRAME <scale> <camera> <avg ms> <max ms> <frames> <frames > 33 ms>
## Exit codes: 0 done, 1 failure, 2 invalid arguments.

enum Phase { START, SETTLE, SAMPLE, PAN, DONE }

const SUWALKI_MAP_ID := &"suwalki"
const SETTLE_FRAMES := 30
const SAMPLE_FRAMES := 120
const PAN_SECONDS := 10.0
const PAN_DISTANCE := 24.0
const SLOW_FRAME_MS := 33.0
## Camera distances of ADR 0021 (world units): overview, default, closest game zoom, study zoom.
const CAMERA_DISTANCES: Array[float] = [46.0, 24.0, 7.0, 1.2]
const PREBUILD_CHUNKS_PER_FRAME := 4

var _scale := 1
var _level := -1
var _map_view: MapView
var _rig: CameraRig
var _grid: HexGrid
var _bounds := Rect2()
var _center := Vector2.ZERO
var _phase := Phase.START
var _camera_index := 0
var _frame := 0
var _last_usec := 0
var _samples: Array[float] = []
var _pan_start_usec := 0
var _hexes := 0
var _finished := false
## [build s, grass s, static MB, video bytes before], printed with the first camera's frame.
var _pending_build: Array = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scale="):
			_scale = arg.trim_prefix("--scale=").to_int()
		elif arg.begins_with("--quality="):
			_level = GraphicsQuality.parse_override([arg])
	if _scale not in [1, 4, 16]:
		_fail("--scale must be 1, 4 or 16", 2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.gui_disable_input = true
	root.set_disable_input(true)


func _process(_delta: float) -> bool:
	if _finished:
		return false
	match _phase:
		Phase.START:
			# One drawn frame first, so the window and renderer are up before the heavy build.
			if _frame < 2:
				_frame += 1
				return false
			_build()
		Phase.SETTLE:
			_settle()
		Phase.SAMPLE:
			_sample()
		Phase.PAN:
			_pan()
	return false


func _build() -> void:
	var map := ImportedMap.find(SUWALKI_MAP_ID)
	if map == null:
		_fail("map '%s' is missing" % SUWALKI_MAP_ID, 1)
		return
	var n := MapTiler.tiles_for_scale(_scale)
	_grid = MapTiler.tile(map.to_grid(), map.width, map.height, n, n)
	_hexes = _grid.coords().size()
	var quality := _setup_scene()
	var static_before := OS.get_static_memory_usage()
	var video_before := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var started := Time.get_ticks_usec()
	_map_view.build(_grid)
	var build_s := (Time.get_ticks_usec() - started) / 1e6
	var centers: Array[Vector3] = []
	for c in _grid.coords():
		centers.append(Hex.to_world(c, _map_view.hex_size))
	_bounds = CameraMath.map_bounds(centers, _map_view.hex_size)
	_center = _bounds.get_center()
	_rig.set_bounds(_bounds)
	_rig.set_ground_query(_map_view.visible_ground_height)
	_rig.set_min_distance_override(CAMERA_DISTANCES[-1])
	_rig.set_view(_center, 0.0, CAMERA_DISTANCES[0])
	_map_view.set_camera_target(_rig.target())
	var grass_s := 0.0
	if quality.get("grass_density", 1.0) > 0.0:
		started = Time.get_ticks_usec()
		var grass := _map_view.grass()
		grass.begin_prebuild()
		while not grass.prebuild_step(PREBUILD_CHUNKS_PER_FRAME, true):
			pass
		grass_s = (Time.get_ticks_usec() - started) / 1e6
	var static_mb := (OS.get_static_memory_usage() - static_before) / 1048576.0
	_camera_index = 0
	_begin_settle()
	_pending_build = [build_s, grass_s, static_mb, video_before]


## The scene the battle has, minus units and HUD; returns the quality switches in use.
func _setup_scene() -> Dictionary:
	var level: GraphicsQuality.Level
	if _level >= 0:
		level = _level as GraphicsQuality.Level
	else:
		level = GraphicsQuality.detect(
			RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()
		)
	var quality := GraphicsQuality.features(level)
	print("Graphics quality: %s" % GraphicsQuality.level_name(level))
	var world_env := WorldEnvironment.new()
	world_env.environment = (
		(load("res://assets/environments/battle_environment.tres") as Environment).duplicate()
		as Environment
	)
	GraphicsQuality.apply_environment(world_env.environment, quality)
	root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(
		Basis(
			Vector3(0.6141, 0, 0.789),
			Vector3(0.4847, 0.7886, -0.3773),
			Vector3(-0.6224, 0.6143, 0.4844)
		),
		Vector3(0, 10, 0)
	)
	sun.light_color = Color(1, 0.93333334, 0.8666667)
	sun.light_energy = 1.1
	sun.light_angular_distance = 1.0
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	GraphicsQuality.apply_sun(sun, quality)
	root.add_child(sun)
	GraphicsQuality.apply_viewport(root, quality)
	_map_view = MapView.new()
	_map_view.quality = quality
	root.add_child(_map_view)
	_rig = CameraRig.new()
	var camera := Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.1
	camera.far = 220.0
	_rig.add_child(camera)
	root.add_child(_rig)
	_rig.process_mode = Node.PROCESS_MODE_DISABLED
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	return quality


func _begin_settle() -> void:
	_phase = Phase.SETTLE
	_frame = 0
	_samples.clear()
	var distance := CAMERA_DISTANCES[_camera_index]
	_rig.set_view(_center, 0.0, distance)
	_map_view.set_camera_distance(distance)
	_map_view.set_camera_target(_rig.target())


func _settle() -> void:
	_frame += 1
	_map_view.set_camera_target(_rig.target())
	if _frame < SETTLE_FRAMES:
		return
	_phase = Phase.SAMPLE
	_frame = 0
	_last_usec = 0


func _sample() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_samples.append((now - _last_usec) / 1000.0)
	_last_usec = now
	if _samples.size() < SAMPLE_FRAMES:
		return
	if _camera_index == 0 and not _pending_build.is_empty():
		_print_build()
	_print_frame("d%s" % String.num(CAMERA_DISTANCES[_camera_index], 1), _samples)
	_camera_index += 1
	if _camera_index < CAMERA_DISTANCES.size():
		_begin_settle()
		return
	_phase = Phase.PAN
	_samples.clear()
	_last_usec = 0
	_pan_start_usec = Time.get_ticks_usec()
	_rig.set_view(_pan_point(0.0), 0.0, PAN_DISTANCE)
	_map_view.set_camera_distance(PAN_DISTANCE)


## West-to-east sweep along the middle of the map, a 10 s round trip.
func _pan_point(progress: float) -> Vector2:
	var t := 1.0 - absf(2.0 * progress - 1.0)
	return Vector2(lerpf(_bounds.position.x, _bounds.end.x, t), _center.y)


func _pan() -> void:
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_samples.append((now - _last_usec) / 1000.0)
	_last_usec = now
	var progress := (now - _pan_start_usec) / 1e6 / PAN_SECONDS
	if progress >= 1.0:
		_print_frame("pan", _samples)
		_phase = Phase.DONE
		_finished = true
		quit(0)
		return
	_rig.set_view(_pan_point(progress), 0.0, PAN_DISTANCE)
	_map_view.set_camera_target(_rig.target())


## Instances in every MultiMesh below the map view (trees, bushes, rocks, grass, ...).
func _count_instances(node: Node) -> int:
	var total := 0
	if node is MultiMeshInstance3D:
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null:
			total += (
				mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			)
	for child in node.get_children():
		total += _count_instances(child)
	return total


func _print_build() -> void:
	var video_before: float = _pending_build[3]
	var video_mb: float = (
		(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) - video_before) / 1048576.0
	)
	print(
		(
			"BUILD %d %d %.2f %.2f %.0f %.0f %d %d %d"
			% [
				_scale,
				_hexes,
				_pending_build[0],
				_pending_build[1],
				_pending_build[2],
				video_mb,
				_count_instances(_map_view),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			]
		)
	)
	_pending_build = []


func _print_frame(label: String, samples: Array[float]) -> void:
	var total := 0.0
	var worst := 0.0
	var slow := 0
	for ms in samples:
		total += ms
		worst = maxf(worst, ms)
		if ms > SLOW_FRAME_MS:
			slow += 1
	print(
		(
			"FRAME %d %s %.2f %.2f %d %d"
			% [_scale, label, total / maxf(samples.size(), 1), worst, samples.size(), slow]
		)
	)


func _fail(message: String, code: int) -> void:
	printerr("ERROR: %s" % message)
	_finished = true
	quit(code)
