class_name StaffMapRouteRibbon
extends Node3D
## The route preview line (TASK-092c): a screen-space ribbon (constant pixel width under zoom and
## tilt, shader staff_map_line) lying on the relief, with a dark casing under it. Rebuilt only when
## the previewed route changes.

const LINE_PX := 3.0
const CASING_PX := 5.6
const PRIORITY := 15

var _casing: MeshInstance3D
var _line: MeshInstance3D
var _vertex_count := 0


func _init(p_name := "RouteRibbon") -> void:
	name = p_name
	_casing = _node("Casing", Color(0.05, 0.06, 0.05, 0.85), CASING_PX, PRIORITY)
	_line = _node("Line", Color.WHITE, LINE_PX, PRIORITY + 1)
	hide()


## Shows the line through `points` (3D, already on the relief) in `colour`.
func show_line(points: PackedVector3Array, colour: Color) -> void:
	show_lines([points], colour)


## Shows several polylines (dashes, or the orders of many formations) as one mesh; `opacity`
## 0 … 1 fades line and casing together.
func show_lines(lines: Array, colour: Color, opacity := 1.0) -> void:
	var mesh := StaffMapLines.polylines_mesh(lines)
	_casing.mesh = mesh
	_line.mesh = mesh
	(_line.material_override as ShaderMaterial).set_shader_parameter(&"line_color", colour)
	for node in [_casing, _line]:
		((node as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter(
			&"opacity", opacity
		)
	_vertex_count = 0
	for line: PackedVector3Array in lines:
		_vertex_count += line.size()
	show()


func clear() -> void:
	_vertex_count = 0
	hide()


func point_count() -> int:
	return _vertex_count if visible else 0


func _node(node_name: String, colour: Color, width: float, priority: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.material_override = StaffMapLines.material(colour, width, priority)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 16384.0
	add_child(node)
	return node
