extends TestCase
## Deploy step before a volley (TASK-045): stabiliser jacks and blast shields interpolate between
## their built (stowed) and `deployed` transforms (UnitModels.pose_deployables), the volley event
## grows by the deploy and stow steps, and the stabiliser contract helper catches bad feet.

const Contract := preload("res://tests/mechanism_contract.gd")
const Battle := preload("res://src/presentation/battle_controller.gd")
const TOL := 0.00001


func _jack(root: Node3D, name: String, built_y: float, deployed_y: float) -> Node3D:
	var jack := Node3D.new()
	jack.name = name
	jack.position = Vector3(0.0, built_y, 0.0)
	jack.set_meta(&"deployed", Transform3D(Basis(), Vector3(0.0, deployed_y, 0.0)))
	root.add_child(jack)
	var foot := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 0.1)
	foot.mesh = box
	foot.position = Vector3(0.0, 0.05, 0.0)  # box bottom on the pivot's y
	jack.add_child(foot)
	return jack


func test_stabiliser_interpolates_between_built_and_deployed() -> void:
	var model := Node3D.new()
	var jack := _jack(model, "Stabiliser0", 0.05, 0.0)
	var built := jack.transform
	UnitModels.pose_deployables(model, 0.0)
	assert_true(jack.transform.is_equal_approx(built))
	UnitModels.pose_deployables(model, 1.0)
	assert_true(jack.transform.is_equal_approx(jack.get_meta(&"deployed")))
	UnitModels.pose_deployables(model, 0.5)
	assert_true(absf(jack.position.y - 0.025) < TOL, str(jack.position))
	UnitModels.pose_deployables(model, 0.0)
	assert_true(jack.transform.is_equal_approx(built), "stowed pose is the built pose again")
	model.free()


func test_model_without_deployables_is_a_no_op() -> void:
	var model := Node3D.new()
	assert_false(UnitModels.has_deployables(model))
	UnitModels.pose_deployables(model, 1.0)
	model.free()


func test_two_models_are_posed_independently() -> void:
	var a := Node3D.new()
	var b := Node3D.new()
	var jack_a := _jack(a, "Stabiliser0", 0.05, 0.0)
	var jack_b := _jack(b, "Stabiliser0", 0.05, 0.0)
	UnitModels.pose_deployables(a, 1.0)
	UnitModels.pose_deployables(b, 0.0)
	assert_true(absf(jack_a.position.y) < TOL and absf(jack_b.position.y - 0.05) < TOL)
	a.free()
	b.free()


func test_blast_shield_rotates_closed() -> void:
	var model := Node3D.new()
	var shield := Node3D.new()
	shield.name = "BlastShield0"
	shield.set_meta(&"deployed", Transform3D(Basis(Vector3.BACK, deg_to_rad(-80.0)), Vector3.ZERO))
	model.add_child(shield)
	assert_true(UnitModels.has_deployables(model))
	UnitModels.pose_deployables(model, 1.0)
	assert_true(shield.transform.is_equal_approx(shield.get_meta(&"deployed")))
	UnitModels.pose_deployables(model, 0.0)
	assert_true(shield.transform.is_equal_approx(Transform3D.IDENTITY))
	model.free()


func test_deploy_adds_two_steps_to_the_volley_event() -> void:
	var launch := 2.0 * 1.8 + SalvoTiming.salvo_duration(12, 0.40, 1.9)
	var deployed := Battle._volley_event_duration(true, false, true, 12, 0.40, 1.9)
	assert_true(absf(deployed - (1.2 + launch)) < TOL)
	var limited := Battle._volley_event_duration(true, true, true, 12, 0.40, 1.9)
	assert_true(absf(limited - (1.2 + 0.5 + launch)) < TOL)
	var plain := Battle._volley_event_duration(true, false, false, 12, 0.40, 1.9)
	assert_true(absf(plain - launch) < TOL)


func test_stabiliser_contract_catches_floating_feet() -> void:
	var model := Node3D.new()
	_jack(model, "Stabiliser0", 0.05, 0.0)
	assert_eq(Contract.stabiliser_violations(model).size(), 0)
	model.free()
	var floating := Node3D.new()
	_jack(floating, "Stabiliser0", 0.05, 0.02)
	var violations := Contract.stabiliser_violations(floating)
	assert_eq(violations.size(), 1, str(violations))
	if violations.size() == 1:
		assert_true("Stabiliser0" in violations[0], violations[0])
	floating.free()
	var grounded := Node3D.new()
	_jack(grounded, "Stabiliser0", 0.0, 0.0)  # stowed on the ground
	assert_eq(Contract.stabiliser_violations(grounded).size(), 1)
	grounded.free()


func test_missing_deployed_meta_and_undeclared_pivots_are_violations() -> void:
	var registry := Contract.load_registry()
	var model := Node3D.new()
	var jack := Node3D.new()
	jack.name = "Stabiliser0"
	model.add_child(jack)
	var violations := Contract.pivot_violations(model, registry["stabilisers"])
	assert_true(violations.any(func(v: String) -> bool: return "deployed" in v), str(violations))
	var shield := Node3D.new()
	shield.name = "BlastShield0"
	model.add_child(shield)
	var owned := Contract.owned_pivots(model, registry, {"stabilisers": {}})
	assert_eq(owned, ["BlastShield0"])
	model.free()
