extends TestCase
## DevTunables (TASK-186a): defaults equal the old constants, overrides only while active, clamping,
## and the effect code reading the store at use.


func after_each() -> void:
	DevTunables.reset_all()
	DevTunables.set_slow_motion(1.0)
	DevTunables.deactivate()


func test_barrage_defaults_equal_the_old_constants() -> void:
	assert_eq(
		DevTunables.default_of(DevTunables.BARRAGE_ELEV_MIN),
		VolleyPlayback.BARREL_MIN_ELEVATION_DEG
	)
	assert_eq(
		DevTunables.default_of(DevTunables.BARRAGE_ELEV_MAX),
		VolleyPlayback.BARREL_MAX_ELEVATION_DEG
	)
	assert_eq(
		DevTunables.default_of(DevTunables.BARRAGE_FULL_DISTANCE),
		VolleyPlayback.BARREL_FULL_DISTANCE_HEXES
	)
	assert_eq(int(DevTunables.default_of(DevTunables.BARRAGE_COUNT)), SalvoTiming.BARRAGE_COUNT)
	assert_eq(DevTunables.default_of(DevTunables.BARRAGE_INTERVAL), SalvoTiming.BARRAGE_INTERVAL)
	assert_eq(
		DevTunables.default_of(DevTunables.BARRAGE_FLIGHT_BASE), SalvoTiming.BARRAGE_FLIGHT_BASE
	)
	assert_eq(
		DevTunables.default_of(DevTunables.BARRAGE_FLIGHT_PER_UNIT),
		SalvoTiming.BARRAGE_FLIGHT_PER_UNIT
	)
	assert_eq(DevTunables.default_of(DevTunables.TRACER_SIZE), RocketVolley.SHELL_GLOW_SIZE)


func test_salvo_defaults_equal_the_old_constants() -> void:
	assert_eq(DevTunables.default_of(DevTunables.LANDING_RADIUS), SalvoTiming.LANDING_RADIUS)
	assert_eq(
		int(DevTunables.default_of(DevTunables.SALVO_COUNT)), SalvoTiming.DEFAULT_PROFILE["count"]
	)
	assert_eq(
		DevTunables.default_of(DevTunables.SALVO_INTERVAL), SalvoTiming.DEFAULT_PROFILE["interval"]
	)
	assert_eq(DevTunables.default_of(DevTunables.SALVO_FLIGHT_BASE), SalvoTiming.FLIGHT_BASE)
	assert_eq(DevTunables.default_of(DevTunables.SALVO_APEX_BASE), RocketVolley.APEX_BASE)
	assert_eq(DevTunables.default_of(DevTunables.MUZZLE_FLASH_SIZE), RocketVolley.LAUNCH_FLASH_SIZE)


func test_impact_and_shake_defaults_equal_the_old_constants() -> void:
	assert_eq(int(DevTunables.default_of(DevTunables.FIREBALL)), SalvoFxPool.FIREBALL)
	assert_eq(int(DevTunables.default_of(DevTunables.SMOKE)), SalvoFxPool.IMPACT_SMOKE)
	assert_eq(int(DevTunables.default_of(DevTunables.DEBRIS)), SalvoFxPool.DEBRIS)
	assert_eq(int(DevTunables.default_of(DevTunables.DUST_RING)), SalvoFxPool.DUST_RING)
	assert_eq(DevTunables.default_of(DevTunables.CAMERA_SHAKE), CameraRig.SHAKE_MAX)


func test_overrides_are_ignored_while_inactive() -> void:
	DevTunables.set_value(DevTunables.BARRAGE_COUNT, 5.0)
	assert_false(DevTunables.active)
	assert_eq(DevTunables.get_int(DevTunables.BARRAGE_COUNT), 3)
	assert_eq(VolleyPlayback.barrage_plan(5.0)["count"], 3)
	DevTunables.activate()
	assert_eq(DevTunables.get_int(DevTunables.BARRAGE_COUNT), 5)
	DevTunables.deactivate()
	assert_eq(VolleyPlayback.barrage_plan(5.0)["count"], 3)


