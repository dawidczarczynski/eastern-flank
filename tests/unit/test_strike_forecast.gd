extends TestCase
## The exact strike forecast (TASK-101): StrikeRules.forecast and the shared helpers.

const Strikes := preload("res://tests/unit/test_strikes.gd")
const SHORT_AT := Vector2i(7, 0)  # within 4 of the airfield `a1`


func _near(actual: float, expected: float, tolerance: float, message := "") -> void:
	assert_true(absf(actual - expected) <= tolerance, "%s: %f vs %f" % [message, actual, expected])


## A state at level 2 (strikes allowed) with a weapon `w` of accuracy / interceptability / damage.
func _state(
	accuracy := 50, interceptability := 100, damage := 40, op: OperationDefinition = null
) -> OperationalState:
	var state := Strikes._state(op)
	state.escalation_level = 2
	var means := Strikes._means(&"w", accuracy, interceptability, damage)
	means.formation_damage = 3
	state.strike_means[&"w"] = means
	state.strike_stock[0][&"w"] = 10
	state.strike_stock[1][&"w"] = 10
	return state


func _with_site() -> OperationalState:
	var op := Strikes._definition()
	op.installations.append(Strikes._placement(&"ad", &"air_defence", 1, SHORT_AT, &"short"))
	return _state(50, 100, 40, op)


func test_unusable_requests_give_empty() -> void:
	var state := _state()
	assert_true(StrikeRules.forecast(state, 0, &"nope", 1, &"a1").is_empty(), "unknown weapon")
	assert_true(StrikeRules.forecast(state, 0, &"w", 1, &"nope").is_empty(), "unknown target")
	assert_true(StrikeRules.forecast(state, 0, &"w", 1, &"pl_air").is_empty(), "own target")
	assert_true(StrikeRules.forecast(state, 0, &"kalibr", 1, &"a1").is_empty(), "other side")
	state.strike_stock[0][&"w"] = 0
	assert_true(StrikeRules.forecast(state, 0, &"w", 1, &"a1").is_empty(), "no stock")
	state.strike_stock[0][&"w"] = 5
	state.escalation_level = 1
	assert_true(StrikeRules.forecast(state, 0, &"w", 1, &"a1").is_empty(), "closed country")
	state.escalation_level = 2
	state.strike_means[&"w"].range_hexes = 1
	assert_true(StrikeRules.forecast(state, 0, &"w", 1, &"a1").is_empty(), "out of range")
	state.strike_means[&"w"].range_hexes = 50
	state.get_installation(&"a1").integrity = 0
	assert_true(StrikeRules.forecast(state, 0, &"w", 1, &"a1").is_empty(), "destroyed")


func test_effective_salvo_is_capped() -> void:
	var state := _state()
	state.strike_stock[0][&"w"] = 2
	assert_eq(StrikeRules.forecast(state, 0, &"w", 4, &"a1")["count"], 2)
	state.strike_stock[0][&"w"] = 10
	assert_eq(StrikeRules.forecast(state, 0, &"w", 9, &"a1")["count"], 4, "max salvo")
	assert_eq(StrikeRules.forecast(state, 0, &"w", 0, &"a1")["count"], 1)


func test_hit_numbers() -> void:
	var state := _state(90, 70)
	var open := StrikeRules.forecast(state, 0, &"w", 4, &"a1")
	assert_eq(open["p_intercept"], 0)
	_near(open["p_hit_missile"], 0.9, 1e-6)
	_near(open["expected_hits"], 3.6, 1e-6)
	_near(open["p_at_least_one"], 0.9999, 1e-6)
	var covered := _with_site()
	covered.strike_means[&"w"] = Strikes._means(&"w", 90, 70, 40)
	# The short site: cruise chance 50 x integrity 100 -> 50, x interceptability 70 -> 35.
	var cover := StrikeRules.forecast(covered, 0, &"w", 4, &"a1")
	var expected := StrikeRules.interception_chance(covered, 0, &"w", Vector2i(6, 0))
	assert_eq(cover["p_intercept"], expected)
	_near(cover["p_hit_missile"], (1.0 - expected / 100.0) * 0.9, 1e-6)
	_near(cover["expected_hits"], 4 * cover["p_hit_missile"], 1e-6)


