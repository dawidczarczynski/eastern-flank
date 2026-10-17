extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")


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
	var model := UnitModels.build(id, owner_id)
	var box := _bounds(model, Transform3D.IDENTITY)
	assert_true(box.size.y > 0.15, "%s too short: %s" % [id, box])
	assert_true(absf(box.position.y) <= 0.02, "%s not on y=0: %s" % [id, box])
	model.free()


func test_models_stand_upright_on_origin() -> void:
	for owner_id in 2:
		_check_upright(&"infantry", owner_id)
		_check_upright(&"cavalry", owner_id)


func test_owner_sets_facing() -> void:
	var west := UnitModels.build(&"infantry", 0)
	var east := UnitModels.build(&"infantry", 1)
	assert_true(absf(west.rotation.y) < 0.0001)
	assert_true(absf(east.rotation.y - PI) < 0.0001)
	west.free()
	east.free()


func test_meshes_are_shared_between_instances() -> void:
	var a := UnitModels.build(&"cavalry", 0)
	var b := UnitModels.build(&"cavalry", 0)
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
	var model := UnitModels.build(&"infantry", 0)
	assert_eq(_count_soldiers(model), 5)
	model.free()


func test_unknown_id_returns_fallback_node() -> void:
	var model := UnitModels.build(&"no_such_unit", 0)
	assert_true(model != null)
	assert_true(_first_mesh(model) != null)
	model.free()


func test_hit_reset_leaves_no_flash_behind() -> void:
	var state := GameState.new(Fixtures.plains_grid(2), 2, 1)
	var unit := state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	var hud := Control.new()
	var view := UnitView.new()
	view.setup(unit, Vector3.ZERO, hud, Callable())
	var flash := UnitView._get_flash_material()
	view._set_overlay(flash)
	flash.albedo_color.a = 0.5
	view._reset_hit()
	assert_true(view._meshes[0].material_overlay == null)
	assert_eq(flash.albedo_color.a, 0.0)
	view.free()
	hud.free()
