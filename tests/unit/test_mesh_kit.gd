# gdlint: disable=max-public-methods
extends TestCase
## MeshKit / MeshKits (TASK-030): chamfered and smooth primitives, winding, normals, the RGB vertex
## masks (r = edge, g = openness, b = per-part tint seed) and the per-material instances.

const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const EPSILON := 1e-5
const NORMAL_EPSILON := 1e-4
const MAX_TWIST_DEG := 1.0
## Vertex colours are stored as 8-bit channels.
const COLOR_EPSILON := 1.0 / 255.0
const PRIMITIVES: Array[String] = [
	"tri",
	"poly",
	"poly_auto",
	"cbox",
	"pillow",
	"lathe",
	"lathe_flat",
	"rod",
	"bolt",
	"stack",
	"loft",
	"plate",
	"profile",
	"sweep",
	"sweep_pointed",
	"tube",
]
const CLOSED: Array[String] = [
	"cbox",
	"pillow",
	"lathe",
	"lathe_flat",
	"rod",
	"stack",
	"loft",
	"plate",
	"profile",
	"sweep",
	"sweep_pointed",
	"tube",
]
const CONVEX: Array[String] = ["cbox", "pillow", "lathe", "rod", "stack", "loft"]


func _arrays(mesh: ArrayMesh) -> Array:
	return mesh.surface_get_arrays(0)


func _verts(mesh: ArrayMesh) -> PackedVector3Array:
	return _arrays(mesh)[Mesh.ARRAY_VERTEX]


func _normals(mesh: ArrayMesh) -> PackedVector3Array:
	return _arrays(mesh)[Mesh.ARRAY_NORMAL]


func _colors(mesh: ArrayMesh) -> PackedColorArray:
	return _arrays(mesh)[Mesh.ARRAY_COLOR]


func _aabb(mesh: ArrayMesh) -> AABB:
	var verts := _verts(mesh)
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return box


func _assert_aabb(mesh: ArrayMesh, expected: AABB, label: String) -> void:
	var box := _aabb(mesh)
	var ok := (
		box.position.distance_to(expected.position) < EPSILON
		and box.end.distance_to(expected.end) < EPSILON
	)
	assert_true(ok, "%s: AABB %s, expected %s" % [label, box, expected])


## Every triangle: (v2 - v0) x (v1 - v0) agrees with all three vertex normals (Godot front faces
## are clockwise seen from outside); normals unit length; one colour per vertex, channels in 0..1.
func _assert_well_formed(mesh: ArrayMesh, label: String) -> void:
	var verts := _verts(mesh)
	var normals := _normals(mesh)
	var colors := _colors(mesh)
	assert_true(verts.size() > 0 and verts.size() % 3 == 0, "%s: triangle list" % label)
	assert_eq(normals.size(), verts.size(), label)
	assert_eq(colors.size(), verts.size(), label)
	var bad_winding := 0
	var bad_normal := 0
	var bad_color := 0
	for t in range(0, verts.size(), 3):
		var face := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t])
		for k in 3:
			var n := normals[t + k]
			if absf(n.length() - 1.0) > NORMAL_EPSILON:
				bad_normal += 1
			if face.dot(n) <= 0.0:
				bad_winding += 1
			var c := colors[t + k]
			for channel: float in [c.r, c.g, c.b]:
				if channel < 0.0 or channel > 1.0:
					bad_color += 1
	assert_eq(bad_winding, 0, "%s: vertices against the winding" % label)
	assert_eq(bad_normal, 0, "%s: non-unit normals" % label)
	assert_eq(bad_color, 0, "%s: colour channels outside 0..1" % label)


