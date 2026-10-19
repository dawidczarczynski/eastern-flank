extends TestCase
## Model contract (TASK-036): every model file in src/presentation/models/ x every faction in
## data/factions/. Numbers are printed per model and faction. Specific behaviour of the registry
## (facing, camo, hit reset) is in test_unit_models.gd.

const MODELS_DIR := "res://src/presentation/models/"
const FACTIONS_DIR := "res://data/factions/"
## Kind of each current model (ids are renamed to real unit ids by TASK-039a: update here).
const KINDS := {
	&"infantry": &"squad",
	&"cavalry": &"tank",
	&"rocket_artillery": &"rocket_artillery",
	&"homar_k": &"rocket_artillery",
}
## Known violations of the current models (measured numbers, reported in TASK-036). The
## thresholds below stay as specified; a waiver is dropped from here when the model is fixed
## (the test fails if a waived check no longer fails).
const WAIVERS := {
	&"cavalry": ["ground", "centre_x", "length", "body_meshes"],
	&"rocket_artillery": ["length", "body_meshes"],
}
const MAX_LENGTH := 1.15
const MAX_WIDTH := 0.8
const MAX_TRIANGLES_VEHICLE := 25000
const MAX_TRIANGLES_SQUAD := 20000
const MAX_BODY_MESH_INSTANCES := 24
const GROUND_TOLERANCE := 0.005
const CENTRE_TOLERANCE := 0.05


func _model_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for file in DirAccess.get_files_at(MODELS_DIR):
		if file.get_extension() == "gd" and file != "model_parts.gd":
			ids.append(StringName(file.get_basename()))
	ids.sort()
	return ids


func _factions() -> Array[FactionDefinition]:
	var result: Array[FactionDefinition] = []
	var files := Array(DirAccess.get_files_at(FACTIONS_DIR))
	files.sort()
	for file: String in files:
		if file.get_extension() == "tres":
			result.append(load(FACTIONS_DIR + file) as FactionDefinition)
	return result


func _triangles(node: Node) -> int:
	var count := 0
	for instance in _all_meshes(node):
		count += instance.mesh.get_faces().size() / 3
	return count


