extends TestCase
## Tank models v3 (TASK-069): the main battle tanks are built with MeshKit (vertex masks, chamfers),
## cut the hidden geometry, keep their silhouette and carry the pivots and anchors the animations
## and effects use. Every check runs for each id in TANK_IDS and every faction in data/factions/.
##
## Each tank model declares: `vehicle_frame()` (its metre -> model space Frame), `running_gear()`
## (its TrackedRunningGear.Spec), `HULL_INTERIOR` (AABB in vehicle metres strictly inside the
## shell), `TURRET_X` / `TURRET_RING_R` (turret ring centre and radius, m), `TURRET_CLEARANCE_H`
## (lowest turret underside outside the ring, m), `HULL_LENGTH` and `K`.

const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const Gear := preload("res://src/presentation/models/parts/tracked_running_gear.gd")
const FACTIONS_DIR := "res://data/factions/"
## Tanks reworked onto the kit.
const TANK_IDS: Array[StringName] = [&"m1a2_sepv3", &"t72b3"]
## Wheel* pivots per tank (unchanged by the rework).
const WHEELS := {&"m1a2_sepv3": 18, &"t72b3": 16}
## Model-space AABB size (x length, y height, z width; before UnitModels' model scale) of each tank
## before TASK-069, from the contract print (size / 1.1).
const BEFORE_SIZE := {
	&"m1a2_sepv3": Vector3(0.871, 0.232, 0.327),
	&"t72b3": Vector3(0.876, 0.242, 0.314),
}
const BEFORE_LABEL_HEIGHT := 0.62
const SIZE_TOLERANCE := 0.03
## Tanks whose exhaust is at the rear plate (in the rear quarter of the hull).
const REAR_EXHAUST: Array[StringName] = [&"m1a2_sepv3"]
const MIN_TRIANGLES := 22000
const MAX_TRIANGLES := 40000
const MIN_INTERIOR := Vector3(4.0, 0.6, 1.6)
## Track triangles allowed on the top run behind the skirts per side (none, or one plain band).
const MAX_HIDDEN_TRACK_TRIANGLES := 24
## Share of a road wheel's triangles that may face the hull centre line (the inner half is a drum).
const MAX_INWARD_SHARE := 0.4
const INWARD_NORMAL := 0.5
const CLEARANCE_MARGIN := 0.01
## Child count of TrackedRunningGear.build with a default Spec before TASK-069: 4 wheel pivots
## (idlers, sprockets), track, rollers, skirts, accent plate.
const DEFAULT_GEAR_CHILDREN := 8


func _factions() -> Array[FactionDefinition]:
	var result: Array[FactionDefinition] = []
	var files := Array(DirAccess.get_files_at(FACTIONS_DIR))
	files.sort()
	for file: String in files:
		if file.get_extension() == "tres":
			result.append(load(FACTIONS_DIR + file) as FactionDefinition)
	return result


func _script(id: StringName) -> GDScript:
	return load(UnitModels.MODEL_PATH % id) as GDScript


func _const(id: StringName, name: StringName) -> Variant:
	return _script(id).get_script_constant_map().get(name)


func _frame(id: StringName) -> Frame:
	return _script(id).call(&"vehicle_frame")


func _spec(id: StringName) -> Gear.Spec:
	return _script(id).call(&"running_gear")


## The "Model" node of a freshly built tank (call `.get_parent().free()` when done).
func _model(id: StringName, faction: FactionDefinition) -> Node3D:
	return UnitModels.build(id, 0, faction).get_node("Model") as Node3D


