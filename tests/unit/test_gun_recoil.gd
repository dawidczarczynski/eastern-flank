extends TestCase
## Gun recoil and muzzle flash (TASK-048): the barrel pose, the recoil profile, MuzzleFlash and the
## shot step of VolleyPlayback.

const Contract := preload("res://tests/mechanism_contract.gd")
const TOL := 0.000001

var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


## Synthetic tank: Model / Turret / Gun / (Barrel at (0.02, 0, 0), Muzzle).
func _tank(declare: bool = true, with_barrel: bool = true) -> Node3D:
	var root := Node3D.new()
	_nodes.append(root)
	var model := Node3D.new()
	model.name = "Model"
	root.add_child(model)
	var mechanisms := {"turret_traverse": {}}
	if declare:
		mechanisms["gun_recoil"] = {"recoil_m": 0.5}
	model.set_meta(&"mechanisms", mechanisms)
	var turret := Node3D.new()
	turret.name = "Turret"
	model.add_child(turret)
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0.05, 0.1, 0.0)
	turret.add_child(gun)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.5, 0.0, 0.0)
	gun.add_child(muzzle)
	if with_barrel:
		var barrel := Node3D.new()
		barrel.name = "Barrel"
		barrel.position = Vector3(0.02, 0.0, 0.0)
		gun.add_child(barrel)
	return root


func _barrel(root: Node3D) -> Node3D:
	return root.get_node("Model/Turret/Gun/Barrel")


func test_pose_recoil_slides_the_barrel_back_and_clamps() -> void:
	var tank := _tank()
	var barrel := _barrel(tank)
	var built := barrel.transform
	UnitModels.pose_recoil(tank, 1.0)
	assert_true(absf(barrel.position.x - (0.02 - 0.05)) < TOL, str(barrel.position))
	UnitModels.pose_recoil(tank, 0.5)
	assert_true(absf(barrel.position.x + 0.005) < TOL, str(barrel.position))
	UnitModels.pose_recoil(tank, 1.7)
	assert_true(absf(barrel.position.x + 0.03) < TOL, "clamped high")
	UnitModels.pose_recoil(tank, -1.0)
	assert_true(barrel.transform.is_equal_approx(built), "clamped low = built")
	UnitModels.pose_recoil(tank, 0.0)
	assert_eq(barrel.transform, built)


## Position of the barrel origin in model space (the headless runner has no scene tree for
## global transforms).
func _barrel_in_model(tank: Node3D) -> Vector3:
	var turret := tank.get_node("Model/Turret") as Node3D
	var gun := turret.get_node("Gun") as Node3D
	return turret.transform * gun.transform * _barrel(tank).position


func test_recoil_follows_the_elevated_gun_and_the_muzzle_stays() -> void:
	var tank := _tank()
	var muzzle := tank.get_node("Model/Turret/Gun/Muzzle") as Node3D
	var gun := tank.get_node("Model/Turret/Gun") as Node3D
	UnitModels.pose_turret(tank, 0.0, deg_to_rad(10.0))
	var before := _barrel_in_model(tank)
	var gun_before := gun.transform
	var muzzle_before := muzzle.transform
	UnitModels.pose_recoil(tank, 1.0)
	var moved := _barrel_in_model(tank) - before
	var expected := Vector3(-cos(deg_to_rad(10.0)), -sin(deg_to_rad(10.0)), 0.0) * 0.05
	assert_true(moved.distance_to(expected) < 0.0001, "%s vs %s" % [moved, expected])
	assert_eq(gun.transform, gun_before, "gun stays")
	assert_eq(muzzle.transform, muzzle_before, "muzzle stays")


func test_pose_recoil_is_a_no_op_without_the_pivot_or_the_declaration() -> void:
	var no_barrel := _tank(true, false)
	var undeclared := _tank(false, true)
	assert_false(UnitModels.has_gun_recoil(no_barrel))
	assert_false(UnitModels.has_gun_recoil(undeclared))
	var gun := undeclared.get_node("Model/Turret/Gun") as Node3D
	var before := _barrel(undeclared).transform
	UnitModels.pose_recoil(no_barrel, 1.0)
	UnitModels.pose_recoil(undeclared, 1.0)
	assert_eq(_barrel(undeclared).transform, before)
	assert_eq(gun.transform.origin, Vector3(0.05, 0.1, 0.0))
	assert_true(UnitModels.has_gun_recoil(_tank()))


func test_recoil_params_default_and_registry() -> void:
	var tank := _tank()
	tank.get_node("Model").set_meta(&"mechanisms", {"gun_recoil": {}})
	assert_eq(UnitModels.recoil_params(tank), {"recoil_m": 0.5})
	var registry: Dictionary = Contract.load_registry()["gun_recoil"]
	var defaults := {}
	for key: String in registry["params"]:
		defaults[key] = registry["params"][key]["default"]
	assert_eq(
		Contract.normalise(UnitModels.RECOIL_DEFAULTS), Contract.normalise(defaults), "defaults"
	)
	assert_eq(registry["status"], "implemented")


func test_owned_barrel_pivot_needs_the_declaration() -> void:
	var tank := _tank(false, true)
	var registry := Contract.load_registry()
	assert_true("Turret/Gun/Barrel" in Contract.owned_pivots(tank.get_node("Model"), registry, {}))
	var declared := {"turret_traverse": {}, "gun_recoil": {}}
	assert_eq(Contract.owned_pivots(tank.get_node("Model"), registry, declared), [] as Array)