## MeshInstance3D nodes that are not below a Wheel* or Soldier* pivot.
func _body_mesh_instances(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		var pivot := String(child.name)
		if pivot.begins_with("Wheel") or pivot.begins_with("Soldier"):
			continue
		if child is MeshInstance3D:
			count += 1
		count += _body_mesh_instances(child)
	return count


func _first_camo(node: Node) -> ShaderMaterial:
	for instance in _all_meshes(node):
		if instance.material_override is ShaderMaterial:
			return instance.material_override
	return null


func test_model_files_exist_for_current_units() -> void:
	var ids := _model_ids()
	for id in KINDS:
		assert_true(id in ids, "missing model file for %s" % id)
	for id in ids:
		assert_true(KINDS.has(id), "model %s has no kind in KINDS (add it to this test)" % id)
	assert_true(_factions().size() >= 2)


func test_every_model_meets_the_contract_for_every_faction() -> void:
	for id in _model_ids():
		assert_true(UnitModels.has_model(id))
		var kind: StringName = KINDS.get(id, &"")
		for faction in _factions():
			var label := "%s/%s" % [id, faction.id]
			var root := UnitModels.build(id, 0, faction)
			var model := root.get_node("Model")
			var box := _bounds(root, Transform3D.IDENTITY)
			var triangles := _triangles(root)
			var body_meshes := _body_mesh_instances(model)
			print(
				(
					(
						"[model] %s: triangles=%d mesh_instances=%d body_mesh_instances=%d"
						+ " size=%.3fx%.3fx%.3f min_y=%.4f centre=(%.3f, %.3f)"
					)
					% [
						label,
						triangles,
						_all_meshes(root).size(),
						body_meshes,
						box.size.x,
						box.size.z,
						box.size.y,
						box.position.y,
						box.get_center().x,
						box.get_center().z,
					]
				)
			)
			var max_triangles := MAX_TRIANGLES_SQUAD if kind == &"squad" else MAX_TRIANGLES_VEHICLE
			var violated: Array[String] = []
			if absf(box.position.y) > GROUND_TOLERANCE:
				violated.append("ground")
			if absf(box.get_center().x) > CENTRE_TOLERANCE:
				violated.append("centre_x")
			if absf(box.get_center().z) > CENTRE_TOLERANCE:
				violated.append("centre_z")
			if box.size.x > MAX_LENGTH:
				violated.append("length")
			if box.size.z > MAX_WIDTH:
				violated.append("width")
			if triangles > max_triangles:
				violated.append("triangles")
			if body_meshes > MAX_BODY_MESH_INSTANCES:
				violated.append("body_meshes")
			_check_waivers(id, label, violated)
			_check_pivots(label, kind, model)
			root.free()


func _check_waivers(id: StringName, label: String, violated: Array[String]) -> void:
	var waived: Array = WAIVERS.get(id, [])
	for key in violated:
		assert_true(key in waived, "%s violates the contract check '%s'" % [label, key])
	for key: String in waived:
		assert_true(key in violated, "%s: waiver '%s' is obsolete, remove it" % [label, key])
	if not violated.is_empty():
		print("[model] %s waived violations: %s" % [label, violated])


func _check_pivots(label: String, kind: StringName, model: Node) -> void:
	if kind != &"squad":
		var wheels := 0
		for child in model.get_children():
			if String(child.name).begins_with("Wheel"):
				wheels += 1
		assert_true(wheels >= 4, "%s: needs >= 4 Wheel* pivots, has %d" % [label, wheels])
	if kind == &"tank":
		assert_true(model.get_node_or_null("Turret") is Node3D, "%s: needs Turret" % label)
	if kind == &"rocket_artillery":
		var pod := model.get_node_or_null("Pod") as Node3D
		assert_true(pod != null, "%s: needs Pod" % label)
		if pod != null:
			var mouths := 0
			for child in pod.get_children():
				var mouth := child as Node3D
				if String(child.name).begins_with("Mouth") and mouth != null:
					mouths += 1
					assert_true(
						mouth.position.x > 0.2, "%s: %s not on front face" % [label, child.name]
					)
			assert_true(mouths >= 6, "%s: needs >= 6 Mouth*, has %d" % [label, mouths])
	if kind == &"squad":
		for i in 5:
			var rig := model.get_node_or_null("Soldier%d/Rig" % i)
			assert_true(rig != null, "%s: Soldier%d needs a Rig" % [label, i])
			if rig != null and rig.get_node_or_null("Kneel") != null:
				assert_true(rig.get_node_or_null("Stand") != null, "%s: Soldier%d" % [label, i])


func test_same_faction_shares_meshes_other_faction_other_camo() -> void:
	var factions := _factions()
	for id in _model_ids():
		var a := UnitModels.build(id, 0, factions[0])
		var b := UnitModels.build(id, 1, factions[0])
		var c := UnitModels.build(id, 0, factions[1])
		var meshes_a := _all_meshes(a)
		var meshes_b := _all_meshes(b)
		assert_eq(meshes_a.size(), meshes_b.size())
		for i in meshes_a.size():
			assert_true(meshes_a[i].mesh == meshes_b[i].mesh, "%s mesh %d not shared" % [id, i])
			assert_true(meshes_a[i] != meshes_b[i], "%s: instances must be separate nodes" % id)
		var camo_a := _first_camo(a)
		assert_true(camo_a != null and camo_a == _first_camo(b), "%s: camo shared" % id)
		assert_true(camo_a != _first_camo(c), "%s: factions need different camo" % id)
		a.free()
		b.free()
		c.free()


func test_cached_copies_have_independent_node_trees() -> void:
	var faction := _faction(0)
	var a := UnitModels.build(&"infantry", 0, faction)
	var b := UnitModels.build(&"infantry", 0, faction)
	UnitModels.pose_infantry(a, 0.0, 0.0, true)
	assert_true((a.get_node("Model/Soldier1/Rig/Stand") as Node3D).visible)
	assert_false((b.get_node("Model/Soldier1/Rig/Stand") as Node3D).visible)
	var c := UnitModels.build(&"cavalry", 0, faction)
	var d := UnitModels.build(&"cavalry", 0, faction)
	UnitModels.pose_tank(c, 2.0, 1.0, Vector2.ZERO)
	assert_true((c.get_node("Model/Wheel0") as Node3D).rotation.z != 0.0)
	assert_eq((d.get_node("Model/Wheel0") as Node3D).rotation.z, 0.0)
	var part := _first_mesh(d.get_node("Model/Turret"))
	assert_true(part.get_instance_shader_parameter(&"part_origin") != null)
	for node: Node in [a, b, c, d]:
		node.free()


func test_model_cache_builds_once_per_key() -> void:
	var calls := [0]
	var builder := func() -> Node3D:
		calls[0] += 1
		return Node3D.new()
	var first := ModelParts.cached("test_key_once", builder)
	var second := ModelParts.cached("test_key_once", builder)
	assert_eq(calls[0], 1)
	assert_true(first != second)
	first.free()
	second.free()


func test_missing_model_file_builds_magenta_placeholder() -> void:
	assert_false(UnitModels.has_model(&"no_such_unit"))
	var model := UnitModels.build(&"no_such_unit", 0, _faction(0))
	var instance := _first_mesh(model)
	assert_true(instance != null)
	assert_eq((instance.material_override as StandardMaterial3D).albedo_color, Color.MAGENTA)
	model.free()


func _bounds(node: Node3D, to_root: Transform3D) -> AABB:
	var result := AABB()
	var has := false
	for child in node.get_children():
		var spatial := child as Node3D
		if spatial == null:
			continue
		var t := to_root * spatial.transform
		var box := AABB()
		var has_box := false
		var instance := spatial as MeshInstance3D
		if instance != null:
			box = t * instance.get_aabb()
			has_box = true
		var inner := _bounds(spatial, t)
		if inner.size != Vector3.ZERO:
			box = box.merge(inner) if has_box else inner
			has_box = true
		if has_box:
			result = result.merge(box) if has else box
			has = true
	return result


func _all_meshes(node: Node, into: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for child in node.get_children():
		if child is MeshInstance3D:
			into.append(child)
		_all_meshes(child, into)
	return into


func _first_mesh(node: Node) -> MeshInstance3D:
	var meshes := _all_meshes(node)
	return meshes[0] if not meshes.is_empty() else null


func _faction(owner_id: int) -> FactionDefinition:
	return FactionRegistry.get_faction(FactionRegistry.DEFAULT_IDS[owner_id])
