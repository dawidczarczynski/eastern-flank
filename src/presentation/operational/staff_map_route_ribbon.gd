class_name StaffMapRouteRibbon
extends Node3D
## The route preview line (TASK-092c): a screen-space ribbon (constant pixel width under zoom and
## tilt, shader staff_map_line) lying on the relief, with a dark casing under it. Rebuilt only when
## the previewed route changes. The line comes in three looks (TASK-153): SOLID (advance, defend),
## DASHED (march: screen-pixel dashes that flow while `set_flowing(true)`) and RAIL (attack: a
## double line, the core hollowed in the shader); one ribbon can hold all three at once (the issued
## orders of many formations).

enum Kind { SOLID, DASHED, RAIL }

const LINE_PX := 3.0
const CASING_PX := 5.6
const RAIL_PX := 6.0
const RAIL_CASING_PX := 8.0
const RAIL_CORE_PX := 2.2
const DASH_ON_PX := 10.0
const DASH_OFF_PX := 7.0
const FLOW_PX_PER_SEC := 19.0  # 17 px per 0.9 s as in the mockup
const PRIORITY := 15

var _layers := {}  # Kind -> {casing: MeshInstance3D, line: MeshInstance3D}
var _vertex_count := 0
var _flow := 0.0
var _px_per_unit := 1.0
var _opacity := 1.0
var _kinds_shown: Array[int] = []


## The ribbon look of a StaffMapRoute.style().
static func kind_of(style: Dictionary) -> Kind:
	if style.get("rail", false):
		return Kind.RAIL
	return Kind.DASHED if style.get("dashed", false) else Kind.SOLID


func _init(p_name := "RouteRibbon") -> void:
	name = p_name
	for kind in Kind.values():
		_layers[kind] = _layer(kind)
	hide()
	set_process(false)


func _process(delta: float) -> void:
	_flow = fmod(_flow + FLOW_PX_PER_SEC * delta, DASH_ON_PX + DASH_OFF_PX)
	_each_material(func(m: ShaderMaterial) -> void: m.set_shader_parameter(&"flow_px", _flow))


## HDR gain of the line colour (the casing stays dark): above 1.0 the bloom makes it glow.
func set_glow(gain: float) -> void:
	for layer: Dictionary in _layers.values():
		(
			((layer["line"] as MeshInstance3D).material_override as ShaderMaterial)
			. set_shader_parameter(&"glow", gain)
		)


## A thin, faint variant (the alternative-posture line): the line `width_px` wide, its casing a
## little wider.
func set_thin(width_px: float) -> void:
	for layer: Dictionary in _layers.values():
		var line := (layer["line"] as MeshInstance3D).material_override as ShaderMaterial
		var casing := (layer["casing"] as MeshInstance3D).material_override as ShaderMaterial
		line.set_shader_parameter(&"width_px", width_px)
		casing.set_shader_parameter(&"width_px", width_px + 1.4)


## Screen pixels per map unit along the ground (the dash pitch stays constant on screen).
func set_scale_px(px_per_unit: float) -> void:
	_px_per_unit = px_per_unit
	_each_material(
		func(m: ShaderMaterial) -> void: m.set_shader_parameter(&"px_per_unit", px_per_unit)
	)


## The dashes flow along the line (only while aiming); false stops them where they are.
func set_flowing(flowing: bool) -> void:
	set_process(flowing)


func is_flowing() -> bool:
	return is_processing()


## Line and casing opacity 0 … 1 (the commit settle).
func set_opacity(opacity: float) -> void:
	_opacity = opacity
	_each_material(func(m: ShaderMaterial) -> void: m.set_shader_parameter(&"opacity", opacity))


## Shows the line through `points` (3D, already on the relief) in `colour`.
func show_line(points: PackedVector3Array, colour: Color) -> void:
	show_lines([points], colour)


## Shows several polylines (the orders of many formations) as one mesh in the look `kind`;
## `opacity` 0 … 1 fades line and casing together.
func show_lines(lines: Array, colour: Color, opacity := 1.0, kind := Kind.SOLID) -> void:
	show_groups({kind: lines}, colour, opacity)


## Shows polylines grouped by look: `groups` = {Kind: Array of PackedVector3Array}.
func show_groups(groups: Dictionary, colour: Color, opacity := 1.0) -> void:
	_vertex_count = 0
	_kinds_shown = []
	for kind: int in _layers:
		var layer: Dictionary = _layers[kind]
		var lines: Array = groups.get(kind, [])
		var mesh := StaffMapLines.polylines_mesh(lines) if not lines.is_empty() else null
		(layer["casing"] as MeshInstance3D).mesh = mesh
		(layer["line"] as MeshInstance3D).mesh = mesh
		if mesh != null:
			_kinds_shown.append(kind)
		for line: PackedVector3Array in lines:
			_vertex_count += line.size()
	set_opacity(opacity)
	for layer: Dictionary in _layers.values():
		var material := (layer["line"] as MeshInstance3D).material_override as ShaderMaterial
		material.set_shader_parameter(&"line_color", colour)
	show()


func clear() -> void:
	_vertex_count = 0
	_kinds_shown = []
	hide()
	set_process(false)


func point_count() -> int:
	return _vertex_count if visible else 0


## The looks that have lines now (tests).
func kinds_shown() -> Array[int]:
	return _kinds_shown


## Shader parameter `param` (a float) of the line material of `kind`; 0 when it is not set (tests).
func line_parameter(kind: int, param: StringName) -> float:
	var layer: Dictionary = _layers[kind]
	var material := (layer["line"] as MeshInstance3D).material_override as ShaderMaterial
	var value: Variant = material.get_shader_parameter(param)
	return float(value) if value != null else 0.0


func _each_material(apply: Callable) -> void:
	for layer: Dictionary in _layers.values():
		for node: String in ["casing", "line"]:
			apply.call((layer[node] as MeshInstance3D).material_override as ShaderMaterial)


func _layer(kind: int) -> Dictionary:
	var width := RAIL_PX if kind == Kind.RAIL else LINE_PX
	var casing_width := RAIL_CASING_PX if kind == Kind.RAIL else CASING_PX
	var casing := _node("Casing%d" % kind, Color(0.05, 0.06, 0.05, 0.85), casing_width, PRIORITY)
	var line := _node("Line%d" % kind, Color.WHITE, width, PRIORITY + 1)
	for node: MeshInstance3D in [casing, line]:
		var material := node.material_override as ShaderMaterial
		if kind == Kind.DASHED:
			material.set_shader_parameter(&"dash_on_px", DASH_ON_PX)
			material.set_shader_parameter(&"dash_off_px", DASH_OFF_PX)
	(line.material_override as ShaderMaterial).set_shader_parameter(
		&"hollow_px", RAIL_CORE_PX if kind == Kind.RAIL else 0.0
	)
	return {"casing": casing, "line": line}


func _node(node_name: String, colour: Color, width: float, priority: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.material_override = StaffMapLines.material(colour, width, priority)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 16384.0
	add_child(node)
	return node
