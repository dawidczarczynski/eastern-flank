extends TestCase
## Shared wheeled running gear (TASK-073): a synthetic Spec builds Wheel0..7 pivots at the axle
## positions on both sides, spinning about their local Z, with one mesh set per side shared by every
## pivot of that side, plain inner halves and opt-in hub / tread / mudflap / arch-liner detail.

const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const Gear := preload("res://src/presentation/models/parts/wheeled_running_gear.gd")
const K := 0.08
const LENGTH_M := 10.0
const AXLES: Array[float] = [1.8, 3.6, 7.0, 8.6]
const RADIUS := 0.6
const WIDTH := 0.4
const TRACK_Z := 1.1
const EPSILON := 1e-5
## Share of a wheel's triangles that may face the vehicle centre line (the inner half is a drum).
const MAX_INWARD_SHARE := 0.4
const INWARD_NORMAL := 0.5


func _frame() -> Frame:
	return Frame.new(K, LENGTH_M / 2.0)


func _spec(key := "test_wheeled") -> Gear.Spec:
	var spec := Gear.Spec.new()
	spec.key = key
	spec.axle_x = AXLES
	spec.wheel_radius = RADIUS
	spec.tyre_width = WIDTH
	spec.track_z = TRACK_Z
	return spec


func _materials() -> Dictionary:
	var materials := {}
	for role: StringName in Gear.MATERIAL_ROLES:
		materials[role] = StandardMaterial3D.new()
	return materials


func _build(spec: Gear.Spec) -> Node3D:
	var root := Node3D.new()
	Gear.build(root, _frame(), spec, _materials())
	return root


