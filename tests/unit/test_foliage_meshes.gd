extends TestCase

const DECIDUOUS_HALF_WIDTH := 0.13
const DECIDUOUS_Y := Vector2(0.05, 0.27)
const CONIFER_Y := Vector2(0.08, 0.36)
const OUTWARD_SHARE := 0.95
const COLOR_RANGE := Vector2(0.35, 1.15)
const EPSILON := 1e-3


func _arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0)


func _verts(mesh: ArrayMesh) -> PackedVector3Array:
	return _arrays(mesh)[Mesh.ARRAY_VERTEX]


func _check_crown(mesh: ArrayMesh, center_y: float, y_range: Vector2, half_width: float) -> void:
	var arrays := _arrays(mesh)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_true(verts.size() > 0)
	assert_eq(normals.size(), verts.size())
	assert_eq(colors.size(), verts.size())
	var outward := 0
	var low_sum := 0.0
	var low_n := 0
	var high_sum := 0.0
	var high_n := 0
	for i in verts.size():
		var v := verts[i]
		assert_true(absf(v.x) <= half_width and absf(v.z) <= half_width)
		assert_true(v.y >= y_range.x - EPSILON and v.y <= y_range.y + EPSILON)
		assert_true(absf(normals[i].length() - 1.0) < EPSILON)
		if normals[i].dot(v - Vector3(0.0, center_y, 0.0)) > 0.0:
			outward += 1
		var c := colors[i]
		for channel in [c.r, c.g, c.b]:
			assert_true(channel >= COLOR_RANGE.x and channel <= COLOR_RANGE.y)
		var brightness := (c.r + c.g + c.b) / 3.0
		if v.y < 0.1:
			low_sum += brightness
			low_n += 1
		elif v.y > 0.2:
			high_sum += brightness
			high_n += 1
	assert_true(float(outward) / verts.size() >= OUTWARD_SHARE)
	assert_true(low_n > 0 and high_n > 0)
	assert_true(low_sum / low_n < high_sum / high_n)


func test_deciduous_crown_bounds_normals_and_ao() -> void:
	for variant in [0, 1]:
		_check_crown(FoliageMeshes.deciduous(variant), 0.15, DECIDUOUS_Y, DECIDUOUS_HALF_WIDTH)


func test_conifer_crown_bounds_normals_and_ao() -> void:
	for variant in [0, 1]:
		_check_crown(FoliageMeshes.conifer(variant), 0.16, CONIFER_Y, 0.13)


func test_meshes_are_deterministic_and_variants_differ() -> void:
	var a := _verts(FoliageMeshes.build_deciduous(0))
	var b := _verts(FoliageMeshes.build_deciduous(0))
	var other := _verts(FoliageMeshes.build_deciduous(1))
	assert_eq(a, b)
	assert_true(a != other)
	var ca := _verts(FoliageMeshes.build_conifer(0))
	var cb := _verts(FoliageMeshes.build_conifer(0))
	var cother := _verts(FoliageMeshes.build_conifer(1))
	assert_eq(ca, cb)
	assert_true(ca != cother)


func test_cache_returns_same_instance_and_bush_is_variant_three() -> void:
	var first := FoliageMeshes.deciduous(0)
	assert_true(first == FoliageMeshes.deciduous(0))
	assert_true(FoliageMeshes.bush() == FoliageMeshes.deciduous(3))


func test_crowns_wind_front_faces_along_their_normals() -> void:
	# Godot front faces are clockwise, so the right-handed cross product points against the
	# outward normal of a correctly wound triangle.
	for mesh in [FoliageMeshes.deciduous(0), FoliageMeshes.conifer(0)]:
		var arrays := _arrays(mesh)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var facing := 0
		for i in range(0, verts.size(), 3):
			var n := (verts[i + 1] - verts[i]).cross(verts[i + 2] - verts[i])
			if n.dot(normals[i] + normals[i + 1] + normals[i + 2]) < 0.0:
				facing += 1
		assert_true(float(facing) / (verts.size() / 3) >= OUTWARD_SHARE)


func test_trunk_and_rock_shapes() -> void:
	var trunk: PackedVector3Array = _arrays(FoliageMeshes.trunk())[Mesh.ARRAY_VERTEX]
	assert_true(trunk.size() > 0)
	var max_y := 0.0
	for v in trunk:
		assert_true(v.y >= -EPSILON)
		max_y = maxf(max_y, v.y)
	assert_true(absf(max_y - 0.12) < EPSILON)
	var rock: PackedVector3Array = _arrays(FoliageMeshes.rock())[Mesh.ARRAY_VERTEX]
	assert_eq(rock.size(), 20 * 4 * 3)
	for v in rock:
		assert_true(v.length() >= 0.05 * 0.75 - EPSILON and v.length() <= 0.05 * 1.25 + EPSILON)
