extends TestCase
## `--soldier=<i>` / `--soldier-yaw=<deg>` of tools/render_unit.sh and tools/compare_silhouette.sh:
## one soldier of a squad, alone, to judge or compare with a one-soldier reference GLB.

const RenderUnitOptions := preload("res://tools/render_unit_options.gd")


func _parse(args: Array) -> Dictionary:
	var model_exists := func(unit_id: StringName) -> bool: return unit_id == &"bare"
	return RenderUnitOptions.parse(
		PackedStringArray(args), "user://test_render_unit_soldier", model_exists
	)


func test_soldier_option_isolates_one_squad_slot() -> void:
	assert_eq(_parse(["bare"])["soldier"], -1)
	assert_eq(_parse(["bare", "--soldier=2"])["soldier"], 2)
	assert_eq(_parse(["bare", "--soldier=-1"])["error"], "invalid_soldier")
	assert_eq(_parse(["bare", "--soldier=x"])["error"], "invalid_soldier")
	assert_eq(_parse(["bare", "--soldier="])["error"], "empty_option")
	assert_eq(_parse(["bare"])["soldier_yaw"], 0.0)
	assert_eq(_parse(["bare", "--soldier=0", "--soldier-yaw=-15.5"])["soldier_yaw"], -15.5)
	assert_eq(_parse(["bare", "--soldier=0", "--soldier-yaw=left"])["error"], "invalid_soldier_yaw")
	assert_eq(_parse(["bare", "--soldier-yaw=15"])["error"], "invalid_soldier_yaw")
	# isolate_soldier: one soldier shown, at the origin, facing +X (turned by the yaw).
	var model := Node3D.new()
	for i in 3:
		var s := Node3D.new()
		s.name = "Soldier%d" % i
		s.position = Vector3(0.1 * i, 0.0, -0.2)
		s.rotation.y = 0.7
		model.add_child(s)
	var other := Node3D.new()
	other.name = "Vehicle"
	model.add_child(other)
	assert_true(RenderUnitOptions.isolate_soldier(model, 1))
	var kept := model.get_node("Soldier1") as Node3D
	assert_true(kept.visible)
	assert_eq(kept.position, Vector3.ZERO)
	assert_eq(kept.rotation.y, 0.0)
	assert_false((model.get_node("Soldier0") as Node3D).visible)
	assert_false((model.get_node("Soldier2") as Node3D).visible)
	assert_true(other.visible)
	assert_false(RenderUnitOptions.isolate_soldier(model, 5))
	assert_true(RenderUnitOptions.isolate_soldier(model, 2, 90.0))
	assert_true(absf((model.get_node("Soldier2") as Node3D).rotation.y - PI / 2.0) < 1e-5)
	assert_false(kept.visible)
	model.free()
