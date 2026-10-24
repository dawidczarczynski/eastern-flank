extends TestCase
## Launcher animation of rocket artillery with a turntable (Homar-K): traverse, elevation and the
## hydraulic actuators following the pod (UnitModels.pose_launcher / launcher_aim, at each
## model's launcher_elevation).


func _homar() -> Node3D:
	var model := UnitModels.build(&"homar_k", 0, FactionRegistry.get_faction(&"poland"))
	return model.get_node("Model") as Node3D


## Transform of `node` relative to `ancestor` (works outside the scene tree).
func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var current := node
	while current != ancestor and current != null:
		t = current.transform * t
		current = current.get_parent() as Node3D
	return t


func _mouth_centre(model: Node3D) -> Vector3:
	var pod := UnitModels.launcher_pod(model)
	var sum := Vector3.ZERO
	var count := 0
	for child in pod.get_children():
		if child.name.begins_with("Mouth"):
			sum += _relative(child as Node3D, model).origin
			count += 1
	return sum / count


func test_homar_has_launcher_with_pod_and_twelve_mouths() -> void:
	var model := _homar()
	assert_true(UnitModels.has_launcher(model))
	var pod := UnitModels.launcher_pod(model)
	assert_true(pod != null and pod.get_parent().name == "Launcher", "Pod under Launcher")
	if pod != null:
		for i in 12:
			assert_true(pod.get_node_or_null("Mouth%d" % i) != null, "missing Mouth%d" % i)
	model.get_parent().free()


func test_model_without_launcher_has_no_pod_and_posing_is_a_no_op() -> void:
	var root := UnitModels.build(&"m1a2_sepv3", 0, FactionRegistry.get_faction(&"poland"))
	var model := root.get_node("Model") as Node3D
	assert_false(UnitModels.has_launcher(model))
	assert_true(UnitModels.launcher_pod(model) == null)
	UnitModels.pose_launcher(model, 1.0, 0.5)  # no-op, must not crash
	root.free()


func test_stowed_pose_is_the_built_pose() -> void:
	var model := _homar()
	var pod := UnitModels.launcher_pod(model)
	var built := pod.transform
	UnitModels.pose_launcher(model, 1.2, UnitModels.launcher_elevation(model))
	UnitModels.pose_launcher(model, 0.0, 0.0)
	assert_true(pod.transform.is_equal_approx(built), "%s != %s" % [pod.transform, built])
	assert_true((model.get_node("Launcher") as Node3D).transform.basis.is_equal_approx(Basis()))
	model.get_parent().free()


func test_elevation_raises_the_tube_ends_and_keeps_the_hinge() -> void:
	var model := _homar()
	var pod := UnitModels.launcher_pod(model)
	var hinge := pod.position
	var stowed := _mouth_centre(model)
	UnitModels.pose_launcher(model, 0.0, UnitModels.launcher_elevation(model))
	var raised := _mouth_centre(model)
	assert_true(raised.y > stowed.y + 0.1, "raised %s vs stowed %s" % [raised, stowed])
	assert_true(pod.position.is_equal_approx(hinge), "the pod turns about its hinge")
	model.get_parent().free()


func test_actuators_connect_turntable_and_pod_and_extend_when_raised() -> void:
	var model := _homar()
	var launcher := model.get_node("Launcher") as Node3D
	var pod := UnitModels.launcher_pod(model)
	var lengths: Array[float] = []
	for elevation: float in [0.0, UnitModels.launcher_elevation(model)]:
		UnitModels.pose_launcher(model, 0.0, elevation)
		for i in 2:
			var barrel := launcher.get_node("Actuator%d" % i) as Node3D
			var rod := launcher.get_node("ActuatorRod%d" % i) as Node3D
			var mount := pod.transform * (pod.get_node("ActuatorMount%d" % i) as Node3D).position
			assert_true(rod.position.is_equal_approx(mount), "rod %d ends at its mount" % i)
			var axis := (mount - barrel.position).normalized()
			assert_true(barrel.basis.y.normalized().is_equal_approx(axis), "barrel %d aims" % i)
			assert_true(rod.basis.y.normalized().is_equal_approx(-axis), "rod %d aims" % i)
			if i == 0:
				lengths.append(barrel.position.distance_to(mount))
	assert_true(lengths[1] > lengths[0], "actuator extends: %s" % [lengths])
	model.get_parent().free()


func test_traverse_turns_the_tubes_towards_the_target_yaw() -> void:
	var model := _homar()
	var target_yaw := PI / 2.0
	var aim := UnitModels.launcher_aim(model, 0.0, target_yaw)
	assert_true(aim.distance_to(Vector2(0.0, -PI / 2.0)) < 0.001, "shortest turn: %s" % aim)
	UnitModels.pose_launcher(model, aim.y, UnitModels.launcher_elevation(model))
	var launcher := model.get_node("Launcher") as Node3D
	var direction := _mouth_centre(model) - launcher.position
	var flat := Vector2(direction.x, direction.z).normalized()
	var expected := Vector2(cos(target_yaw), -sin(target_yaw))
	assert_true(flat.is_equal_approx(expected), "tubes point %s, expected %s" % [flat, expected])
	model.get_parent().free()


## The Uragan's tubes are stowed facing forward over the cab (`stowed: front`) and traverse only
## ±30°: body turn + turntable angle together point the tubes at the target in every direction.
func test_uragan_aim_uses_the_models_stowed_direction_and_range() -> void:
	var root := UnitModels.build(&"bm27_uragan", 0, FactionRegistry.get_faction(&"russia"))
	var model := root.get_node("Model") as Node3D
	for target_yaw: float in [0.0, 0.3, PI / 2.0, -2.0, PI]:
		var aim := UnitModels.launcher_aim(model, 0.0, target_yaw)
		assert_true(absf(aim.y) <= deg_to_rad(30.0) + 0.0001, "within the range: %s" % aim)
		model.rotation.y = aim.x  # the body turn (on the model, as the unit pivot would)
		UnitModels.pose_launcher(model, aim.y, UnitModels.launcher_elevation(model))
		var launcher := model.get_node("Launcher") as Node3D
		var direction := model.basis * (_mouth_centre(model) - launcher.position)
		var flat := Vector2(direction.x, direction.z).normalized()
		var expected := Vector2(cos(target_yaw), -sin(target_yaw))
		assert_true(
			flat.distance_to(expected) < 0.05, "tubes point %s, expected %s" % [flat, expected]
		)
	root.free()


func test_full_traverse_is_wrapped_to_the_shortest_turn() -> void:
	assert_true(absf(absf(UnitModels.traverse_aim("full", PI, 0.0, 0.0).y) - PI) < 0.001)
	assert_true(absf(UnitModels.traverse_aim("full", PI, PI, 0.0).y) < 0.001)
	assert_true(absf(UnitModels.traverse_aim("full", PI, 0.3, 0.3 + PI - 0.2).y + 0.2) < 0.001)