func _meshes(node: Node, into: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for child in node.get_children():
		if child is MeshInstance3D:
			into.append(child)
		_meshes(child, into)
	return into


## Transform of `node` in the space of its root (works outside the scene tree).
func _to_root(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var current := node
	while current != null:
		t = current.transform * t
		current = current.get_parent() as Node3D
	return t


func _triangles(node: Node) -> int:
	var total := 0
	for instance in _meshes(node):
		total += instance.mesh.get_faces().size() / 3
	return total


func _wheels(root: Node3D) -> Array[Node3D]:
	var wheels: Array[Node3D] = []
	for child in root.get_children():
		if String(child.name).begins_with("Wheel"):
			wheels.append(child as Node3D)
	return wheels


func test_builds_wheel_pivots_at_the_axles_on_both_sides() -> void:
	ModelParts.clear_mesh_cache()
	var root := Node3D.new()
	var next := Gear.build(root, _frame(), _spec(), _materials())
	assert_eq(next, 8)
	assert_eq(_wheels(root).size(), 8)
	var f := _frame()
	for i in 8:
		var pivot := root.get_node_or_null("Wheel%d" % i) as Node3D
		assert_true(pivot != null, "Wheel%d exists" % i)
		var side := -1.0 if i < 4 else 1.0
		var expected := f.p(AXLES[i % 4], RADIUS, side * TRACK_Z)
		assert_true(
			pivot.position.distance_to(expected) < EPSILON,
			"Wheel%d at %s, expected %s" % [i, pivot.position, expected]
		)
		assert_true(_meshes(pivot).size() >= 2, "Wheel%d has tyre and hub meshes" % i)
	root.free()


func test_first_index_offsets_the_pivot_names() -> void:
	var root := Node3D.new()
	var next := Gear.build(root, _frame(), _spec(), _materials(), 2)
	assert_eq(next, 10)
	assert_true(root.get_node_or_null("Wheel2") != null)
	assert_true(root.get_node_or_null("Wheel9") != null)
	assert_true(root.get_node_or_null("Wheel0") == null)
	root.free()


func test_wheel_meshes_stay_inside_the_wheel() -> void:
	var root := _build(_spec())
	for pivot in _wheels(root):
		var box := AABB()
		var first := true
		for instance in _meshes(pivot):
			var t := pivot.transform.affine_inverse() * _to_root(instance)
			var b := t * instance.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var r := RADIUS * K
		assert_true(absf(box.size.x - 2.0 * r) < 0.01 * K, "%s diameter %s" % [pivot.name, box])
		assert_true(absf(box.size.y - 2.0 * r) < 0.01 * K, "%s diameter %s" % [pivot.name, box])
		assert_true(box.size.z <= WIDTH * K * 1.05, "%s width %s" % [pivot.name, box])
		assert_true(box.size.z >= WIDTH * K * 0.9, "%s width %s" % [pivot.name, box])
	root.free()


func test_wheels_spin_independently_about_local_z() -> void:
	var root := _build(_spec())
	var before := {}
	for instance in _meshes(root):
		before[instance] = _to_root(instance)
	var spun := root.get_node("Wheel2") as Node3D
	var axis_before := _to_root(spun).basis.z
	spun.rotation.z = PI / 2.0
	assert_true(_to_root(spun).basis.z.distance_to(axis_before) < EPSILON, "axis unchanged")
	for instance in _meshes(root):
		var moved := not _to_root(instance).is_equal_approx(before[instance])
		assert_eq(moved, spun.is_ancestor_of(instance), "%s moved: %s" % [instance, moved])
	root.free()


func test_hub_and_tread_detail_cost_triangles() -> void:
	var full := _build(_spec("test_wheeled_full"))
	var plain_spec := _spec("test_wheeled_plain")
	plain_spec.hub_detail = false
	plain_spec.tread = false
	var plain := _build(plain_spec)
	var hub_only := _spec("test_wheeled_hub_off")
	hub_only.hub_detail = false
	var no_hub := _build(hub_only)
	var full_count := _triangles(full.get_node("Wheel0"))
	var no_hub_count := _triangles(no_hub.get_node("Wheel0"))
	var plain_count := _triangles(plain.get_node("Wheel0"))
	assert_true(no_hub_count < full_count, "hub detail: %d < %d" % [no_hub_count, full_count])
	assert_true(plain_count < no_hub_count, "tread: %d < %d" % [plain_count, no_hub_count])
	print("wheeled running gear: %d triangles per wheel (plain %d)" % [full_count, plain_count])
	for root in [full, plain, no_hub]:
		(root as Node3D).free()


func test_inflation_hub_adds_detail() -> void:
	var plain := _build(_spec("test_wheeled_no_ctis"))
	var ctis_spec := _spec("test_wheeled_ctis")
	ctis_spec.inflation_hub = true
	var ctis := _build(ctis_spec)
	assert_true(_triangles(ctis.get_node("Wheel0")) > _triangles(plain.get_node("Wheel0")))
	plain.free()
	ctis.free()


func test_wheels_of_one_side_share_their_meshes() -> void:
	var root := _build(_spec())
	for side in 2:
		var first := _meshes(root.get_node("Wheel%d" % (side * 4)))
		for i in range(side * 4 + 1, side * 4 + 4):
			var meshes := _meshes(root.get_node("Wheel%d" % i))
			assert_eq(meshes.size(), first.size())
			for j in meshes.size():
				assert_true(meshes[j].mesh == first[j].mesh, "Wheel%d shares meshes" % i)
	var left := _meshes(root.get_node("Wheel0"))
	var right := _meshes(root.get_node("Wheel4"))
	assert_true(left[0].mesh != right[0].mesh, "each side has its own (mirrored) meshes")
	root.free()


func test_meshes_are_cached_across_builds() -> void:
	var a := _build(_spec())
	var b := _build(_spec())
	assert_true(_meshes(a.get_node("Wheel5"))[0].mesh == _meshes(b.get_node("Wheel5"))[0].mesh)
	a.free()
	b.free()


func test_inner_wheel_halves_are_plain() -> void:
	var spec := _spec("test_wheeled_inner")
	spec.inflation_hub = true
	var root := _build(spec)
	for pivot in _wheels(root):
		var side := signf(pivot.position.z)
		var total := 0
		var inward := 0
		for instance in _meshes(pivot):
			var t := _to_root(instance)
			var faces := instance.mesh.get_faces()
			for j in range(0, faces.size(), 3):
				var a := t * faces[j]
				var n := (t * faces[j + 2] - a).cross(t * faces[j + 1] - a).normalized()
				total += 1
				if -side * n.z > INWARD_NORMAL:
					inward += 1
		assert_true(total > 0, "%s has meshes" % pivot.name)
		assert_true(
			inward <= total * MAX_INWARD_SHARE,
			"%s: %d of %d triangles face inwards" % [pivot.name, inward, total]
		)
	root.free()


func test_wheel_meshes_carry_paint_masks() -> void:
	var root := _build(_spec())
	for instance in _meshes(root.get_node("Wheel0")):
		assert_true(instance.mesh is ArrayMesh, "kit mesh")
		var colors: PackedColorArray = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		assert_true(colors.size() > 0, "vertex masks")
		var edge := false
		for c in colors:
			edge = edge or c.r >= 0.99
			assert_true(c.g >= 0.0 and c.g <= 1.0 and c.b >= 0.0 and c.b <= 1.0)
		assert_true(edge, "chamfer bands in %s" % instance.name)
	root.free()


func test_mudflaps_and_arch_liners_are_opt_in_hull_parts() -> void:
	var plain := _build(_spec())
	assert_eq(plain.get_child_count(), 8, "only the wheel pivots by default")
	var spec := _spec("test_wheeled_flaps")
	spec.mudflap_x = [9.3] as Array[float]
	spec.arch_liner_x = AXLES
	var root := _build(spec)
	var hull: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			hull.append(child)
	assert_true(hull.size() >= 1, "hull meshes for the flaps and liners")
	var box := AABB()
	for i in hull.size():
		var b := hull[i].transform * hull[i].mesh.get_aabb()
		box = b if i == 0 else box.merge(b)
	var f := _frame()
	# Liners arch over the wheels: higher than the tyres, never below the ground.
	assert_true(box.end.y > 2.0 * RADIUS * K, "liners above the tyres: %s" % box)
	assert_true(box.position.y >= 0.0, "nothing below the ground: %s" % box)
	assert_true(box.end.z > TRACK_Z * K and box.position.z < -TRACK_Z * K, "both sides: %s" % box)
	assert_true(box.position.x < f.p(9.3, 0.0).x + 0.001, "flap behind the rear axle: %s" % box)
	plain.free()
	root.free()