func test_built_units_declare_the_recoil() -> void:
	var expected := {
		&"m1a2_sepv3": 0.5,
		&"t72b3": 0.4,
		&"homar_k": -1.0,
		&"bm27_uragan": -1.0,
		&"pl_mech_infantry": -1.0,
		&"ru_motor_rifle": -1.0,
	}
	for unit_id: StringName in expected:
		var model := UnitModels.build(unit_id, 0, null)
		_nodes.append(model)
		var stroke: float = expected[unit_id]
		assert_eq(UnitModels.has_gun_recoil(model), stroke > 0.0, str(unit_id))
		if stroke > 0.0:
			assert_eq(UnitModels.recoil_params(model)["recoil_m"], stroke, str(unit_id))
		var inner := model.get_node("Model") as Node3D
		var problems := Contract.problems(
			str(unit_id),
			inner,
			Contract.load_catalog_mechanisms(str(unit_id)),
			Contract.load_registry()
		)
		assert_eq(problems, [] as Array, str(unit_id))


func test_recoil_profile() -> void:
	var cases := {-0.1: 0.0, 0.0: 0.0, 0.025: 0.5, 0.05: 1.0, 0.2: 0.25, 0.35: 0.0, 0.4: 0.0}
	for age: float in cases:
		assert_true(absf(VolleyPlayback.recoil_at(age) - float(cases[age])) < TOL, str(age))
	assert_true(
		VolleyPlayback.RECOIL_KICK + VolleyPlayback.RECOIL_RETURN <= EventQueue.ATTACK_DURATION
	)


func test_muzzle_flash_pose_and_light() -> void:
	var flash := MuzzleFlash.new().setup(true)
	_nodes.append(flash)
	var ball := flash.get_child(0) as FlashFx
	assert_false(ball.visible, "hidden before fire")
	for age in [-0.01, 0.12, 0.5]:
		flash.pose(age)
		assert_false(ball.visible, str(age))
	flash.pose(0.0)
	assert_true(ball.visible)
	var light := flash.get_node("Light") as OmniLight3D
	assert_true(absf(light.light_energy - 4.0) < 0.0001)
	flash.pose(0.06)
	assert_true(ball.visible)
	assert_true(absf(light.light_energy - 2.0) < 0.0001)
	flash.pose(0.12)
	assert_eq(light.light_energy, 0.0)
	assert_false(light.shadow_enabled)
	var plain := MuzzleFlash.new().setup(false)
	_nodes.append(plain)
	for child in plain.get_children():
		assert_false(child is OmniLight3D)
	flash.fire(Vector3(1, 0.5, 0), Vector3.RIGHT)
	assert_true(flash.position.is_equal_approx(Vector3(1.0 + flash.flash_size / 2.0, 0.5, 0)))


func _view(unit_id: StringName) -> UnitView:
	var definition: UnitDefinition = load("res://data/units/%s.tres" % unit_id)
	var unit := Unit.new(1, 0, definition, Vector2i.ZERO)
	var hud := Control.new()
	_nodes.append(hud)
	var view := UnitView.new()
	_nodes.append(view)
	view.setup(unit, FactionRegistry.get_faction(&"russia"), Vector3.ZERO, hud, Callable())
	return view


func test_append_shot_lasts_the_duration_and_restores_the_pose() -> void:
	var view := _view(&"t72b3")
	var flash := MuzzleFlash.new().setup(true)
	_nodes.append(flash)
	var barrel := view.model().get_node("Turret/Gun/Barrel") as Node3D
	var built := barrel.transform
	var tween: Tween = (Engine.get_main_loop() as SceneTree).create_tween()
	tween.pause()
	VolleyPlayback.append_shot(tween, view, flash, EventQueue.ATTACK_DURATION)
	assert_true(tween.custom_step(0.06), "still running")
	assert_false(barrel.transform.is_equal_approx(built), "kicked back")
	assert_true((flash.get_child(0) as FlashFx).visible, "flash shown at 0.06 s")
	assert_true(tween.custom_step(0.339), "still running at 0.399 s")
	assert_false((flash.get_child(0) as FlashFx).visible, "flash over")
	# custom_step reports the end one step late: 0.401 s has passed, the next step sees it finished.
	tween.custom_step(0.002)
	assert_false(tween.custom_step(0.1), "done after the duration")
	assert_true(barrel.transform.is_equal_approx(built))
	assert_false((flash.get_child(0) as FlashFx).visible)
	tween.kill()


func test_append_shot_without_recoil_only_waits() -> void:
	var view := _view(&"homar_k")
	var flash := MuzzleFlash.new().setup(false)
	_nodes.append(flash)
	var tween: Tween = (Engine.get_main_loop() as SceneTree).create_tween()
	tween.pause()
	VolleyPlayback.append_shot(tween, view, flash, EventQueue.ATTACK_DURATION)
	assert_true(tween.custom_step(0.39))
	assert_false((flash.get_child(0) as FlashFx).visible)
	tween.custom_step(0.02)
	assert_false(tween.custom_step(0.1))
	tween.kill()


func test_append_shot_without_a_flash_still_recoils() -> void:
	var view := _view(&"t72b3")
	var barrel := view.model().get_node("Turret/Gun/Barrel") as Node3D
	var built := barrel.transform
	var tween: Tween = (Engine.get_main_loop() as SceneTree).create_tween()
	tween.pause()
	VolleyPlayback.append_shot(tween, view, null, EventQueue.ATTACK_DURATION)
	assert_true(tween.custom_step(0.05))
	assert_false(barrel.transform.is_equal_approx(built), "kicked back without a flash")
	tween.custom_step(0.36)
	tween.custom_step(0.1)
	assert_true(barrel.transform.is_equal_approx(built))
	tween.kill()
