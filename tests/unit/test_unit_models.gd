# gdlint: disable=max-public-methods
extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const CAMO_SHADER := "res://assets/shaders/camo.gdshader"
const Soldier := preload("res://src/presentation/models/parts/soldier.gd")


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


func _check_upright(id: StringName, owner_id: int) -> void:
	var model := UnitModels.build(id, owner_id, _faction(owner_id))
	var box := _bounds(model, Transform3D.IDENTITY)
	assert_true(box.size.y > 0.15, "%s too short: %s" % [id, box])
	assert_true(absf(box.position.y) <= 0.02, "%s not on y=0: %s" % [id, box])
	model.free()


func test_models_stand_upright_on_origin() -> void:
	for owner_id in 2:
		_check_upright(&"pl_mech_infantry", owner_id)
		_check_upright(&"m1a2_sepv3", owner_id)
		_check_upright(&"homar_k", owner_id)


func test_launchers_have_a_pod_with_mouths_and_no_placeholder() -> void:
	for id in [&"homar_k", &"bm27_uragan"]:
		var model := UnitModels.build(id, 0, _faction(0))
		var pod := UnitModels.launcher_pod(model)
		assert_true(pod != null, "%s needs a Pod node" % id)
		assert_true(pod.get_node_or_null("Mouth0") != null, "%s: missing Mouth0" % id)
		model.free()


func test_vehicles_use_wheel_locomotion() -> void:
	assert_true(UnitModels.is_vehicle(load("res://data/units/m1a2_sepv3.tres")))
	assert_true(UnitModels.is_vehicle(load("res://data/units/homar_k.tres")))
	assert_false(UnitModels.is_vehicle(load("res://data/units/pl_mech_infantry.tres")))
	assert_false(UnitModels.is_vehicle(null))
	var model := UnitModels.build(&"homar_k", 1, _faction(1))
	UnitModels.pose_tank(model.get_node("Model"), 2.0, 1.0, Vector2.ZERO)
	assert_true(model.get_node("Model/Wheel0").rotation.z != 0.0, "wheels should spin")
	model.free()


func test_owner_sets_facing() -> void:
	var west := UnitModels.build(&"pl_mech_infantry", 0, _faction(0))
	var east := UnitModels.build(&"pl_mech_infantry", 1, _faction(1))
	assert_true(absf(west.rotation.y) < 0.0001)
	assert_true(absf(east.rotation.y - PI) < 0.0001)
	west.free()
	east.free()


func test_meshes_are_shared_between_instances() -> void:
	var a := UnitModels.build(&"m1a2_sepv3", 0, _faction(0))
	var b := UnitModels.build(&"m1a2_sepv3", 0, _faction(0))
	var ma := _first_mesh(a)
	var mb := _first_mesh(b)
	assert_true(ma.mesh == mb.mesh and ma.material_override == mb.material_override)
	a.free()
	b.free()


