extends TestCase
## Rocket launcher models v3 (TASK-073): the trucks are built with MeshKit (vertex masks,
## chamfers), cut the hidden geometry, share their wheel meshes, keep the launcher hierarchy and
## silhouette, sweep the raised pod clear of the truck and carry the effect anchors. Every check
## runs for each id in MLRS_IDS (and every faction in data/factions/ where the faction matters).
##
## Each model declares: `K` (model units per metre) and `LENGTH_M` (its metre -> model space frame
## is `Frame.new(K, LENGTH_M / 2.0)`), `HULL_INTERIOR: Array[AABB]` (vehicle metres, x from the
## front, h, z; boxes strictly inside closed shells at rest, the cab first – see INTERIOR_MIN) and
## `LAUNCHER_CLEARANCE_H` (metres: the lowest point of the raised pod outside the turntable ring;
## every hull part the raised pod passes over stays below it). Optional: `TURNTABLE_RING_R`
## (metres, the turntable ring radius around the "Launcher" pivot; DEFAULT_RING_R otherwise).

const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const FACTIONS_DIR := "res://data/factions/"
const MLRS_IDS: Array[StringName] = [&"homar_k", &"bm27_uragan"]
const WHEELS := 8
## Model-space AABB size (x length, y height, z width; before UnitModels' model scale) of each
## truck before TASK-073 (rest pose, measured on the pre-rework models).
const BEFORE_SIZE := {
	&"homar_k": Vector3(0.86112, 0.26442, 0.22776),
	&"bm27_uragan": Vector3(0.87792, 0.29946, 0.32829),
}
const BEFORE_LABEL_HEIGHT := 0.62
const SIZE_TOLERANCE := 0.03
const MIN_TRIANGLES := 16000
const MAX_TRIANGLES := 40000
## Minimum sizes (m) of each model's HULL_INTERIOR boxes, in order: the cab, the Homar-K pod box.
const CAB_MIN := Vector3(1.5, 0.6, 1.6)
const POD_MIN := Vector3(3.0, 0.8, 2.0)
const INTERIOR_MIN := {&"homar_k": [CAB_MIN, POD_MIN], &"bm27_uragan": [CAB_MIN]}
## Share of a wheel's triangles that may face the vehicle centre line (the inner half is a drum).
const MAX_INWARD_SHARE := 0.4
const INWARD_NORMAL := 0.5
## Metres the hull stays below the raised pod parts that pass over it.
const CLEARANCE_MARGIN := 0.01
## LAUNCHER_CLEARANCE_H may lie this far (m) below the pod's actual lowest point.
const CLEARANCE_SLACK := 0.05
## Hull parts inside the turntable ring stay this far (m) below the Launcher pivot at most.
const RING_ABOVE_BASE := 0.05
const DEFAULT_RING_R := 1.0
## Mouth markers lie this far (m) beyond the pod meshes along pod-local +X, all at one x.
const MOUTH_GAP_MIN := 0.0
const MOUTH_GAP_MAX := 0.15
const MOUTH_SPREAD := 0.02
## A warm-cache build (meshes cached) takes at most this share of the cold build (plus slack ms).
const WARM_SHARE := 0.2
const WARM_SLACK_MSEC := 1.0
## Dust anchors: within this many model units of the ground, in the rear share of the length.
const GROUND_BAND := 0.05
const REAR_SHARE := 0.3
## The Homar-K exhaust stack outlet is higher than the cab roof's lowest point (its edge, m).
const HOMAR_CAB_ROOF_LOW := 3.12
## Glass and light lenses (glossy plain materials) carry no chamfer bands.
const UNMASKED_ROUGHNESS := 0.2
const DEPLOY_PREFIXES: Array[String] = ["Wheel", "Stabiliser", "BlastShield"]


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


func _const(id: StringName, name: StringName, fallback: Variant = null) -> Variant:
	return _script(id).get_script_constant_map().get(name, fallback)


func _frame(id: StringName) -> Frame:
	var k: float = _const(id, &"K")
	var length: float = _const(id, &"LENGTH_M")
	return Frame.new(k, length / 2.0)


## The "Model" node of a freshly built truck (call `.get_parent().free()` when done).
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


## Whether `node` sits below a wheel, jack or shield pivot of `model`.
func _in_deployable(node: Node, model: Node) -> bool:
	var current := node.get_parent()
	while current != null and current != model:
		for prefix in DEPLOY_PREFIXES:
			if String(current.name).begins_with(prefix):
				return true
		current = current.get_parent()
	return false


