extends RefCounted
## Frame cost breakdown of the battle scene (tools/perf.sh): after the baseline it switches one
## part of the picture off at a time (a node group, an effect, a viewport setting), times the
## frame without it and restores it. "Saves" in the printed table is what that part costs.
## Driven one frame at a time by tools/screenshot.gd (SCREENSHOT_PROFILE=1), vsync off and uncapped.
## The parts overlap (hidden trees also cast no shadows), so the rows do not add up to the frame.

const SETTLE_FRAMES := 24  # frames ignored after a switch (LOD fades, shadow atlas, pipelines)
const SAMPLE_FRAMES := 80

var _root: Window
var _battle: Node
var _cases: Array[Dictionary] = []
var _index := -1  # -1 = baseline
var _frame := 0
var _last_usec := 0
var _wall_usec := 0
var _gpu_ms := 0.0
var _cpu_ms := 0.0
var _undo: Array[Callable] = []
var _results: Array[Dictionary] = []
var _only := PackedStringArray()


## `only`: comma-separated parts of case names to run (empty or "1" = every case).
func _init(root: Window, battle: Node, only: String = "") -> void:
	_root = root
	_battle = battle
	_only = PackedStringArray() if only in ["", "1"] else only.to_lower().split(",", false)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_add_hide("grass", ["Grass"])
	_add_hide("trees (map + backdrop)", ["Trees"])
	_add_hide("bushes", ["Bushes", "BackdropBushes"])
	_add_hide("rocks", ["Rocks", "BackdropRocks"])
	_add_hide("backdrop ground", ["Backdrop"])
	_add_hide("backdrop canopy", ["BackdropCanopy"])
	_add_hide("water", ["Water"])
	_add_hide("terrain", ["Terrain"])
	_add_hide("units", ["Units"])
	_add_hide("HUD", ["HUD"])
	_cases.append({"name": "all shadows (sun)", "apply": _sun_shadows_off})
	_cases.append({"name": "tree shadows", "apply": _shadows_off.bind("Trees")})
	_cases.append({"name": "unit shadows", "apply": _shadows_off.bind("Units")})
	_cases.append({"name": "terrain shadow casting", "apply": _shadows_off.bind("Terrain")})
	for property: String in ["ssao_enabled", "ssil_enabled", "glow_enabled", "fog_enabled"]:
		_cases.append(
			{"name": property.trim_suffix("_enabled"), "apply": _environment_off.bind(property)}
		)
	_cases.append({"name": "MSAA 4x -> off", "apply": _msaa_off})
	_cases.append({"name": "(3D at half resolution)", "apply": _half_resolution})
	_cases.append({"name": "(3D hidden: HUD + fixed cost)", "apply": _hide_3d})
	if not _only.is_empty():
		_cases = _cases.filter(_is_wanted)


## Advances the profile by one rendered frame; true once the table has been printed.
func step() -> bool:
	var now := Time.get_ticks_usec()
	_frame += 1
	if _frame > SETTLE_FRAMES + 1:
		var rid := _root.get_viewport_rid()
		_wall_usec += now - _last_usec
		_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_last_usec = now
	if _frame < SETTLE_FRAMES + 1 + SAMPLE_FRAMES:
		return false
	(
		_results
		. append(
			{
				"name": "baseline" if _index < 0 else String(_cases[_index]["name"]),
				"frame_ms": _wall_usec / 1000.0 / SAMPLE_FRAMES,
				"gpu_ms": _gpu_ms / SAMPLE_FRAMES,
				"cpu_ms": _cpu_ms / SAMPLE_FRAMES,
				"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				"tris": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			}
		)
	)
	for undo in _undo:
		undo.call()
	_undo.clear()
	_index += 1
	_frame = 0
	_wall_usec = 0
	_gpu_ms = 0.0
	_cpu_ms = 0.0
	if _index >= _cases.size():
		_print_table()
		return true
	(_cases[_index]["apply"] as Callable).call()
	return false


func _is_wanted(case: Dictionary) -> bool:
	var case_name := String(case["name"]).to_lower()
	for part in _only:
		if case_name.contains(part.strip_edges()):
			return true
	return false


func _add_hide(case_name: String, node_names: Array[String]) -> void:
	_cases.append({"name": case_name, "apply": _hide.bind(node_names)})


func _hide(node_names: Array[String]) -> void:
	for node_name in node_names:
		var node := _battle.find_child(node_name, true, false)
		if node == null or not bool(node.get("visible")):
			continue
		node.set("visible", false)
		_undo.append(node.set.bind("visible", true))


func _shadows_off(node_name: String) -> void:
	var parent := _battle.find_child(node_name, true, false)
	if parent == null:
		return
	var nodes: Array[Node] = parent.find_children("*", "GeometryInstance3D", true, false)
	nodes.append(parent)
	for node in nodes:
		var geometry := node as GeometryInstance3D
		if (
			geometry == null
			or geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		):
			continue
		_undo.append(geometry.set.bind("cast_shadow", geometry.cast_shadow))
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _sun_shadows_off() -> void:
	var sun := _battle.find_child("Sun", true, false) as DirectionalLight3D
	if sun == null or not sun.shadow_enabled:
		return
	sun.shadow_enabled = false
	_undo.append(sun.set.bind("shadow_enabled", true))


func _environment_off(property: String) -> void:
	var holder := _battle.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if holder == null or holder.environment == null or not bool(holder.environment.get(property)):
		return
	holder.environment.set(property, false)
	_undo.append(holder.environment.set.bind(property, true))


func _msaa_off() -> void:
	_undo.append(_root.set.bind("msaa_3d", _root.msaa_3d))
	_root.msaa_3d = Viewport.MSAA_DISABLED


func _half_resolution() -> void:
	_undo.append(_root.set.bind("scaling_3d_scale", _root.scaling_3d_scale))
	_root.scaling_3d_scale = 0.5


func _hide_3d() -> void:
	_undo.append(_root.set.bind("disable_3d", _root.disable_3d))
	_root.disable_3d = true


func _print_table() -> void:
	var base := _results[0]
	print("Frame cost breakdown (%d frames each, vsync off):" % SAMPLE_FRAMES)
	print(
		(
			"  %-32s %8.2f ms  GPU %6.2f  CPU %5.2f  %5d draws  %5d k tris"
			% [
				"baseline",
				base["frame_ms"],
				base["gpu_ms"],
				base["cpu_ms"],
				base["draws"],
				int(base["tris"]) / 1000,
			]
		)
	)
	var rows := _results.slice(1)
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["frame_ms"] < b["frame_ms"]
	)
	for row in rows:
		print(
			(
				"  without %-24s %8.2f ms  saves %6.2f ms  %5d draws  %5d k tris"
				% [
					row["name"],
					row["frame_ms"],
					float(base["frame_ms"]) - float(row["frame_ms"]),
					int(base["draws"]) - int(row["draws"]),
					(int(base["tris"]) - int(row["tris"])) / 1000,
				]
			)
		)
