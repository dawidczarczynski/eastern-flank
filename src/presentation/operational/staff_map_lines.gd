class_name StaffMapLines
extends RefCounted
## Mesh building for the staff map's screen-space lines (TASK-125, assets/shaders/
## staff_map_line.gdshader): one quad per segment whose vertices carry the previous and next
## point, so the shader can give the line a constant pixel width and mitred joints under any zoom
## and pitch. A whole line class is one mesh, built once.

const SHADER := preload("res://assets/shaders/staff_map_line.gdshader")


## Mesh of separate `segments` (3D end points in pairs), each a two-point polyline.
static func segments_mesh(segments: PackedVector3Array) -> ArrayMesh:
	var lines: Array = []
	for i in range(0, segments.size() - 1, 2):
		lines.append(PackedVector3Array([segments[i], segments[i + 1]]))
	return polylines_mesh(lines)


## Mesh of `lines` (Array of PackedVector3Array): a quad per segment, joints mitred in the shader.
static func polylines_mesh(lines: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var previous := PackedFloat32Array()
	var following := PackedFloat32Array()
	var uvs := PackedVector2Array()
	for raw: PackedVector3Array in lines:
		var line := _without_repeats(raw)
		var n := line.size()
		for i in n - 1:
			# Quad (i, +) (i, -) (i+1, +) / (i+1, +) (i, -) (i+1, -).
			for corner: Array in [
				[i, 1.0], [i, -1.0], [i + 1, 1.0], [i + 1, 1.0], [i, -1.0], [i + 1, -1.0]
			]:
				var k: int = corner[0]
				var before := line[k - 1] if k > 0 else line[k]
				var after := line[k + 1] if k < n - 1 else line[k]
				vertices.append(line[k])
				previous.append_array([before.x, before.y, before.z])
				following.append_array([after.x, after.y, after.z])
				uvs.append(Vector2(corner[1], 0.0))
	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = previous
	arrays[Mesh.ARRAY_CUSTOM1] = following
	var format := (
		(Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		| (Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
	return mesh


## A line material: colour, width in pixels, layer order (higher draws later).
static func material(colour: Color, width_px: float, priority: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = priority
	m.set_shader_parameter(&"line_color", colour)
	m.set_shader_parameter(&"width_px", width_px)
	m.set_shader_parameter(&"opacity", 1.0)
	return m


## Consecutive duplicate points removed (they would make a zero-length segment).
static func _without_repeats(line: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in line:
		if out.is_empty() or not out[out.size() - 1].is_equal_approx(p):
			out.append(p)
	return out
