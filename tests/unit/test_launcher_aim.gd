extends TestCase
## Launcher mechanism parameters (TASK-044): traverse range, stowed direction and elevation per
## unit (UnitModels.traverse_aim / launcher_aim / launcher_params) and the volley event duration.

const Contract := preload("res://tests/mechanism_contract.gd")
const Battle := preload("res://src/presentation/battle_controller.gd")
const TOL := 0.0001
const LIMITS := [-30, 30]


func _assert_aim(actual: Vector2, body_deg: float, turntable_deg: float, label: String) -> void:
	var expected := Vector2(deg_to_rad(body_deg), deg_to_rad(turntable_deg))
	assert_true(
		absf(actual.x - expected.x) < TOL and absf(actual.y - expected.y) < TOL,
		(
			"%s: (%.2f°, %.2f°), expected (%s°, %s°)"
			% [label, rad_to_deg(actual.x), rad_to_deg(actual.y), body_deg, turntable_deg]
		)
	)


func _aim(traverse: Variant, offset: float, facing_deg: float, target_deg: float) -> Vector2:
	return UnitModels.traverse_aim(traverse, offset, deg_to_rad(facing_deg), deg_to_rad(target_deg))


func _homar() -> Node3D:
	return UnitModels.build(&"homar_k", 0, FactionRegistry.get_faction(&"poland"))


func _uragan() -> Node3D:
	return UnitModels.build(&"bm27_uragan", 0, FactionRegistry.get_faction(&"russia"))


func test_front_stowed_limited_traverse_inside_and_outside_the_range() -> void:
	_assert_aim(_aim(LIMITS, 0.0, 0.0, 20.0), 0.0, 20.0, "inside")
	_assert_aim(_aim(LIMITS, 0.0, 0.0, 90.0), 60.0, 30.0, "beyond the upper limit")
	_assert_aim(_aim(LIMITS, 0.0, 0.0, -45.0), -15.0, -30.0, "beyond the lower limit")
	_assert_aim(_aim(LIMITS, 0.0, 0.0, 180.0), -150.0, -30.0, "tie -> lower limit")
	_assert_aim(_aim(LIMITS, 0.0, 90.0, 100.0), 0.0, 10.0, "turned body")


func test_full_traverse_never_turns_the_body() -> void:
	_assert_aim(_aim("full", 0.0, 0.0, 90.0), 0.0, 90.0, "front-stowed full")
	_assert_aim(_aim("full", PI, 0.0, 90.0), 0.0, -90.0, "rear-stowed full")


func test_rear_stowed_limited_traverse() -> void:
	_assert_aim(_aim(LIMITS, PI, 0.0, 170.0), 0.0, -10.0, "rear-stowed")


func test_launcher_defaults_match_the_registry() -> void:
	var params: Dictionary = Contract.load_registry()["launcher"]["params"]
	var defaults := {}
	for key: String in params:
		defaults[key] = params[key]["default"]
	assert_eq(
		Contract.normalise(UnitModels.LAUNCHER_DEFAULTS), Contract.normalise(defaults), "defaults"
	)


func test_launcher_without_metadata_gets_the_defaults() -> void:
	var root := Node3D.new()
	var launcher := Node3D.new()
	launcher.name = "Launcher"
	root.add_child(launcher)
	assert_eq(UnitModels.launcher_params(root), UnitModels.LAUNCHER_DEFAULTS)
	assert_false(UnitModels.launcher_limited(root))
	assert_true(absf(UnitModels.launcher_elevation(root) - deg_to_rad(40.0)) < TOL)
	root.free()


func test_partial_metadata_falls_back_to_the_defaults() -> void:
	var root := Node3D.new()
	root.set_meta(&"mechanisms", {"launcher": {"max_elevation_deg": 55}})
	var params := UnitModels.launcher_params(root)
	assert_eq(params["max_elevation_deg"], 55)
	assert_eq(params["traverse_deg"], "full")
	assert_eq(params["stowed"], "rear")
	root.free()


func test_homar_behaves_as_before() -> void:
	var homar := _homar()
	var aim := UnitModels.launcher_aim(homar, 0.0, PI / 2.0)
	assert_true(aim.distance_to(Vector2(0.0, -PI / 2.0)) < TOL, "aim %s" % aim)
	assert_true(absf(UnitModels.launcher_elevation(homar) - 0.7) < 0.01)
	assert_false(UnitModels.launcher_limited(homar))
	homar.free()


func test_uragan_is_front_stowed_with_a_limited_traverse() -> void:
	var uragan := _uragan()
	assert_eq(UnitModels.launcher_params(uragan)["stowed"], "front")
	assert_true(UnitModels.launcher_limited(uragan))
	assert_true(absf(UnitModels.launcher_elevation(uragan) - deg_to_rad(55.0)) < TOL)
	# Over the cab: no turn at all; behind it: the truck turns, the launcher takes a limit.
	_assert_aim(UnitModels.launcher_aim(uragan, 0.0, 0.0), 0.0, 0.0, "ahead")
	_assert_aim(UnitModels.launcher_aim(uragan, 0.0, PI), -150.0, -30.0, "behind")
	uragan.free()


func test_volley_event_duration() -> void:
	# Homar-K at 6 hexes (world distance 6 * sqrt(3) with hex size 1).
	var flight := SalvoTiming.flight_time(6.0 * sqrt(3.0))
	var salvo := SalvoTiming.salvo_duration(12, 0.40, flight)
	var turntable := Battle._volley_event_duration(true, false, false, 12, 0.40, flight)
	assert_true(absf(turntable - (2.0 * 1.8 + salvo)) < TOL)
	var limited := Battle._volley_event_duration(true, true, false, 12, 0.40, flight)
	assert_true(absf(limited - (0.5 + 3.6 + salvo)) < TOL)
	var fixed := Battle._volley_event_duration(false, false, false, 12, 0.40, flight)
	assert_true(absf(fixed - (0.5 + salvo)) < TOL, "no launcher: AIM_DURATION + salvo")
