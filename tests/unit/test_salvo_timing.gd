extends TestCase
## SalvoTiming (TASK-074): salvo size, ripple interval, flight time, launch / impact crossings,
## flight progress, per-rocket HP steps and landing points of a rocket salvo.

const TOL := 0.001


func _near(actual: float, expected: float, label: String) -> void:
	assert_true(absf(actual - expected) < TOL, "%s: %f, expected %f" % [label, actual, expected])


func test_rocket_count_prefers_the_mouth_count() -> void:
	assert_eq(SalvoTiming.rocket_count(&"homar_k", 12), 12)
	assert_eq(SalvoTiming.rocket_count(&"bm27_uragan", 16), 16)
	assert_eq(SalvoTiming.rocket_count(&"bm27_uragan", 0), 16)
	assert_eq(SalvoTiming.rocket_count(&"unknown", 0), 6)
	assert_eq(SalvoTiming.rocket_count(&"unknown", 4), 4)


func test_interval_per_unit() -> void:
	_near(SalvoTiming.interval(&"homar_k"), 0.50, "homar_k")
	_near(SalvoTiming.interval(&"bm27_uragan"), 0.38, "bm27_uragan")
	_near(SalvoTiming.interval(&"unknown"), 0.35, "unknown")


func test_launcher_models_have_one_mouth_per_profile_rocket() -> void:
	for unit_id: StringName in SalvoTiming.PROFILES:
		var expected: int = SalvoTiming.PROFILES[unit_id]["count"]
		for faction in FactionRegistry.all():
			var model := UnitModels.build(unit_id, 0, faction)
			var pod := UnitModels.launcher_pod(model.get_node("Model"))
			var mouths := 0
			if pod != null:
				for child in pod.get_children():
					if child.name.begins_with("Mouth"):
						mouths += 1
			assert_eq(mouths, expected, "%s / %s" % [unit_id, faction.id])
			model.free()


func test_flight_time_is_clamped() -> void:
	_near(SalvoTiming.flight_time(0.0), 1.1, "0")
	_near(SalvoTiming.flight_time(10.0), 1.9, "10")
	_near(SalvoTiming.flight_time(100.0), 2.2, "100")


func test_salvo_duration() -> void:
	_near(SalvoTiming.salvo_duration(12, 0.40, 1.9), 6.8, "homar")
	_near(SalvoTiming.salvo_duration(16, 0.30, 1.9), 6.9, "uragan")
	_near(SalvoTiming.salvo_duration(1, 0.4, 1.1), 1.6, "single")


func test_launch_and_impact_times() -> void:
	_near(SalvoTiming.launch_time(3, 0.4), 1.2, "launch")
	_near(SalvoTiming.impact_time(3, 0.4, 1.9), 3.1, "impact")


## Steps t from -0.01 to the salvo's end in `step` increments (<= 0 = one single step) and checks
## that every launch and impact index is reported exactly once, in ascending order.
func _assert_crossings_complete(count: int, interval: float, flight: float, step: float) -> void:
	var end := SalvoTiming.salvo_duration(count, interval, flight)
	var launches: Array[int] = []
	var impacts: Array[int] = []
	var t0 := -0.01
	while t0 < end:
		var t1 := end if step <= 0.0 else minf(t0 + step, end)
		var crossed := SalvoTiming.crossings(t0, t1, count, interval, flight)
		launches.append_array(crossed["launches"])
		impacts.append_array(crossed["impacts"])
		t0 = t1
	var expected: Array[int] = []
	for i in count:
		expected.append(i)
	assert_eq(launches, expected, "launches, step %s" % step)
	assert_eq(impacts, expected, "impacts, step %s" % step)


func test_crossings_report_every_rocket_once() -> void:
	for step: float in [0.016, 0.37, 0.0]:
		_assert_crossings_complete(12, 0.40, 1.9, step)
		_assert_crossings_complete(16, 0.30, 1.94, step)


func test_crossings_window() -> void:
	var crossed := SalvoTiming.crossings(0.39, 0.41, 12, 0.40, 1.9)
	assert_eq(crossed["launches"], [1] as Array[int])
	assert_eq(crossed["impacts"], [] as Array[int])
	var none := SalvoTiming.crossings(1.0, 1.0, 12, 0.40, 1.9)
	assert_true(none["launches"].is_empty() and none["impacts"].is_empty())
	var start := SalvoTiming.crossings(-0.5, 0.0, 12, 0.40, 1.9)
	assert_eq(start["launches"], [0] as Array[int], "time 0 is included from a negative t0")


func test_flight_progress() -> void:
	_near(SalvoTiming.flight_progress(0.0), 0.0, "0")
	_near(SalvoTiming.flight_progress(1.0), 1.0, "1")
	_near(SalvoTiming.flight_progress(-1.0), 0.0, "clamp low")
	_near(SalvoTiming.flight_progress(2.0), 1.0, "clamp high")
	assert_true(SalvoTiming.flight_progress(0.1) < 0.1, "accelerating start")
	var previous := -1.0
	for i in 101:
		var u := SalvoTiming.flight_progress(i / 100.0)
		assert_true(u >= previous, "monotonic at %d" % i)
		previous = u


func test_hp_after_impact() -> void:
	var previous := 6
	for k in 12:
		var hp := SalvoTiming.hp_after_impact(6, 1, k, 12)
		assert_true(hp <= previous, "non-increasing at %d" % k)
		previous = hp
	assert_eq(SalvoTiming.hp_after_impact(6, 1, 0, 12), 6)
	assert_eq(SalvoTiming.hp_after_impact(6, 1, 11, 12), 1)
	assert_eq(SalvoTiming.hp_after_impact(6, 0, 15, 16), 0)
	for k in 12:
		assert_eq(SalvoTiming.hp_after_impact(5, 5, k, 12), 5)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_landing_points() -> void:
	var centre := Vector3(3.0, 0.5, -2.0)
	var points := SalvoTiming.landing_points(_rng(7), centre, 12, 0.8)
	assert_eq(points.size(), 12)
	for p in points:
		assert_true(Vector2(p.x - centre.x, p.z - centre.z).length() <= 0.8 + 0.000001)
	assert_eq(SalvoTiming.landing_points(_rng(7), centre, 12, 0.8), points, "same seed")
	assert_true(SalvoTiming.landing_points(_rng(8), centre, 12, 0.8) != points, "other seed")