func _first_mesh(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _count_soldiers(model: Node3D) -> int:
	# Infantry: root -> "Model" -> one Node3D per soldier.
	return model.get_node("Model").get_child_count()


func test_infantry_has_five_soldiers() -> void:
	var model := UnitModels.build(&"pl_mech_infantry", 0, _faction(0))
	assert_eq(_count_soldiers(model), 5)
	model.free()


func test_unknown_id_returns_fallback_node() -> void:
	var model := UnitModels.build(&"no_such_unit", 0, _faction(0))
	assert_true(model != null)
	assert_true(_first_mesh(model) != null)
	model.free()


func test_hit_reset_leaves_no_flash_behind() -> void:
	var state := GameState.new(Fixtures.plains_grid(2), 2, 1)
	var unit := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	var hud := Control.new()
	var view := UnitView.new()
	view.setup(unit, state.faction_of(0), Vector3.ZERO, hud, Callable())
	var flash := UnitView._get_flash_material()
	view._set_overlay(flash)
	flash.albedo_color.a = 0.5
	view._reset_hit()
	assert_true(view._meshes[0].material_overlay == null)
	assert_eq(flash.albedo_color.a, 0.0)
	view.free()
	hud.free()


func test_faction_colours_models_and_null_is_neutral() -> void:
	var poland := _faction(0)
	var tank := UnitModels.build(&"m1a2_sepv3", 0, poland)
	var turret_mat := _first_mesh(tank.get_node("Model/Turret")).material_override
	assert_eq((turret_mat as ShaderMaterial).get_shader_parameter(&"color_a"), poland.camo[0])
	var neutral_tank := UnitModels.build(&"m1a2_sepv3", 1, null)
	var neutral_mat := _first_mesh(neutral_tank.get_node("Model/Turret")).material_override
	assert_eq(
		(neutral_mat as ShaderMaterial).get_shader_parameter(&"color_a"), ModelParts.NEUTRAL_BODY
	)
	tank.free()
	neutral_tank.free()


func test_faction_materials_are_shared_per_faction_not_owner() -> void:
	var a := UnitModels.build(&"m1a2_sepv3", 0, _faction(0))
	var b := UnitModels.build(&"m1a2_sepv3", 1, _faction(0))
	var c := UnitModels.build(&"m1a2_sepv3", 0, _faction(1))
	var mat_a := _first_mesh(a.get_node("Model/Turret")).material_override
	assert_true(mat_a == _first_mesh(b.get_node("Model/Turret")).material_override)
	assert_true(mat_a != _first_mesh(c.get_node("Model/Turret")).material_override)
	a.free()
	b.free()
	c.free()


func _camo_of(instance: MeshInstance3D) -> ShaderMaterial:
	return instance.material_override as ShaderMaterial


func _all_meshes(node: Node, into: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for child in node.get_children():
		if child is MeshInstance3D:
			into.append(child)
		_all_meshes(child, into)
	return into


func test_tank_hull_uses_faction_camo_shader() -> void:
	for owner_id in 2:
		var faction := _faction(owner_id)
		var tank := UnitModels.build(&"m1a2_sepv3", owner_id, faction)
		var hull := _camo_of(_first_mesh(tank.get_node("Model/Turret")))
		assert_true(hull != null, "turret should use a ShaderMaterial")
		assert_eq(hull.shader.resource_path, CAMO_SHADER)
		assert_eq(hull.get_shader_parameter(&"color_a"), faction.camo[0])
		assert_eq(hull.get_shader_parameter(&"color_b"), faction.camo[1])
		assert_eq(hull.get_shader_parameter(&"color_c"), faction.camo[2])
		assert_eq(hull.get_shader_parameter(&"pattern_scale"), 9.0)
		tank.free()
	assert_eq(_faction(0).camo[0].to_html(false), "4b5320")
	assert_eq(_faction(1).camo[0].to_html(false), "4d5a3a")


func test_infantry_torso_uses_fine_uniform_camo() -> void:
	var model := UnitModels.build(&"pl_mech_infantry", 1, _faction(1))
	var patterned := 0
	var plain := 0
	for instance in _all_meshes(model):
		var m := instance.material_override as ShaderMaterial
		if m == null:
			continue
		if m.get_shader_parameter(&"color_a") == m.get_shader_parameter(&"color_b"):
			plain += 1  # weathered one-colour gear paint (boots, gloves, straps)
			continue
		patterned += 1
		assert_eq(m.get_shader_parameter(&"pattern_scale"), ModelParts.CAMO_UNIFORM["scale"])
		assert_eq(m.get_shader_parameter(&"color_a"), _faction(1).camo[0])
	assert_true(patterned > 0, "uniform parts should use camo")
	assert_true(plain > 0, "boots and gloves should use the weathered gear paint")
	model.free()


## TASK-067: the soldiers' bodies are smooth MeshKit meshes (swept limbs and torso, pillows), not
## merged box / cylinder primitives.
func test_soldier_bodies_are_smooth_kit_meshes() -> void:
	for id in [&"pl_mech_infantry", &"ru_motor_rifle"]:
		var faction := _faction(0)
		var mats := Soldier.materials(faction)
		var model := UnitModels.build(id, 0, faction)
		var body_meshes := 0
		for instance in _all_meshes(model):
			assert_false(instance.mesh is PrimitiveMesh, "%s: %s" % [id, instance.mesh])
			var role: Variant = mats.find_key(instance.material_override)
			if role == null or not role in Soldier.BODY_ROLES:
				continue
			body_meshes += 1
			var mesh := instance.mesh as ArrayMesh
			assert_true(mesh != null, "%s %s is an ArrayMesh" % [id, role])
			var arrays := mesh.surface_get_arrays(0)
			assert_true(arrays[Mesh.ARRAY_INDEX] == null, "%s %s: written by MeshKit" % [id, role])
			assert_false((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).is_empty())
			if role != &"dark":
				var smooth := _smooth_fraction(arrays)
				assert_true(smooth > 0.7, "%s %s smooth vertices: %.2f" % [id, role, smooth])
		assert_true(body_meshes >= 15, "%s: body meshes %d" % [id, body_meshes])
		model.free()


## Share of vertices (non-indexed triangles) whose normal differs from the face normal by > 2°.
func _smooth_fraction(arrays: Array) -> float:
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var smooth := 0
	for t in range(0, verts.size(), 3):
		var face := (verts[t + 2] - verts[t]).cross(verts[t + 1] - verts[t]).normalized()
		for i in 3:
			if absf(face.dot(normals[t + i])) < cos(deg_to_rad(2.0)):
				smooth += 1
	return float(smooth) / verts.size()


func test_camo_materials_shared_per_faction_and_preset() -> void:
	var a := UnitModels.build(&"m1a2_sepv3", 0, _faction(0))
	var b := UnitModels.build(&"m1a2_sepv3", 0, _faction(0))
	var ia := UnitModels.build(&"pl_mech_infantry", 0, _faction(0))
	var ta := _camo_of(_first_mesh(a.get_node("Model/Turret")))
	assert_true(ta == _camo_of(_first_mesh(b.get_node("Model/Turret"))))
	var soldier_mat := _camo_of(_first_mesh(ia))
	assert_true(soldier_mat != ta, "vehicle and uniform presets differ")
	a.free()
	b.free()
	ia.free()


func test_vests_stay_plain_standard_materials() -> void:
	var model := UnitModels.build(&"pl_mech_infantry", 0, _faction(0))
	var found := false
	for instance in _all_meshes(model):
		var m := instance.material_override as StandardMaterial3D
		if m != null and m.albedo_color == _faction(0).vest_color:
			found = true
	assert_true(found, "vest should be a StandardMaterial3D in vest_color")
	model.free()


func test_some_part_is_steel() -> void:
	for id in [&"m1a2_sepv3", &"homar_k"]:
		var model := UnitModels.build(id, 0, _faction(0))
		var steel := false
		for instance in _all_meshes(model):
			var m := instance.material_override as StandardMaterial3D
			if m != null and m.metallic >= 0.7 and m.roughness <= 0.45:
				steel = true
		assert_true(steel, "%s needs a steel part" % id)
		model.free()


func test_glass_on_launcher_windscreen() -> void:
	var model := UnitModels.build(&"homar_k", 0, _faction(0))
	var glass := false
	for instance in _all_meshes(model):
		var m := instance.material_override as StandardMaterial3D
		if m != null and m.roughness <= 0.1 and m.metallic >= 0.89:
			glass = true
	assert_true(glass)
	model.free()


func test_part_origin_makes_pattern_continuous() -> void:
	var tank := UnitModels.build(&"m1a2_sepv3", 0, _faction(0))
	var turret_part := _first_mesh(tank.get_node("Model/Turret"))
	var origin: Vector3 = turret_part.get_instance_shader_parameter(&"part_origin")
	assert_true(origin.y > 0.1, "turret parts are offset by the turret pivot: %s" % origin)
	tank.free()


func test_camo_shader_exposes_both_pattern_modes() -> void:
	var material := ShaderMaterial.new()
	material.shader = load(CAMO_SHADER)
	assert_true(material.shader != null)
	assert_eq(material.get_shader_parameter(&"pattern_mode"), null)
	for mode in [0, 1]:
		material.set_shader_parameter(&"pattern_mode", mode)
		assert_eq(material.get_shader_parameter(&"pattern_mode"), mode)
	assert_true(material.shader.get_shader_uniform_list().size() >= 9)


func test_hit_reset_works_on_camo_surfaces() -> void:
	var state := GameState.new(Fixtures.plains_grid(2), 2, 1)
	var definition := Fixtures.infantry()
	definition.id = &"pl_mech_infantry"
	var unit := state.add_unit(0, definition, Vector2i(0, 0))
	var hud := Control.new()
	var view := UnitView.new()
	view.setup(unit, state.faction_of(0), Vector3.ZERO, hud, Callable())
	var flash := UnitView._get_flash_material()
	view._set_overlay(flash)
	var camo_surfaces := 0
	var before: Array[Material] = []
	for instance in view._meshes:
		assert_true(instance.material_overlay == flash)
		before.append(instance.material_override)
		if instance.material_override is ShaderMaterial:
			camo_surfaces += 1
	assert_true(camo_surfaces > 0)
	view._reset_hit()
	for i in view._meshes.size():
		var instance: MeshInstance3D = view._meshes[i]
		assert_true(instance.material_overlay == null)
		assert_true(instance.material_override == before[i], "camo kept after the hit reset")
	view.free()
	hud.free()


## Every unit in data/units has its own model file (no stand-ins); the vehicles drive.
func test_every_unit_has_its_own_model_and_vehicles_drive() -> void:
	for file in DirAccess.get_files_at("res://data/units"):
		if file.ends_with(".tres"):
			var definition := load("res://data/units/" + file) as UnitDefinition
			assert_true(UnitModels.has_model(definition.id), "%s has a model" % definition.id)
			assert_eq(UnitModels.is_vehicle(definition), definition.mobility != &"foot", file)


func _faction(owner_id: int) -> FactionDefinition:
	return FactionRegistry.get_faction(FactionRegistry.DEFAULT_IDS[owner_id])