## Watertight and consistently oriented: every directed edge (by position) appears exactly once
## and its reverse exactly once.
func _assert_closed(mesh: ArrayMesh, label: String) -> void:
	var verts := _verts(mesh)
	var ids := {}
	var vid := PackedInt32Array()
	for v in verts:
		var key := Vector3i(roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5))
		if not ids.has(key):
			ids[key] = ids.size()
		vid.append(ids[key])
	var edges := {}
	for t in range(0, verts.size(), 3):
		for k in 3:
			var edge := Vector2i(vid[t + k], vid[t + (k + 1) % 3])
			edges[edge] = int(edges.get(edge, 0)) + 1
	var open := 0
	for edge: Vector2i in edges:
		if edges[edge] != 1 or edges.get(Vector2i(edge.y, edge.x), 0) != 1:
			open += 1
	assert_eq(open, 0, "%s: open or non-manifold edges" % label)


func _l_path() -> Array:
	return [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.5, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.5),
		Vector3(1.0, 0.0, 1.0),
	]


func _constant_radii(path: Array, r: float) -> Array:
	var radii := []
	for p: Vector3 in path:
		radii.append(Vector2(r, r))
	return radii


## Adds one part made by the primitive `name` to `k`.
func _build(k: MeshKit, name: String) -> void:
	var tilt := Basis(Vector3(1.0, 2.0, 0.5).normalized(), 0.7)
	var square := [Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]
	match name:
		"tri":
			var up := Vector3.UP
			k.tri(Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 1), up, up, up)
		"poly":
			k.poly(square, Vector3.DOWN)
		"poly_auto":
			k.poly_auto(square, Vector3(0.5, 1.0, 0.5))
		"cbox":
			k.cbox(Vector3(0.1, 0.2, 0.3), Vector3(0.4, 0.2, 0.3), 0.03, tilt)
		"pillow":
			k.pillow(Vector3.ZERO, Vector3(0.3, 0.2, 0.4), tilt, 0.35)
		"lathe":
			var prof := [
				Vector2(0.0, 0.2),
				Vector2(0.1, 0.2),
				Vector2(0.12, 0.18),
				Vector2(0.12, -0.2),
				Vector2(0.0, -0.2),
			]
			k.lathe(Vector3.ZERO, tilt, prof, 12)
		"lathe_flat":
			var prof := [Vector2(0, 0.1), Vector2(0.1, 0.1), Vector2(0.1, 0.0), Vector2(0, 0)]
			k.lathe(Vector3.ZERO, Basis.IDENTITY, prof, 8, false)
		"rod":
			k.rod(Vector3(1, 0, 0), Vector3(1, 1, 0), 0.05, 0.5, 12, 0.01)
		"bolt":
			k.bolt(Vector3.ZERO, Vector3.BACK)
		"stack":
			var top := [
				Vector3(0.1, 1, 0.1),
				Vector3(0.9, 1, 0.1),
				Vector3(0.9, 1, 0.9),
				Vector3(0.1, 1, 0.9),
			]
			k.stack([square, top], [1.0])
		"loft":
			var bottom := [Vector2(0, -1), Vector2(2, -1), Vector2(2, 1), Vector2(0, 1)]
			var top := [
				Vector2(0.3, -0.8),
				Vector2(1.7, -0.8),
				Vector2(1.7, 0.8),
				Vector2(0.3, 0.8),
			]
			k.loft(bottom, top, 0.0, 0.6, 0.05)
		"plate":
			# Non-convex L outline.
			var outline := [
				Vector2(0, 0),
				Vector2(1, 0),
				Vector2(1, 0.3),
				Vector2(0.3, 0.3),
				Vector2(0.3, 1),
				Vector2(0, 1),
			]
			var o := Vector3(0.5, 0, 0)
			k.plate(outline, o, Vector3.RIGHT, Vector3.UP, Vector3.BACK, -0.05, 0.05, 0.02)
		"profile":
			var side := [Vector2(0, 0.5), Vector2(0.5, 1), Vector2(3, 1), Vector2(3, 0.5)]
			k.profile(side, 0.8, 0.0, 0.03)
		"sweep":
			var radii := [
				Vector2(0.1, 0.05),
				Vector2(0.1, 0.06),
				Vector2(0.1, 0.07),
				Vector2(0.08, 0.05),
				Vector2(0.06, 0.04),
			]
			k.sweep(_l_path(), radii)
		"sweep_pointed":
			var path := [
				Vector3.ZERO,
				Vector3(0, 0.2, 0),
				Vector3(0, 0.8, 0.1),
				Vector3(0, 1, 0.1),
			]
			var radii := [Vector2.ZERO, Vector2(0.1, 0.1), Vector2(0.08, 0.06), Vector2.ZERO]
			k.sweep(path, radii, 10)
		"tube":
			k.tube(_l_path(), 0.04, 8)
		_:
			_fail("unknown primitive %s" % name)