## Hull meshes: not under the launcher, the wheels, the jacks or the shields.
func _hull_meshes(model: Node3D) -> Array[MeshInstance3D]:
	var launcher := model.get_node("Launcher")
	var hull: Array[MeshInstance3D] = []
	for instance in _meshes(model):
		if not _under(instance, launcher) and not _in_deployable(instance, model):
			hull.append(instance)
	return hull


func _model_bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for instance in _meshes(model):
		var b := _to_model(instance, model) * instance.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _triangles(node: Node) -> int:
	var total := 0
	for instance in _meshes(node):
		total += instance.mesh.get_faces().size() / 3
	return total


## Model-space transforms of every mesh instance of `model`, by instance.
func _placements(model: Node3D) -> Dictionary:
	var result := {}
	for instance in _meshes(model):
		result[instance] = _to_model(instance, model)
	return result


func test_launchers_are_kit_meshes_with_paint_masks() -> void:
	for faction in _factions():
		for id in MLRS_IDS:
			var model := _model(id, faction)
			for instance in _meshes(model):
				var label := "%s/%s %s" % [id, faction.id, model.get_path_to(instance)]
				assert_true(
					instance.mesh is ArrayMesh and not instance.mesh is PrimitiveMesh,
					"%s is an ArrayMesh" % label
				)
				var plain := instance.material_override as StandardMaterial3D
				if plain != null and plain.roughness <= UNMASKED_ROUGHNESS:
					continue
				var arrays := (instance.mesh as ArrayMesh).surface_get_arrays(0)
				var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
				assert_eq(
					colors.size(),
					(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
					"%s has vertex masks" % label
				)
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
		for id in MLRS_IDS:
			var model := _model(id, faction)
			var triangles := _triangles(model)
			print("[mlrs] %s/%s: triangles=%d" % [id, faction.id, triangles])
			assert_true(triangles >= MIN_TRIANGLES, "%s: %d triangles" % [id, triangles])
			assert_true(triangles <= MAX_TRIANGLES, "%s: %d triangles" % [id, triangles])
			model.get_parent().free()


func test_no_triangle_inside_the_closed_shells() -> void:
	for id in MLRS_IDS:
		var boxes: Array = _const(id, &"HULL_INTERIOR", [])
		var minimum: Array = INTERIOR_MIN[id]
		assert_true(boxes.size() >= minimum.size(), "%s: HULL_INTERIOR boxes" % id)
		var frame := _frame(id)
		var model_boxes: Array[AABB] = []
		for i in boxes.size():
			var interior: AABB = boxes[i]
			if i < minimum.size():
				var least: Vector3 = minimum[i]
				for axis in 3:
					assert_true(
						interior.size[axis] >= least[axis],
						"%s HULL_INTERIOR[%d] axis %d: %.2f m" % [id, i, axis, interior.size[axis]]
					)
			var a := frame.p(interior.position.x, interior.position.y, interior.position.z)
			var b := frame.p(interior.end.x, interior.end.y, interior.end.z)
			model_boxes.append(AABB(a, Vector3.ZERO).expand(b))
		for faction in _factions():
			var model := _model(id, faction)
			var inside := 0
			for instance in _meshes(model):
				var faces := _faces(instance, model)
				for i in range(0, faces.size(), 3):
					for box in model_boxes:
						if (
							box.has_point(faces[i])
							and box.has_point(faces[i + 1])
							and box.has_point(faces[i + 2])
						):
							inside += 1
			assert_eq(inside, 0, "%s/%s: triangles inside a closed shell" % [id, faction.id])
			model.get_parent().free()


func test_inner_wheel_halves_are_plain() -> void:
	for id in MLRS_IDS:
		var model := _model(id, _factions()[0])
		for i in WHEELS:
			var pivot := model.get_node_or_null("Wheel%d" % i) as Node3D
			assert_true(pivot != null, "%s Wheel%d exists" % [id, i])
			if pivot == null:
				continue
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


func test_wheels_of_one_side_share_their_meshes() -> void:
	for id in MLRS_IDS:
		var model := _model(id, _factions()[0])
		var first := {}  # side -> meshes of the first wheel on that side
		for i in WHEELS:
			var pivot := model.get_node("Wheel%d" % i) as Node3D
			var side := int(signf(pivot.position.z))
			var meshes := _meshes(pivot)
			if not first.has(side):
				first[side] = meshes
				continue
			var reference: Array[MeshInstance3D] = first[side]
			assert_eq(meshes.size(), reference.size(), "%s Wheel%d mesh count" % [id, i])
			for j in mini(meshes.size(), reference.size()):
				assert_true(
					meshes[j].mesh == reference[j].mesh, "%s Wheel%d shares its meshes" % [id, i]
				)
		assert_eq(first.size(), 2, "%s: wheels on both sides" % id)
		model.get_parent().free()


func test_warm_cache_build_is_cheap() -> void:
	var faction := _factions()[0]
	for id in MLRS_IDS:
		ModelParts.clear_mesh_cache()
		var start := Time.get_ticks_usec()
		var cold: Node3D = _script(id).call(&"build", faction)
		var cold_msec := (Time.get_ticks_usec() - start) / 1000.0
		start = Time.get_ticks_usec()
		var warm: Node3D = _script(id).call(&"build", faction)
		var warm_msec := (Time.get_ticks_usec() - start) / 1000.0
		print("[mlrs] %s: cold build %.1f ms, warm %.1f ms" % [id, cold_msec, warm_msec])
		assert_true(
			warm_msec <= cold_msec * WARM_SHARE + WARM_SLACK_MSEC,
			"%s: warm build %.1f ms vs cold %.1f ms" % [id, warm_msec, cold_msec]
		)
		cold.free()
		warm.free()


## Raising the pod moves only the pod and the actuators; traversing moves only the launcher.
func test_launcher_hierarchy() -> void:
	for id in MLRS_IDS:
		var model := _model(id, _factions()[0])
		var launcher := model.get_node("Launcher") as Node3D
		var pod := UnitModels.launcher_pod(model)
		var rest := _placements(model)
		UnitModels.pose_launcher(model, 0.0, UnitModels.launcher_elevation(model))
		for instance: MeshInstance3D in rest:
			var moved := not _to_model(instance, model).is_equal_approx(rest[instance])
			var actuator := false
			var current := instance.get_parent()
			while current != launcher and current != null:
				actuator = actuator or String(current.name).begins_with("Actuator")
				current = current.get_parent()
			if moved:
				assert_true(
					_under(instance, pod) or actuator,
					"%s: raising moves %s" % [id, model.get_path_to(instance)]
				)
		UnitModels.pose_launcher(model, 0.0, 0.0)
		UnitModels.pose_launcher(model, deg_to_rad(30.0), 0.0)
		for instance: MeshInstance3D in rest:
			if not _to_model(instance, model).is_equal_approx(rest[instance]):
				assert_true(
					_under(instance, launcher),
					"%s: traversing moves %s" % [id, model.get_path_to(instance)]
				)
		model.get_parent().free()


## Inside the turntable ring the hull holds only the fixed turntable base.
func test_hull_stays_below_the_turntable_inside_the_ring() -> void:
	for id in MLRS_IDS:
		var frame := _frame(id)
		var ring_r: float = _const(id, &"TURNTABLE_RING_R", DEFAULT_RING_R)
		var model := _model(id, _factions()[0])
		var axis := _metres(frame, (model.get_node("Launcher") as Node3D).position)
		var highest := -INF
		for instance in _hull_meshes(model):
			for p in _faces(instance, model):
				var m := _metres(frame, p)
				if Vector2(m.x - axis.x, m.z - axis.z).length() < ring_r:
					highest = maxf(highest, m.y)
		assert_true(
			highest <= axis.y + RING_ABOVE_BASE,
			"%s: hull at %.3f m inside the ring, turntable base %.3f m" % [id, highest, axis.y]
		)
		model.get_parent().free()


## One mouth per tube just beyond the tube ends (pod-local +X), all at one depth.
func test_mouths_just_beyond_the_tube_ends() -> void:
	for id in MLRS_IDS:
		var k: float = _const(id, &"K")
		var model := _model(id, _factions()[0])
		var pod := UnitModels.launcher_pod(model)
		var front := -INF
		for instance in _meshes(pod):
			var t := Transform3D.IDENTITY
			var current: Node3D = instance
			while current != pod:
				t = current.transform * t
				current = current.get_parent() as Node3D
			front = maxf(front, (t * instance.get_aabb()).end.x)
		var xs: Array[float] = []
		for child in pod.get_children():
			if String(child.name).begins_with("Mouth"):
				xs.append((child as Node3D).position.x)
		assert_true(xs.size() >= 12, "%s: %d mouths" % [id, xs.size()])
		for x in xs:
			var gap := (x - front) / k
			assert_true(
				gap >= MOUTH_GAP_MIN and gap <= MOUTH_GAP_MAX,
				"%s: mouth %.3f m beyond the tube ends" % [id, gap]
			)
		assert_true(xs.max() - xs.min() <= MOUTH_SPREAD * k, "%s: mouths at one depth" % id)
		model.get_parent().free()


## The raised pod sweeps over the hull without touching it at any traverse angle: every hull
## vertex outside the turntable ring stays CLEARANCE_MARGIN below the lowest raised-pod vertex at
## its distance from the turntable axis or farther out (the pod parts that pass over it; distances
## do not change with the traverse, so this holds for the whole range). LAUNCHER_CLEARANCE_H is the
## lowest raised-pod vertex outside the ring.
func test_raised_pod_sweeps_clear_of_the_hull() -> void:
	for id in MLRS_IDS:
		var frame := _frame(id)
		var ring_r: float = _const(id, &"TURNTABLE_RING_R", DEFAULT_RING_R)
		var clearance: float = _const(id, &"LAUNCHER_CLEARANCE_H", INF)
		var model := _model(id, _factions()[0])
		var pod := UnitModels.launcher_pod(model)
		var axis := _metres(frame, (model.get_node("Launcher") as Node3D).position)
		UnitModels.pose_launcher(model, 0.0, UnitModels.launcher_elevation(model))
		var reach: Array[Vector2] = []  # (distance, height) of raised-pod vertices outside the ring
		for instance in _meshes(pod):
			for p in _faces(instance, model):
				var m := _metres(frame, p)
				var d := Vector2(m.x - axis.x, m.z - axis.z).length()
				if d > ring_r:
					reach.append(Vector2(d, m.y))
		var hull: Array[Vector2] = []
		for instance in _hull_meshes(model):
			for p in _faces(instance, model):
				var m := _metres(frame, p)
				var d := Vector2(m.x - axis.x, m.z - axis.z).length()
				if d > ring_r:
					hull.append(Vector2(d, m.y))
		var farther := func(a: Vector2, b: Vector2) -> bool: return a.x > b.x
		reach.sort_custom(farther)
		hull.sort_custom(farther)
		var pod_lowest := INF
		for r in reach:
			pod_lowest = minf(pod_lowest, r.y)
		assert_true(
			pod_lowest >= clearance - 0.001,
			"%s: raised pod at %.3f m, below LAUNCHER_CLEARANCE_H" % [id, pod_lowest]
		)
		assert_true(
			pod_lowest <= clearance + CLEARANCE_SLACK,
			"%s: LAUNCHER_CLEARANCE_H %.3f m set too low (pod %.3f m)" % [id, clearance, pod_lowest]
		)
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
				"%s: hull vertex %.2f m from the turntable axis, h %.3f m, reaches %.3f m into the sweep"
				% [id, at.x, at.y, worst]
			)
		)
		model.get_parent().free()


