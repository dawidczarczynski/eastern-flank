extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

var _view: MapView


func before_each() -> void:
	_view = MapView.new()
	# Not in a scene tree in tests, so run the setup _ready() would do.
	_view._ready()
	_view.build(Fixtures.plains_grid(1))


func after_each() -> void:
	_view.free()


func _surface_mesh(node_name: String) -> ArrayMesh:
	var instance := _view._tiles_root.get_node(node_name) as MeshInstance3D
	return instance.mesh as ArrayMesh


func test_terrain_mesh_has_uvs_scaled_by_detail_tile() -> void:
	var arrays := _surface_mesh("Terrain").surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_true(uvs.size() > 0 and uvs.size() == vertices.size(), "one UV per vertex")
	var v := vertices[7]
	assert_true(uvs[7].is_equal_approx(Vector2(v.x, v.z) / MapView.DETAIL_TILE))


func test_terrain_material_has_detail_textures() -> void:
	var material := _surface_mesh("Terrain").surface_get_material(0) as StandardMaterial3D
	assert_true(material.albedo_texture != null, "albedo texture")
	assert_true(material.normal_enabled and material.normal_texture != null, "normal texture")
	assert_eq(
		material.texture_filter, BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	)


func test_water_has_normal_map() -> void:
	var plane := _view._tiles_root.get_node("Water") as MeshInstance3D
	var material := plane.mesh.material as StandardMaterial3D
	assert_true(material.normal_enabled and material.normal_texture != null)
	assert_true(is_equal_approx(material.normal_scale, 0.3))


func test_terrain_has_tangents_perpendicular_to_normals() -> void:
	var arrays := _surface_mesh("Terrain").surface_get_arrays(0)
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_eq(tangents.size(), normals.size() * 4)
	for i in [0, 7, normals.size() / 2, normals.size() - 1]:
		var t := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
		assert_true(absf(t.length() - 1.0) < 1e-4, "unit tangent")
		assert_true(absf(t.dot(normals[i])) < 1e-4, "tangent perpendicular to normal")
		assert_true(t.x > 0.5, "tangent points along +x")
		# Binormal = cross(normal, tangent) * w must be the -z side (up the normal map image).
		var binormal := normals[i].cross(t) * tangents[i * 4 + 3]
		assert_true(binormal.z < -0.5, "binormal points along -z")