func _single(name: String) -> ArrayMesh:
	var kit := MeshKit.new()
	_build(kit, name)
	return kit.commit()


func test_cbox_without_chamfer_is_twelve_triangles_of_the_given_size() -> void:
	var size := Vector3(0.1, 0.05, 0.2)
	var kit := MeshKit.new()
	kit.cbox(Vector3.ZERO, size, 0.0)
	assert_eq(kit.count, 12)
	var mesh := kit.commit()
	assert_eq(_verts(mesh).size(), 36)
	_assert_aabb(mesh, AABB(-size / 2.0, size), "sharp cbox")
	for c in _colors(mesh):
		assert_eq(c.r, 0.0, "a sharp box has no edge flags")


func test_chamfered_cbox_keeps_its_size_and_flags_the_chamfers() -> void:
	var size := Vector3(0.1, 0.05, 0.2)
	var kit := MeshKit.new()
	kit.cbox(Vector3.ZERO, size, 0.01)
	assert_true(kit.count > 12, "chamfer bands and corners add triangles")
	var mesh := kit.commit()
	_assert_aabb(mesh, AABB(-size / 2.0, size), "chamfered cbox")
	var edge := 0
	var face := 0
	for c in _colors(mesh):
		if c.r == 1.0:
			edge += 1
		elif c.r == 0.0:
			face += 1
	assert_true(edge > 0, "chamfer vertices have r == 1")
	assert_true(face > 0, "face vertices have r == 0")
	assert_eq(edge + face, _verts(mesh).size(), "r is either 0 or 1")


func test_every_primitive_winds_clockwise_with_unit_normals() -> void:
	for name in PRIMITIVES:
		_assert_well_formed(_single(name), name)


func test_solid_primitives_are_closed() -> void:
	for name in CLOSED:
		_assert_closed(_single(name), name)


func test_convex_primitives_face_outwards() -> void:
	for name in CONVEX:
		var mesh := _single(name)
		var verts := _verts(mesh)
		var normals := _normals(mesh)
		var centre := _aabb(mesh).get_center()
		var inward := 0
		for i in verts.size():
			if normals[i].dot(verts[i] - centre) <= 0.0:
				inward += 1
		assert_eq(inward, 0, "%s: normals pointing inwards" % name)


func test_pillow_with_exponent_one_is_an_ellipsoid() -> void:
	var size := Vector3(0.4, 0.2, 0.3)
	var kit := MeshKit.new()
	kit.pillow(Vector3.ZERO, size, Basis.IDENTITY, 1.0, 10, 16)
	var mesh := kit.commit()
	var h := size / 2.0
	var worst := 0.0
	for v in _verts(mesh):
		var r := Vector3(v.x / h.x, v.y / h.y, v.z / h.z).length()
		worst = maxf(worst, absf(r - 1.0))
	assert_true(worst < 0.02, "vertices within 2 %% of the ellipsoid (worst %f)" % worst)
	_assert_aabb(mesh, AABB(-h, size), "ellipsoid pillow")


func test_boxy_pillow_fills_its_size() -> void:
	var size := Vector3(0.5, 0.1, 0.3)
	var c := Vector3(1.0, 2.0, 3.0)
	var kit := MeshKit.new()
	kit.pillow(c, size, Basis.IDENTITY, 0.3)
	_assert_aabb(kit.commit(), AABB(c - size / 2.0, size), "boxy pillow")