func test_effect_anchors() -> void:
	for id in MLRS_IDS:
		var frame := _frame(id)
		var model := _model(id, _factions()[0])
		var bounds := _model_bounds(model).grow(0.001)
		for name: String in ["Exhaust", "Dust_L", "Dust_R"]:
			var anchor := model.get_node_or_null(name)
			assert_true(anchor is Marker3D, "%s: %s is a Marker3D under Model" % [id, name])
			if anchor is Marker3D:
				var at := (anchor as Marker3D).position
				assert_true(bounds.has_point(at), "%s: %s inside the model" % [id, name])
		if not model.get_node_or_null("Dust_L") is Marker3D:
			model.get_parent().free()
			continue
		var rear_limit := bounds.position.x + bounds.size.x * REAR_SHARE
		for name: String in ["Dust_L", "Dust_R"]:
			var at := (model.get_node(name) as Node3D).position
			assert_true(
				at.y <= bounds.position.y + GROUND_BAND, "%s: %s on the ground" % [id, name]
			)
			assert_true(at.x <= rear_limit, "%s: %s at the rear (x %.3f)" % [id, name, at.x])
		assert_true((model.get_node("Dust_L") as Node3D).position.z < 0.0, "%s Dust_L left" % id)
		assert_true((model.get_node("Dust_R") as Node3D).position.z > 0.0, "%s Dust_R right" % id)
		if id == &"homar_k":
			var exhaust := _metres(frame, (model.get_node("Exhaust") as Node3D).position)
			assert_true(exhaust.y > HOMAR_CAB_ROOF_LOW, "homar_k: exhaust above the cab roof edge")
		model.get_parent().free()


func test_silhouette_and_label_unchanged() -> void:
	for id in MLRS_IDS:
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
			var wheels := 0
			for child in model.get_children():
				wheels += 1 if String(child.name).begins_with("Wheel") else 0
			assert_eq(wheels, WHEELS, "%s wheel pivots" % id)
			model.get_parent().free()