func test_matches_resolution_for_every_shipped_weapon() -> void:
	for player in 2:
		for means: StrikeMeansDefinition in StrikeMeansDefinition.shipped().values():
			if not means.usable_by(player):
				continue
			for covered in [false, true]:
				var state := _with_site() if covered else _state()
				var copy := means.duplicate() as StrikeMeansDefinition
				copy.range_hexes = 500
				state.strike_means[means.id] = copy
				state.strike_stock[player][means.id] = 10
				var target_id := &"a1" if player == 0 else &"pl_air"
				var forecast := StrikeRules.forecast(state, player, means.id, 1, target_id)
				assert_false(forecast.is_empty(), String(means.id))
				var target := StrikeRules.find_target(state, player, target_id)
				var event := StrikeRules.resolve(state, player, means.id, target, 1)[0]
				assert_eq(forecast["p_intercept"], event["p_intercept"], String(means.id))
				assert_eq(forecast["p_hit"], event["p_hit"], String(means.id))
				var p_intercept := mini(int(event["p_intercept"]), 100)
				_near(
					forecast["p_hit_missile"],
					(1.0 - p_intercept / 100.0) * int(event["p_hit"]) / 100.0,
					1e-9
				)


func test_installation_target() -> void:
	var state := _state(50, 100, 40)
	var forecast := StrikeRules.forecast(state, 0, &"w", 4, &"a1")
	assert_eq(forecast["integrity_before"], 100)
	_near(forecast["p_destroyed"], 0.3125, 1e-9)
	_near(forecast["expected_integrity_after"], 28.75, 1e-9)
	state.get_installation(&"a1").integrity = 30
	var floor_case := StrikeRules.forecast(state, 0, &"w", 1, &"a1")
	_near(floor_case["p_destroyed"], 0.5, 1e-9)
	_near(floor_case["expected_integrity_after"], 15.0, 1e-9)


func test_strengths_after_hits() -> void:
	var lost := StrikeRules.strengths_after_hits([4, 4, 4] as Array[int], 2, 3)
	assert_eq(lost, [1, 1, 4] as Array[int])
	assert_eq(StrikeRules.strengths_after_hits([2] as Array[int], 1, 3), [0] as Array[int])
	assert_eq(StrikeRules.strengths_after_hits([5, 5] as Array[int], 0, 3), [5, 5] as Array[int])


func test_formation_target_matches_resolution() -> void:
	var state := _state(50)
	var forecast := StrikeRules.forecast(state, 0, &"w", 3, &"r")
	var before := state.get_formation(&"r").strength()
	assert_eq(forecast["strength_before"], before)
	var expected := 0.0
	var destroyed := 0.0
	var means: StrikeMeansDefinition = state.strike_means[&"w"]
	for k in 4:
		var copy := _state(50)
		var formation := copy.get_formation(&"r")
		var result := StrikeRules._damage_formation(copy, formation, k, means)
		var weight := [0.125, 0.375, 0.375, 0.125][k] as float
		expected += weight * result["dealt"]
		if result["destroyed"]:
			destroyed += weight
	_near(forecast["expected_strength_lost"], expected, 1e-9)
	_near(forecast["p_destroyed"], destroyed, 1e-9)


func test_suppressed_and_destroyed_sites_do_not_count() -> void:
	var state := _with_site()
	assert_true(StrikeRules.forecast(state, 0, &"w", 1, &"a1")["p_intercept"] > 0)
	state.get_installation(&"ad").suppressed_rounds = 2
	assert_eq(StrikeRules.forecast(state, 0, &"w", 1, &"a1")["p_intercept"], 0)
	state.get_installation(&"ad").suppressed_rounds = 0
	state.get_installation(&"ad").integrity = 0
	assert_eq(StrikeRules.forecast(state, 0, &"w", 1, &"a1")["p_intercept"], 0)


func test_deterministic_and_pure() -> void:
	var state := _with_site()
	var snapshot := state.snapshot()
	var rng_state := state.rng.state
	var first := StrikeRules.forecast(state, 0, &"w", 3, &"a1")
	var second := StrikeRules.forecast(state, 0, &"w", 3, &"a1")
	assert_eq(first, second)
	assert_eq(state.rng.state, rng_state)
	assert_eq(state.snapshot(), snapshot)