func test_sweep_rings_are_perpendicular_to_the_path() -> void:
	var path := _l_path()
	var r := 0.1
	var kit := MeshKit.new()
	kit.sweep(path, _constant_radii(path, r), 8, Vector3.UP)
	var verts := _verts(kit.commit())
	# Ring tangents: the segment direction on the straight parts, the bisector at the corner.
	var tangents := [
		Vector3.RIGHT, Vector3.RIGHT, Vector3(1, 0, 1).normalized(), Vector3.BACK, Vector3.BACK
	]
	for i in path.size():
		var on_ring := 0
		var tilted := 0
		for v in verts:
			var offset: Vector3 = v - (path[i] as Vector3)
			if absf(offset.length() - r) > 1e-4:
				continue
			on_ring += 1
			if absf(offset.normalized().dot(tangents[i])) > 1e-3:
				tilted += 1
		assert_true(on_ring >= 8, "ring %d has its vertices (%d)" % [i, on_ring])
		assert_eq(tilted, 0, "ring %d is perpendicular to its tangent" % i)


func test_sweep_frames_do_not_twist() -> void:
	var path := _l_path()
	# Side axis normal to the bend plane: parallel transport keeps it fixed all along.
	var frames := MeshKit.sweep_frames(path, Vector3.UP)
	assert_eq(frames.size(), path.size())
	for i in frames.size():
		var t: Vector3 = frames[i][0]
		var side: Vector3 = frames[i][1]
		assert_true(absf(t.dot(side)) < 1e-5, "side axis normal to the tangent at %d" % i)
		assert_true(rad_to_deg(side.angle_to(Vector3.UP)) < MAX_TWIST_DEG, "no twist at %d" % i)
	# Side axis in the bend plane: it turns with the path, but not between rings on a straight part.
	frames = MeshKit.sweep_frames(path, Vector3.BACK)
	for pair: Vector2i in [Vector2i(0, 1), Vector2i(3, 4)]:
		var a: Vector3 = frames[pair.x][1]
		var b: Vector3 = frames[pair.y][1]
		assert_true(rad_to_deg(a.angle_to(b)) < MAX_TWIST_DEG, "no twist %s" % pair)
	var last: Vector3 = frames[4][1]
	assert_true(last.is_equal_approx(Vector3.LEFT), "carried around the bend: %s" % last)


func test_tube_is_closed_with_the_expected_bounds() -> void:
	var kit := MeshKit.new()
	kit.tube([Vector3(0, 0, 0), Vector3(0, 1, 0)], 0.1, 4)
	var mesh := kit.commit()
	_assert_closed(mesh, "tube")
	_assert_aabb(mesh, AABB(Vector3(-0.1, 0.0, -0.1), Vector3(0.2, 1.0, 0.2)), "tube")
	# Along the L: the first ring lies in x = 0, the last in z = 1, the legs are 0.1 thick.
	var bent := MeshKit.new()
	bent.tube(_l_path(), 0.05, 8)
	var bent_mesh := bent.commit()
	_assert_closed(bent_mesh, "L tube")
	_assert_aabb(bent_mesh, AABB(Vector3(0.0, -0.05, -0.05), Vector3(1.05, 0.1, 1.05)), "L tube")


func test_lathe_is_closed_where_the_profile_radius_is_zero() -> void:
	var prof := [
		Vector2(0.0, 0.3),
		Vector2(0.2, 0.3),
		Vector2(0.2, -0.1),
		Vector2(0.1, -0.3),
		Vector2(0.0, -0.3),
	]
	var kit := MeshKit.new()
	kit.lathe(Vector3.ZERO, Basis.IDENTITY, prof, 16)
	var mesh := kit.commit()
	_assert_closed(mesh, "lathe")
	_assert_aabb(mesh, AABB(Vector3(-0.2, -0.3, -0.2), Vector3(0.4, 0.6, 0.4)), "lathe")
	var sleeve := MeshKit.new()
	sleeve.lathe(Vector3.ZERO, Basis.IDENTITY, [Vector2(0.2, 0.3), Vector2(0.2, -0.3)], 16)
	assert_eq(sleeve.count, 16 * 2, "an open sleeve has no caps")


