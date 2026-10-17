extends TestCase

const TOL := 0.001


func _near(a: float, b: float, msg := "") -> void:
	assert_true(absf(a - b) <= TOL, "%s expected %s got %s" % [msg, b, a])


func _path() -> PackedVector3Array:
	return PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 2)])


func test_travelled() -> void:
	var p := _path()
	_near(Locomotion.travelled(p, 0.0), 0.0)
	_near(Locomotion.travelled(p, 0.13), 0.5)
	_near(Locomotion.travelled(p, 0.39), 2.0)
	_near(Locomotion.travelled(p, 10.0), 3.0)
	_near(Locomotion.travelled(PackedVector3Array([Vector3.ZERO]), 1.0), 0.0)
	var tall := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 5, 0)])
	_near(Locomotion.travelled(tall, 0.26), 1.0)


func test_envelope() -> void:
	_near(Locomotion.envelope(0.0, 0.78), 0.0)
	_near(Locomotion.envelope(0.04, 0.78), 0.5)
	_near(Locomotion.envelope(0.39, 0.78), 1.0)
	_near(Locomotion.envelope(0.74, 0.78), 0.5)
	_near(Locomotion.envelope(0.78, 0.78), 0.0)
	_near(Locomotion.envelope(1.0, 0.78), 0.0)
	_near(Locomotion.envelope(0.1, 0.0), 0.0)


func test_step_phase() -> void:
	var distinct := {}
	for i in 5:
		var v := Locomotion.step_phase(i)
		assert_eq(v, TerrainNoise.hash(i, 11.0, 4.0))
		assert_true(v >= 0.0 and v < 1.0)
		assert_eq(v, Locomotion.step_phase(i))
		distinct[v] = true
	assert_true(distinct.size() > 1)


func test_step_bob_and_sway() -> void:
	_near(Locomotion.step_bob(0.0, 0.0), 0.0)
	_near(Locomotion.step_bob(1.0 / 3.0, 0.0), 0.012)
	_near(Locomotion.step_bob(2.0 / 3.0, 0.0), 0.0)
	_near(Locomotion.step_sway(1.0 / 3.0, 0.0), 0.06)
	_near(Locomotion.step_sway(1.0, 0.0), -0.06)
	_near(Locomotion.step_bob(0.0, 0.5), 0.012)
	for k in 101:
		assert_true(Locomotion.step_bob(k * 0.05, 0.3) >= 0.0)


func test_wheel_angle() -> void:
	_near(Locomotion.wheel_angle(0.0), 0.0)
	_near(Locomotion.wheel_angle(1.0), -5.0)
	_near(Locomotion.wheel_angle(1.732), -8.66)


func test_hull_bob() -> void:
	var b := Locomotion.hull_bob(0.0)
	_near(b.x, 0.0)
	_near(b.y, 0.008 * sin(1.3))
	for k in 101:
		var v := Locomotion.hull_bob(k * 0.05)
		assert_true(absf(v.x) <= 0.012 + 0.000001 and absf(v.y) <= 0.008 + 0.000001)


func test_slope_tilt() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var ramp := func(x: float, _z: float) -> float: return 0.2 * x
	var side := func(_x: float, z: float) -> float: return -0.1 * z
	var steep := func(x: float, _z: float) -> float: return 2.0 * x
	assert_eq(Locomotion.slope_tilt(flat, Vector3.ZERO, 0.0), Vector2.ZERO)
	var t := Locomotion.slope_tilt(ramp, Vector3.ZERO, 0.0)
	_near(t.x, 0.1974)
	_near(t.y, 0.0)
	_near(Locomotion.slope_tilt(ramp, Vector3.ZERO, PI).x, -0.1974)
	t = Locomotion.slope_tilt(ramp, Vector3.ZERO, PI / 2.0)
	_near(t.x, 0.0)
	_near(t.y, -0.1974)
	t = Locomotion.slope_tilt(side, Vector3.ZERO, 0.0)
	_near(t.x, 0.0)
	_near(t.y, 0.0997)
	_near(Locomotion.slope_tilt(steep, Vector3.ZERO, 0.0).x, 0.35)


func test_infantry_structure() -> void:
	var root := UnitModels.build(&"infantry", 0)
	for i in 5:
		var rig := root.get_node_or_null("Model/Soldier%d/Rig" % i)
		assert_true(rig != null)
		var kneel := rig.get_node_or_null("Kneel")
		var stand := rig.get_node_or_null("Stand")
		if i == 1 or i == 4:
			assert_true(kneel != null and kneel.visible)
			assert_true(stand != null and not stand.visible)
		else:
			assert_true(kneel == null and stand == null)
	root.free()


func test_tank_structure() -> void:
	var root := UnitModels.build(&"cavalry", 0)
	for i in 12:
		var pivot := root.get_node_or_null("Model/Wheel%d" % i)
		assert_true(pivot != null)
		assert_eq(pivot.get_child_count(), 2)
	root.free()


func test_pose_infantry() -> void:
	var root := UnitModels.build(&"infantry", 0)
	UnitModels.pose_infantry(root, 1.0 / 3.0, 1.0, true)
	var rig: Node3D = root.get_node("Model/Soldier0/Rig")
	_near(rig.position.y, 0.012 * absf(sin(PI * (0.5 + Locomotion.step_phase(0)))))
	_near(rig.rotation.z, -0.08)
	assert_true((root.get_node("Model/Soldier1/Rig/Stand") as Node3D).visible)
	assert_true(not (root.get_node("Model/Soldier1/Rig/Kneel") as Node3D).visible)
	UnitModels.pose_infantry(root, 0.0, 0.0, false)
	for i in 5:
		assert_true(
			(root.get_node("Model/Soldier%d/Rig" % i) as Node3D).transform == Transform3D.IDENTITY
		)
	assert_true((root.get_node("Model/Soldier4/Rig/Kneel") as Node3D).visible)
	assert_true(not (root.get_node("Model/Soldier4/Rig/Stand") as Node3D).visible)
	root.free()


func test_pose_tank() -> void:
	var root := UnitModels.build(&"cavalry", 0)
	UnitModels.pose_tank(root, 1.0, 1.0, Vector2.ZERO)
	for i in 12:
		_near((root.get_node("Model/Wheel%d" % i) as Node3D).rotation.z, -5.0)
	var model: Node3D = root.get_node("Model")
	UnitModels.pose_tank(root, 3.7, 0.0, Vector2(0.1, -0.05))
	_near(model.rotation.z, 0.1, "no bob residue")
	_near(model.rotation.x, -0.05, "no bob residue")
	UnitModels.pose_tank(root, 3.7, 0.0, Vector2.ZERO)
	assert_eq(model.rotation, Vector3.ZERO)
	root.free()
