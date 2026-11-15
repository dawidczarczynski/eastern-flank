class_name StaffMapControlLayer
extends Node3D
## The terrain control layer of the staff map (TASK-152, docs/design/operational_map/
## terrain_control.html variant A, contour dropped after the playtest 2026-11-14): hexes held by a
## side other than their country's original one get the holder colour as a fill with a 45 degree
## hatch (6 px pitch, 2 px lines, 30 %). The fill is 10 % (22 % zoomed out, toned down for
## the dark glow look); the hatch fades in at Z1. Sits under counters, orders and the front line,
## ignores the mouse, read-only (rule 3).
##
## Work happens only when something changed: `refresh` compares a signature of the holders, the
## viewer and the visibility, `set_view` the zoom level – never per frame.

const FILL_ALPHA := 0.10
const FAR_FILL_ALPHA := 0.22
const PRIORITY_FILL := 13
const SHADER := preload("res://assets/shaders/staff_map_control.gdshader")

var _relief: StaffMapRelief
var _palette: StaffMapPalette
var _fill: MeshInstance3D
var _occupied: Dictionary = {}
var _signature := ""
var _level := 1
var _enabled := true
var _shown := true
var _rebuilds := 0


func _init(relief: StaffMapRelief, palette: StaffMapPalette) -> void:
	name = "TerrainControl"
	_relief = relief
	_palette = palette
	_fill = _node("Fill")
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = PRIORITY_FILL
	_fill.material_override = material


## Recomputes the layer from `state` when the holders, the viewer or `shown` changed since the
## last call; otherwise does nothing. `shown` is false while the counters slide.
func refresh(state: OperationalState, viewer: int, shown := true) -> void:
	var signature := "%d|%d|%s" % [TerrainControl.signature(state), viewer, shown]
	if signature == _signature:
		return
	_signature = signature
	_shown = shown
	_apply_visibility()
	if not shown:
		return
	_rebuilds += 1
	_occupied = TerrainControl.occupied(state)
	_fill.mesh = _fill_mesh()


## Camera state: the zoom level 0 … 2 (Z0 has no hatch and a stronger fill).
func set_view(level: int) -> void:
	_level = level
	var far := level == 0
	var fill := _fill.material_override as ShaderMaterial
	fill.set_shader_parameter(&"hatch", 0.0 if far else 1.0)
	fill.set_shader_parameter(&"fill_alpha", FAR_FILL_ALPHA if far else FILL_ALPHA)


## The player's toggle (key K, Map options).
func set_enabled(value: bool) -> void:
	_enabled = value
	_apply_visibility()


func is_enabled() -> bool:
	return _enabled


## Number of recomputations so far (tests: nothing recomputes without a change).
func rebuild_count() -> int:
	return _rebuilds


## Hex -> holder drawn by the last refresh (tests).
func occupied() -> Dictionary:
	return _occupied


## Whether the hatch lines are drawn at the current zoom level (Z1 and Z2).
func hatch_visible() -> bool:
	return _level > 0


func _apply_visibility() -> void:
	visible = _enabled and _shown


func _fill_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	var hexes: Array = _occupied.keys()
	hexes.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	for hex: Vector2i in hexes:
		var colour := StaffMapFormations.side_colour(_palette, _occupied[hex] as int)
		var centre := Hex.to_world(hex, 1.0)
		var middle := Vector2(centre.x, centre.z)
		for k in 6:
			for point: Vector2 in [middle, middle + _corner(k), middle + _corner(k + 1)]:
				vertices.append(_relief.surface_point(point))
				colours.append(colour)
	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _corner(k: int) -> Vector2:
	var angle := PI / 6.0 + k * PI / 3.0
	return Vector2(cos(angle), sin(angle))


func _node(node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 16384.0
	add_child(node)
	return node