func test_set_value_clamps_and_reset_restores_the_default() -> void:
	DevTunables.activate()
	assert_eq(DevTunables.set_value(DevTunables.BARRAGE_COUNT, 99.0), 12.0)
	assert_eq(DevTunables.set_value(DevTunables.BARRAGE_INTERVAL, 0.0), 0.05)
	assert_eq(DevTunables.set_value(DevTunables.SALVO_FLIGHT_BASE, 50.0), 4.0)
	assert_eq(DevTunables.set_value(DevTunables.BARRAGE_ELEV_MIN, -5.0), 0.0)
	assert_eq(DevTunables.set_value(DevTunables.BARRAGE_ELEV_MAX, 120.0), 85.0)
	assert_eq(DevTunables.set_value(DevTunables.TRACER_SIZE, 0.0), 0.01)
	assert_eq(DevTunables.set_value(DevTunables.LANDING_RADIUS, 9.0), 2.0)
	assert_eq(DevTunables.set_value(DevTunables.FIREBALL, 100.0), 30.0)
	DevTunables.reset(DevTunables.BARRAGE_COUNT)
	assert_eq(DevTunables.get_int(DevTunables.BARRAGE_COUNT), 3)
	assert_eq(DevTunables.get_value(DevTunables.FIREBALL), 30.0)
	DevTunables.reset_all()
	assert_eq(DevTunables.get_int(DevTunables.FIREBALL), SalvoFxPool.FIREBALL)


func test_shell_count_5_gives_5_shells() -> void:
	DevTunables.activate()
	DevTunables.set_value(DevTunables.BARRAGE_COUNT, 5.0)
	var plan := VolleyPlayback.barrage_plan(4.0)
	assert_eq(plan["count"], 5)
	var rng := RandomNumberGenerator.new()
	var landings := VolleyPlayback.landing_points(rng, Vector3.ZERO, plan["count"], 0.5)
	assert_eq(landings.size(), 5)


func test_elevation_min_30_gives_30_degrees_at_distance_0() -> void:
	assert_true(absf((rad_to_deg(VolleyPlayback.barrage_elevation(0.0))) - (15.0)) < 0.001)
	DevTunables.activate()
	DevTunables.set_value(DevTunables.BARRAGE_ELEV_MIN, 30.0)
	assert_true(absf((rad_to_deg(VolleyPlayback.barrage_elevation(0.0))) - (30.0)) < 0.001)


func test_timing_tunables_reach_the_plans() -> void:
	DevTunables.activate()
	DevTunables.set_value(DevTunables.BARRAGE_INTERVAL, 0.3)
	DevTunables.set_value(DevTunables.SALVO_COUNT, 9.0)
	DevTunables.set_value(DevTunables.SALVO_INTERVAL, 0.2)
	DevTunables.set_value(DevTunables.SALVO_FLIGHT_BASE, 3.0)
	assert_eq(VolleyPlayback.barrage_plan(5.0)["interval"], 0.3)
	var plan := VolleyPlayback.salvo_plan(&"homar_k", 12, 2.0)
	assert_eq(plan["count"], 9)
	assert_eq(plan["interval"], 0.2)
	assert_true(plan["flight"] > SalvoTiming.FLIGHT_MAX)


func test_apex_follows_the_tunable() -> void:
	var normal := RocketVolley.apex_height(2.0)
	DevTunables.activate()
	DevTunables.set_value(DevTunables.SALVO_APEX_BASE, 1.5)
	assert_true(absf((RocketVolley.apex_height(2.0)) - (normal + 0.8)) < 0.0001)


func test_slow_motion_applies_while_active_and_is_restored_on_leaving() -> void:
	DevTunables.set_slow_motion(0.2)
	assert_eq(Engine.time_scale, 1.0)
	DevTunables.activate()
	assert_true(absf((Engine.time_scale) - (0.2)) < 0.0001)
	DevTunables.set_slow_motion(5.0)
	assert_eq(Engine.time_scale, 1.0)
	DevTunables.set_slow_motion(0.0)
	assert_true(absf((Engine.time_scale) - (0.1)) < 0.0001)
	var arena := ArenaController.new()
	arena._exit_tree()
	arena.free()
	assert_eq(Engine.time_scale, 1.0)
	assert_false(DevTunables.active)


func test_fire_again_is_disabled_without_a_previous_attack() -> void:
	var arena := ArenaController.new()
	assert_false(arena.can_fire_again())
	arena.fire_again()  # no crash
	arena.free()