func _meshes(node: Node, into: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for child in node.get_children():
		if child is MeshInstance3D:
			into.append(child)
		_meshes(child, into)
	return into


## Transform from `node`'s space into the space of its ancestor `model`.
func _to_model(node: Node3D, model: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var current := node
	while current != model:
		t = current.transform * t
		current = current.get_parent() as Node3D
	return t


## Triangle corners of `instance` in the space of `model` (3 points per triangle).
func _faces(instance: MeshInstance3D, model: Node3D) -> PackedVector3Array:
	var t := _to_model(instance, model)
	var faces := instance.mesh.get_faces()
	for i in faces.size():
		faces[i] = t * faces[i]
	return faces


## Model-space point -> vehicle metres (x from the front, h, z).
func _metres(frame: Frame, p: Vector3) -> Vector3:
	return Vector3(frame.origin_x - p.x / frame.k, p.y / frame.k, p.z / frame.k)


func _under(node: Node, ancestor: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _in_wheel(node: Node, model: Node) -> bool:
	var current := node.get_parent()
	while current != null and current != model:
		if String(current.name).begins_with("Wheel"):
			return true
		current = current.get_parent()
	return false


func _model_bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for instance in _meshes(model):
		var b := _to_model(instance, model) * instance.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_tanks_are_kit_meshes_with_paint_masks() -> void:
	for faction in _factions():
		var plain := Frame.kit_tank_materials(faction)
		var unmasked: Array = [plain[&"glass"], plain[&"lens"], plain[&"red_lens"]]
		for id in TANK_IDS:
			var model := _model(id, faction)
			for instance in _meshes(model):
				var label := "%s/%s %s" % [id, faction.id, model.get_path_to(instance)]
				assert_true(
					instance.mesh is ArrayMesh and not instance.mesh is PrimitiveMesh,
					"%s is an ArrayMesh" % label
				)
				if instance.material_override in unmasked:
					continue
				var arrays := (instance.mesh as ArrayMesh).surface_get_arrays(0)
				var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
				assert_eq(colors.size(), (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
				var edge := false
				var in_range := true
				for c in colors:
					edge = edge or c.r >= 0.99
					in_range = in_range and c.g >= 0.0 and c.g <= 1.0 and c.b >= 0.0 and c.b <= 1.0
				assert_true(edge, "%s has chamfer bands (r = 1)" % label)
				assert_true(in_range, "%s masks g, b in [0, 1]" % label)
			model.get_parent().free()


func test_triangle_budget_spent_on_detail() -> void:
	for faction in _factions():
		for id in TANK_IDS:
			var model := _model(id, faction)
			var triangles := 0
			for instance in _meshes(model):
				triangles += instance.mesh.get_faces().size() / 3
			print("[tank] %s/%s: triangles=%d" % [id, faction.id, triangles])
			assert_true(triangles >= MIN_TRIANGLES, "%s: %d triangles" % [id, triangles])
			assert_true(triangles <= MAX_TRIANGLES, "%s: %d triangles" % [id, triangles])
			model.get_parent().free()


func test_no_triangle_inside_the_hull_shell() -> void:
	for id in TANK_IDS:
		var interior: AABB = _const(id, &"HULL_INTERIOR")
		assert_true(interior.size.x >= MIN_INTERIOR.x, "%s interior length" % id)
		assert_true(interior.size.y >= MIN_INTERIOR.y, "%s interior height" % id)
		assert_true(interior.size.z >= MIN_INTERIOR.z, "%s interior width" % id)
		var frame := _frame(id)
		var a := frame.p(interior.position.x, interior.position.y, interior.position.z)
		var b := frame.p(interior.end.x, interior.end.y, interior.end.z)
		var box := AABB(a, Vector3.ZERO).expand(b)
		for faction in _factions():
			var model := _model(id, faction)
			var inside := 0
			for instance in _meshes(model):
				var faces := _faces(instance, model)
				for i in range(0, faces.size(), 3):
					if (
						box.has_point(faces[i])
						and box.has_point(faces[i + 1])
						and box.has_point(faces[i + 2])
					):
						inside += 1
			assert_eq(inside, 0, "%s/%s: triangles inside the hull" % [id, faction.id])
			model.get_parent().free()


func test_no_track_shoes_on_the_top_run_behind_the_skirts() -> void:
	var track := Frame.weathered(&"track")
	for id in TANK_IDS:
		var spec := _spec(id)
		var frame := _frame(id)
		var top := spec.road_wheel_h + spec.road_wheel_radius
		var model := _model(id, _factions()[0])
		var hidden := {-1: 0, 1: 0}
		var visible := 0
		for instance in _meshes(model):
			if instance.material_override != track:
				continue
			var faces := _faces(instance, model)
			for i in range(0, faces.size(), 3):
				var c := _metres(frame, (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0)
				var behind := c.x >= spec.skirt_x0 + 0.5 and c.x <= spec.skirt_x1 - 0.5
				if behind and c.y > top:
					hidden[int(signf(c.z))] += 1
				else:
					visible += 1
		for side: int in hidden:
			assert_true(
				hidden[side] <= MAX_HIDDEN_TRACK_TRIANGLES,
				"%s side %d: %d track triangles behind the skirts" % [id, side, hidden[side]]
			)
		assert_true(visible > 0, "%s: the visible track runs have shoes" % id)
		model.get_parent().free()


func test_inner_road_wheel_halves_are_plain() -> void:
	for id in TANK_IDS:
		var model := _model(id, _factions()[0])
		for i in _spec(id).road_wheel_x.size() * 2:
			var pivot := model.get_node("Wheel%d" % i) as Node3D
			var side := signf(pivot.position.z)
			var total := 0
			var inward := 0
			for instance in _meshes(pivot):
				var faces := _faces(instance, model)
				for j in range(0, faces.size(), 3):
					var n := (faces[j + 2] - faces[j]).cross(faces[j + 1] - faces[j]).normalized()
					total += 1
					if -side * n.z > INWARD_NORMAL:
						inward += 1
			assert_true(total > 0, "%s Wheel%d has meshes" % [id, i])
			assert_true(
				inward <= total * MAX_INWARD_SHARE,
				"%s Wheel%d: %d of %d triangles face inwards" % [id, i, inward, total]
			)
		model.get_parent().free()


func test_road_wheels_of_one_side_share_their_meshes() -> void:
	for id in TANK_IDS:
		var model := _model(id, _factions()[0])
		var per_side := _spec(id).road_wheel_x.size()
		for side in 2:
			var first := _meshes(model.get_node("Wheel%d" % (side * per_side)))
			for i in range(side * per_side + 1, (side + 1) * per_side):
				var meshes := _meshes(model.get_node("Wheel%d" % i))
				assert_eq(meshes.size(), first.size())
				for j in meshes.size():
					assert_true(
						meshes[j].mesh == first[j].mesh, "%s Wheel%d shares meshes" % [id, i]
					)
		model.get_parent().free()


## The turret (gun at rest included) sweeps over the hull without touching it: every hull vertex
## outside the turret ring that some turret part passes over (distance from the ring centre up to
## the turret's reach) stays CLEARANCE_MARGIN below the lowest turret vertex at that distance or
## further out; TURRET_CLEARANCE_H is the lowest turret vertex outside the ring.
func test_turret_sweeps_clear_of_the_hull() -> void:
	for id in TANK_IDS:
		var frame := _frame(id)
		var ring_x: float = _const(id, &"TURRET_X")
		var ring_r: float = _const(id, &"TURRET_RING_R") + 0.01
		var clearance: float = _const(id, &"TURRET_CLEARANCE_H")
		var model := _model(id, _factions()[0])
		var turret := model.get_node("Turret")
		var reach: Array[Vector2] = []  # (distance, height) of turret vertices outside the ring
		var hull: Array[Vector2] = []  # the same for the hull vertices
		for instance in _meshes(model):
			if _in_wheel(instance, model):
				continue
			var is_turret := _under(instance, turret)
			for p in _faces(instance, model):
				var m := _metres(frame, p)
				var d := Vector2(m.x - ring_x, m.z).length()
				if d > ring_r:
					(reach if is_turret else hull).append(Vector2(d, m.y))
		var farther := func(a: Vector2, b: Vector2) -> bool: return a.x > b.x
		reach.sort_custom(farther)
		hull.sort_custom(farther)
		var turret_lowest := INF
		for r in reach:
			turret_lowest = minf(turret_lowest, r.y)
		assert_true(turret_lowest >= clearance - 0.001, "%s: turret below TURRET_CLEARANCE_H" % id)
		assert_true(turret_lowest <= clearance + CLEARANCE_MARGIN, "%s: clearance set too low" % id)
		# Walk both lists from the outside in: `lowest` = lowest turret vertex at the hull vertex's
		# distance or farther out (the turret parts that pass over it).
		var j := 0
		var lowest := INF
		var worst := -INF
		var at := Vector2.ZERO
		for v in hull:
			while j < reach.size() and reach[j].x >= v.x:
				lowest = minf(lowest, reach[j].y)
				j += 1
			if lowest < INF and v.y - (lowest - CLEARANCE_MARGIN) > worst:
				worst = v.y - (lowest - CLEARANCE_MARGIN)
				at = v
		assert_true(
			worst <= 0.0,
			(
				"%s: hull vertex at %.2f m from the ring centre, h %.3f m, reaches %.3f m into the sweep"
				% [id, at.x, at.y, worst]
			)
		)
		_assert_turret_turns_freely(model)
		model.get_parent().free()


## Turning the turret moves no hull part and keeps the model on the ground.
func _assert_turret_turns_freely(model: Node3D) -> void:
	var turret := model.get_node("Turret") as Node3D
	var hull: Array[Mesh] = []
	for instance in _meshes(model):
		if not _under(instance, turret):
			hull.append(instance.mesh)
	var ground := _model_bounds(model).position.y
	for quarter in [1, 2, 3]:
		turret.rotation.y = quarter * PI / 2.0
		assert_true(absf(_model_bounds(model).position.y - ground) <= 0.005, "ground kept")
		var index := 0
		for instance in _meshes(model):
			if not _under(instance, turret):
				assert_true(instance.mesh == hull[index], "hull mesh unchanged")
				index += 1
	turret.rotation.y = 0.0


func test_barrel_pivot_holds_the_barrel_up_to_the_muzzle() -> void:
	for id in TANK_IDS:
		var k: float = _const(id, &"K")
		var model := _model(id, _factions()[0])
		var gun := model.get_node("Turret/Gun") as Node3D
		assert_true(gun.basis.is_equal_approx(Basis.IDENTITY), "%s: gun level" % id)
		var barrel := gun.get_node_or_null("Barrel") as Node3D
		assert_true(barrel != null, "%s: Turret/Gun/Barrel exists" % id)
		assert_true(barrel.transform.is_equal_approx(Transform3D.IDENTITY), "%s: identity" % id)
		var parts := _meshes(barrel)
		assert_true(parts.size() >= 1, "%s: Barrel holds meshes" % id)
		var front := -INF
		for instance in parts:
			front = maxf(front, (instance.transform * instance.get_aabb()).end.x)
		var muzzle := gun.get_node("Muzzle") as Node3D
		assert_true(
			absf(muzzle.position.x - front) <= 0.1 * k,
			"%s: barrel ends at the muzzle (%.4f vs %.4f)" % [id, front, muzzle.position.x]
		)
		var mantlet := false
		for child in gun.get_children():
			mantlet = mantlet or child is MeshInstance3D
		assert_true(mantlet, "%s: Turret/Gun holds the mantlet" % id)
		model.get_parent().free()


func test_effect_anchors() -> void:
	for id in TANK_IDS:
		var frame := _frame(id)
		var model := _model(id, _factions()[0])
		var bounds := _model_bounds(model).grow(0.001)
		for name: String in ["Exhaust", "Dust_L", "Dust_R"]:
			var anchor := model.get_node_or_null(name)
			assert_true(anchor is Marker3D, "%s: %s is a Marker3D under Model" % [id, name])
			if anchor is Marker3D:
				var at := (anchor as Marker3D).position
				assert_true(bounds.has_point(at), "%s: %s inside the model" % [id, name])
		assert_true((model.get_node("Dust_L") as Node3D).position.z < 0.0, "%s Dust_L left" % id)
		assert_true((model.get_node("Dust_R") as Node3D).position.z > 0.0, "%s Dust_R right" % id)
		if id in REAR_EXHAUST:
			var hull_length: float = _const(id, &"HULL_LENGTH")
			var x := _metres(frame, (model.get_node("Exhaust") as Node3D).position).x
			assert_true(x >= hull_length * 0.75, "%s: exhaust at the rear (%.2f m)" % [id, x])
		model.get_parent().free()


func test_silhouette_and_label_unchanged() -> void:
	for id in TANK_IDS:
		assert_eq(UnitModels.label_height(id), BEFORE_LABEL_HEIGHT)
		var before: Vector3 = BEFORE_SIZE[id]
		for faction in _factions():
			var model := _model(id, faction)
			var size := _model_bounds(model).size
			for axis in 3:
				assert_true(
					absf(size[axis] / before[axis] - 1.0) <= SIZE_TOLERANCE,
					(
						"%s/%s axis %d: %.4f vs %.4f before"
						% [id, faction.id, axis, size[axis], before[axis]]
					)
				)
			assert_eq(_meshes(model).size() > 0, true)
			var wheels := 0
			for child in model.get_children():
				wheels += 1 if String(child.name).begins_with("Wheel") else 0
			assert_eq(wheels, WHEELS[id], "%s wheel pivots" % id)
			model.get_parent().free()


func _gear_materials() -> Dictionary:
	var materials := {}
	for key: StringName in [&"body", &"dark", &"steel", &"rubber", &"track", &"accent"]:
		materials[key] = StandardMaterial3D.new()
	return materials


func test_running_gear_kit_options_are_opt_in() -> void:
	var spec := Gear.Spec.new()
	assert_false(Gear.uses_kit(spec))
	var root := Node3D.new()
	Gear.build(root, Frame.new(0.09, 3.3), spec, _gear_materials())
	assert_eq(root.get_child_count(), DEFAULT_GEAR_CHILDREN)
	root.free()


func test_running_gear_kit_options_build_shared_detailed_wheels() -> void:
	ModelParts.clear_mesh_cache()
	var spec := Gear.Spec.new()
	spec.key = "test_kit_gear"
	spec.road_wheel_x = [1.0, 1.8, 2.6, 3.4] as Array[float]
	spec.return_roller_x = [2.0] as Array[float]
	spec.detailed_wheels = true
	spec.track_shoe_pitch = 0.2
	spec.detailed_skirts = true
	spec.skirt_rear_rake = 0.6
	spec.skirt_rear_rise = 0.3
	var root := Node3D.new()
	var next := Gear.build(root, Frame.new(0.09, 3.3), spec, _gear_materials())
	assert_eq(next, 12)
	for i in 12:
		var pivot := root.get_node_or_null("Wheel%d" % i)
		assert_true(pivot != null and _meshes(pivot).size() >= 2, "Wheel%d detailed" % i)
	assert_true(
		_meshes(root.get_node("Wheel0"))[0].mesh == _meshes(root.get_node("Wheel3"))[0].mesh
	)
	assert_true(
		_meshes(root.get_node("Wheel0"))[0].mesh != _meshes(root.get_node("Wheel4"))[0].mesh
	)
	var hull := 0
	for child in root.get_children():
		hull += 1 if child is MeshInstance3D else 0
	assert_true(hull >= 4, "track, rubber, dark, body, steel, accent hull meshes: %d" % hull)
	root.free()