func test_lathe_inner_wall_is_a_cavity() -> void:
	# A cup: outer wall down, bottom, inner wall back up to the rim.
	var prof := [
		Vector2(0.2, 0.3),
		Vector2(0.2, -0.3),
		Vector2(0.0, -0.3),
		Vector2(0.0, -0.25),
		Vector2(0.15, -0.25),
		Vector2(0.15, 0.3),
		Vector2(0.2, 0.3),
	]
	var kit := MeshKit.new()
	kit.lathe(Vector3.ZERO, Basis.IDENTITY, prof, 12)
	var mesh := kit.commit()
	var normals := _normals(mesh)
	var verts := _verts(mesh)
	var colors := _colors(mesh)
	var inner := 0
	var outer := 0
	for i in verts.size():
		var radial := Vector3(verts[i].x, 0.0, verts[i].z)
		if radial.length() < 0.1 or absf(normals[i].y) > 0.5:
			continue
		if normals[i].dot(radial) < 0.0:
			inner += 1
			assert_true(colors[i].g < 0.5, "inner wall is darker")
		else:
			outer += 1
			assert_eq(colors[i].g, 1.0, "outer wall is open")
	assert_true(inner > 0 and outer > 0)


func test_lathe_flags_short_diagonal_segments_as_chamfers() -> void:
	var colors := _colors(_single("lathe"))
	var edge := 0
	for c in colors:
		if c.r == 1.0:
			edge += 1
	assert_true(edge > 0 and edge < colors.size())


func test_openness_is_written_to_green() -> void:
	var kit := MeshKit.new()
	kit.openness = 0.25
	kit.cbox(Vector3.ZERO, Vector3.ONE, 0.1)
	kit.openness = 1.0
	kit.cbox(Vector3(2, 0, 0), Vector3.ONE, 0.1)
	var mesh := kit.commit()
	var verts := _verts(mesh)
	var colors := _colors(mesh)
	var wrong := 0
	for i in verts.size():
		if absf(colors[i].g - (0.25 if verts[i].x < 1.0 else 1.0)) > COLOR_EPSILON:
			wrong += 1
	assert_eq(wrong, 0)


func test_tint_seed_is_constant_per_part_and_differs_between_parts() -> void:
	for name in PRIMITIVES:
		var part_colors := _colors(_single(name))
		var varying := 0
		for c in part_colors:
			if c.b != part_colors[0].b:
				varying += 1
		assert_eq(varying, 0, "%s: one tint seed per part" % name)
	var kit := MeshKit.new()
	kit.cbox(Vector3.ZERO, Vector3.ONE, 0.1)
	var one := kit.count * 3
	kit.cbox(Vector3(3, 0, 0), Vector3.ONE, 0.1)
	kit.rod(Vector3(0, 3, 0), Vector3.UP, 0.2, 1.0)
	var colors := _colors(kit.commit())
	var seeds := {colors[0].b: true, colors[one].b: true, colors[colors.size() - 1].b: true}
	assert_eq(seeds.size(), 3, "parts at different centres get different seeds")


func test_frame_and_base_map_vehicle_metres_into_the_pivot() -> void:
	# Frame: x from the front backwards (mirrored), 0.1 units per metre; base lowers by 0.2.
	var kit := MeshKit.new(Frame.new(0.1, 4.0), Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0)))
	kit.slab(1.0, 3.0, 0.5, 1.5, 0.5, 0.0, 0.05)
	var mesh := kit.commit()
	_assert_well_formed(mesh, "framed slab")
	_assert_closed(mesh, "framed slab")
	_assert_aabb(mesh, AABB(Vector3(0.1, -0.15, -0.05), Vector3(0.2, 0.1, 0.1)), "framed slab")
	var scaled := MeshKit.new(null, Transform3D.IDENTITY.scaled(Vector3.ONE * 0.1))
	scaled.cbox(Vector3(1, 1, 1), Vector3(2, 2, 2), 0.2)
	var small := scaled.commit()
	_assert_well_formed(small, "scaled cbox")
	_assert_aabb(small, AABB(Vector3.ZERO, Vector3(0.2, 0.2, 0.2)), "scaled cbox")


