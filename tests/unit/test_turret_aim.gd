extends TestCase
## Turret traverse mechanism (TASK-047): turret aim, gun elevation, the turret pose of a model and
## the direct-fire event annotation.

const Contract := preload("res://tests/mechanism_contract.gd")
const Battle := preload("res://src/presentation/battle_controller.gd")
const TOL := 0.0001
const ELEVATION := [-9, 20]


## Synthetic tank: Turret (offset) / Gun (hinge) / Muzzle in front, declaring turret_traverse.
func _tank(elevation: Array = ELEVATION, with_gun: bool = true) -> Node3D:
	var root := Node3D.new()
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	var params := {"traverse_deg": "full", "elevation_deg": elevation}
	model.set_meta(&"mechanisms", {"turret_traverse": params})
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0.1, 0.2, 0.0)
	model.add_child(turret)
	if with_gun:
		var gun := Node3D.new()
		gun.name = "Gun"
		gun.position = Vector3(0.05, 0.1, 0.0)
		turret.add_child(gun)
		var muzzle := Node3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = Vector3(0.5, 0.0, 0.0)
		gun.add_child(muzzle)
	return root


func test_gun_elevation_follows_the_target_and_clamps() -> void:
	var tank := _tank(ELEVATION)
	var down := UnitModels.gun_elevation(tank, Vector3(0, 0.5, 0), Vector3(1, 0.4, 0))
	assert_true(absf(rad_to_deg(down) + 5.711) < 0.01, "%.3f" % rad_to_deg(down))
	var clamped := UnitModels.gun_elevation(_tank([-3, 20]), Vector3(0, 0.5, 0), Vector3(1, 0.4, 0))
	assert_true(absf(rad_to_deg(clamped) + 3.0) < 0.01, "depression limit")
	var up := UnitModels.gun_elevation(tank, Vector3(0, 0.5, 0), Vector3(1, 1.0, 0))
	assert_true(absf(rad_to_deg(up) - 20.0) < 0.01, "elevation limit")
	var sideways := UnitModels.gun_elevation(tank, Vector3.ZERO, Vector3(0.0, 0.0, 2.0))
	assert_true(absf(sideways) < TOL, "horizontal distance uses x and z")
	tank.free()


func test_turret_aim_full_and_limited() -> void:
	var tank := _tank()
	var aim := UnitModels.turret_aim(tank, 0.0, deg_to_rad(135.0))
	assert_true(absf(aim.x) < TOL and absf(aim.y - deg_to_rad(135.0)) < TOL, str(aim))
	assert_false(UnitModels.turret_limited(tank))
	tank.free()
	var limited := _tank()
	limited.get_node("Model").set_meta(
		&"mechanisms", {"turret_traverse": {"traverse_deg": [-30, 30]}}
	)
	assert_true(UnitModels.turret_limited(limited))
	var turned := UnitModels.turret_aim(limited, 0.0, deg_to_rad(90.0))
	assert_true(absf(turned.x - deg_to_rad(60.0)) < TOL, str(turned))
	assert_true(absf(turned.y - deg_to_rad(30.0)) < TOL, str(turned))
	limited.free()


## Model-space position of a point of the Muzzle / Gun / Turret chain (nodes outside a tree have
## no global transform).
func _in_model(model: Node3D, path: String) -> Vector3:
	var turret := model.get_node("Turret") as Node3D
	var gun := turret.get_node("Gun") as Node3D
	match path:
		"Turret":
			return turret.transform.origin
		"Gun":
			return (turret.transform * gun.transform).origin
		_:
			var muzzle := gun.get_node("Muzzle") as Node3D
			return turret.transform * gun.transform * muzzle.position


func test_pose_turret_turns_the_muzzle_and_keeps_the_hinge() -> void:
	var tank := _tank()
	var model := tank.get_node("Model") as Node3D
	var built_muzzle := _in_model(model, "Muzzle")
	var built_gun := _in_model(model, "Gun")
	UnitModels.pose_turret(model, 0.0, 0.0)
	assert_true(_in_model(model, "Muzzle").is_equal_approx(built_muzzle), "(0, 0) is built")
	UnitModels.pose_turret(model, PI / 2.0, 0.0)
	var offset := _in_model(model, "Muzzle") - _in_model(model, "Gun")
	assert_true(offset.is_equal_approx(Vector3(0.0, 0.0, -0.5)), "+X -> -Z: %s" % offset)
	assert_true(_in_model(model, "Turret").is_equal_approx(Vector3(0.1, 0.2, 0.0)), "turret fixed")
	UnitModels.pose_turret(model, 0.0, deg_to_rad(10.0))
	assert_true(_in_model(model, "Muzzle").y > built_muzzle.y + 0.05, "elevation raises it")
	assert_true(_in_model(model, "Gun").is_equal_approx(built_gun), "the Gun origin stays")
	UnitModels.pose_turret(model, 0.0, 0.0)
	assert_true(_in_model(model, "Muzzle").is_equal_approx(built_muzzle), "back to built")
	tank.free()


func test_pose_turret_without_a_gun_is_a_no_op() -> void:
	var bare := _tank(ELEVATION, false)
	assert_false(UnitModels.has_turret(bare))
	UnitModels.pose_turret(bare, 1.0, 0.5)
	assert_true((bare.get_node("Model/Turret") as Node3D).rotation.is_zero_approx())
	bare.free()


func test_the_tanks_have_a_turret() -> void:
	for id in [&"m1a2_sepv3", &"t72b3"]:
		var root := UnitModels.build(id, 0, FactionRegistry.get_faction(&"poland"))
		assert_true(UnitModels.has_turret(root), str(id))
		root.free()
	var homar := UnitModels.build(&"homar_k", 0, FactionRegistry.get_faction(&"poland"))
	assert_false(UnitModels.has_turret(homar))
	homar.free()


func test_a_turret_without_a_muzzle_violates_the_contract() -> void:
	var registry := Contract.load_registry()
	var tank := _tank()
	var model := tank.get_node("Model") as Node3D
	assert_eq(Contract.pivot_violations(model, registry["turret_traverse"]).size(), 0)
	var muzzle := model.get_node("Turret/Gun/Muzzle")
	muzzle.get_parent().remove_child(muzzle)
	muzzle.free()
	var violations := Contract.pivot_violations(model, registry["turret_traverse"])
	assert_eq(violations.size(), 1, str(violations))
	assert_true("Turret/Gun/Muzzle" in violations[0], str(violations))
	tank.free()


func test_turret_defaults_match_the_registry() -> void:
	var params: Dictionary = Contract.load_registry()["turret_traverse"]["params"]
	var defaults := {}
	for key: String in params:
		defaults[key] = params[key]["default"]
	assert_eq(
		Contract.normalise(UnitModels.TURRET_DEFAULTS), Contract.normalise(defaults), "defaults"
	)


func test_direct_fire_duration() -> void:
	assert_true(absf(Battle._direct_fire_duration(false) - 1.4) < TOL)
	assert_true(absf(Battle._direct_fire_duration(true) - 1.9) < TOL)
	assert_true(absf(EventQueue.ATTACK_DURATION - 0.4) < TOL, "units without a turret stay at 0.4")
