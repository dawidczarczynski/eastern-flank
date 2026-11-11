extends TestCase
## Strike weapon models (TASK-144): WeaponModels registry, the JASSM-ER model against its catalog
## entry (docs/design/units/weapons/jassm_er/unit.json) and the WeaponTurntable smoke test.

const CATALOG := "res://docs/design/units/weapons/%s/unit.json"
const TOLERANCE := 0.05


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


func _meshes(node: Node, into: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for child in node.get_children():
		if child is MeshInstance3D:
			into.append(child)
		_meshes(child, into)
	return into


func _catalog_dimensions(means_id: StringName) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG % means_id))
	assert_true(parsed is Dictionary, "%s catalog entry is readable" % means_id)
	return (parsed as Dictionary).get("dimensions", {}) if parsed is Dictionary else {}


func _assert_close(actual: float, expected: float, label: String) -> void:
	assert_true(
		absf(actual - expected) <= expected * TOLERANCE,
		"%s: model %.3f m vs catalog %.3f m (±5 %%)" % [label, actual, expected]
	)


func test_registry_knows_jassm_and_returns_null_without_a_model() -> void:
	assert_true(WeaponModels.has_model(&"jassm_er"))
	assert_false(WeaponModels.has_model(&"warmate"))
	assert_false(WeaponModels.has_model(&""))
	assert_eq(WeaponModels.build(&"warmate"), null)


func test_every_registered_weapon_is_a_strike_means_with_a_catalog_entry() -> void:
	for means_id: StringName in WeaponModels.MODELS:
		assert_true(
			ResourceLoader.exists("res://data/strike/%s.tres" % means_id),
			"%s is a strike means" % means_id
		)
		assert_true(FileAccess.file_exists(CATALOG % means_id), "%s has a catalog entry" % means_id)


func test_jassm_bounding_box_matches_the_catalog() -> void:
	var model := WeaponModels.build(&"jassm_er")
	assert_true(model != null, "jassm_er builds")
	if model == null:
		return
	var box := _bounds(model, Transform3D.IDENTITY)
	var real := _catalog_dimensions(&"jassm_er")
	_assert_close(box.size.x, float(real.get("overall_length", 0.0)), "length")
	_assert_close(box.size.z, float(real.get("width", 0.0)), "span")
	_assert_close(box.size.y, float(real.get("height", 0.0)), "height")
	# Origin at the centre of mass: inside the body, not at an end.
	assert_true(box.position.x < -1.5 and box.end.x > 1.5, "origin near the middle: %s" % box)
	assert_true(absf(box.get_center().z) < 0.01, "symmetric across: %s" % box)
	model.free()


func test_jassm_nose_points_along_plus_x_and_stays_in_budget() -> void:
	var model := WeaponModels.build(&"jassm_er")
	var triangles := 0
	var front_width := 0.0
	var back_width := 0.0
	var box := _bounds(model, Transform3D.IDENTITY)
	for instance in _meshes(model):
		var faces := instance.mesh.get_faces()
		triangles += faces.size() / 3
		for p in faces:
			if p.x > box.end.x - 0.05:
				front_width = maxf(front_width, absf(p.z))
			if p.x < box.position.x + 0.05:
				back_width = maxf(back_width, absf(p.z))
	assert_true(
		triangles <= WeaponModels.MAX_TRIANGLES,
		"jassm_er: %d triangles > %d" % [triangles, WeaponModels.MAX_TRIANGLES]
	)
	assert_true(
		front_width < back_width,
		"the narrow nose is at +X (front %.2f, back %.2f)" % [front_width, back_width]
	)
	model.free()


func test_copies_are_independent() -> void:
	var a := WeaponModels.build(&"jassm_er")
	var b := WeaponModels.build(&"jassm_er")
	assert_true(a != b, "every build is a new node tree")
	a.free()
	b.free()


func test_turntable_smoke_with_and_without_a_model() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var turntable := WeaponTurntable.new()
	tree.root.add_child(turntable)
	assert_eq(
		turntable.viewport.render_target_update_mode, SubViewport.UPDATE_WHEN_VISIBLE, "update mode"
	)
	assert_false(turntable.light.shadow_enabled, "no shadows")
	assert_true(turntable.show_weapon(&"jassm_er"), "jassm_er has a model")
	assert_true(turntable.model != null and turntable.model.get_parent() == turntable.spinner)
	var yaw := turntable.spinner.rotation.y
	turntable.spin(1.0)
	assert_true(
		is_equal_approx(turntable.spinner.rotation.y - yaw, TAU / WeaponTurntable.SPIN_SECONDS),
		"one turn per %s s" % WeaponTurntable.SPIN_SECONDS
	)
	# Fitted: the whole spinning model stays in front of the camera.
	var distance := turntable.camera.position.length()
	assert_true(distance > 2.4 and distance < 40.0, "camera distance %.2f" % distance)
	assert_false(turntable.show_weapon(&"warmate"), "warmate has no model")
	assert_eq(turntable.model, null)
	turntable.spin(1.0)
	turntable.hide()
	assert_true(turntable.show_weapon(&"jassm_er"))
	yaw = turntable.spinner.rotation.y
	turntable._process(1.0)
	assert_eq(turntable.spinner.rotation.y, yaw, "no spin while hidden")
	turntable.free()