func test_mesh_kits_add_one_instance_per_material() -> void:
	var kits := MeshKits.new()
	kits.k(&"body").cbox(Vector3.ZERO, Vector3.ONE, 0.1)
	kits.k(&"body").pillow(Vector3(0, 1, 0), Vector3.ONE)
	kits.k(&"dark").tube(_l_path(), 0.05)
	kits.k(&"unused")
	var triangles := kits.triangle_count()
	assert_eq(triangles, kits.k(&"body").count + kits.k(&"dark").count)
	var materials := {
		&"body": StandardMaterial3D.new(),
		&"dark": StandardMaterial3D.new(),
		&"unused": StandardMaterial3D.new(),
	}
	var root := Node3D.new()
	var added := kits.add_to(root, materials)
	assert_eq(added.size(), 2)
	assert_eq(root.get_child_count(), 2, "empty kits add nothing")
	var vertices := 0
	for instance in added:
		vertices += _verts(instance.mesh as ArrayMesh).size()
	assert_eq(vertices, triangles * 3, "all vertices kept")
	assert_eq(added[0].material_override, materials[&"body"])
	assert_eq(added[1].material_override, materials[&"dark"])
	root.free()


func test_builds_are_deterministic() -> void:
	var a := MeshKit.new()
	var b := MeshKit.new()
	for name in PRIMITIVES:
		_build(a, name)
		_build(b, name)
	var arrays_a := _arrays(a.commit())
	var arrays_b := _arrays(b.commit())
	for slot: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
		assert_true(arrays_a[slot] == arrays_b[slot], "array %d identical" % slot)


func test_lathe_keeps_long_diagonal_segments_unflagged() -> void:
	var kit := MeshKit.new()
	# A cone: the slanted side (0.5 m) is far longer than chamfer_max, so it is a face, not an edge.
	kit.lathe(
		Vector3.ZERO, Basis.IDENTITY, [Vector2(0, 0.4), Vector2(0.3, 0.0), Vector2(0, 0.0)], 12
	)
	assert_true(0.5 > kit.chamfer_max)
	for c in _colors(kit.commit()):
		assert_eq(c.r, 0.0, "a long diagonal segment is not a chamfer")


func test_pair_mirrors_the_slab_across_z() -> void:
	var one := MeshKit.new()
	one.slab(0.0, 1.0, 0.0, 0.5, 0.05, 0.4)
	var both := MeshKit.new()
	both.pair(0.0, 1.0, 0.0, 0.5, 0.05, 0.4)
	assert_eq(both.count, one.count * 2)
	var box := _aabb(both.commit())
	assert_true(absf(box.position.z + 0.45) < EPSILON, "left slab at -z")
	assert_true(absf(box.end.z - 0.45) < EPSILON, "right slab at +z")


func test_arc_spans_its_angles_on_the_radius() -> void:
	var pts := MeshKit.arc(Vector3(1, 2, 3), 0.5, Vector3.RIGHT, Vector3.UP, 0.0, PI / 2.0, 4)
	assert_eq(pts.size(), 5)
	assert_true((pts[0] as Vector3).is_equal_approx(Vector3(1.5, 2, 3)))
	assert_true((pts[4] as Vector3).is_equal_approx(Vector3(1, 2.5, 3)))
	for p: Vector3 in pts:
		assert_true(absf(p.distance_to(Vector3(1, 2, 3)) - 0.5) < EPSILON)
