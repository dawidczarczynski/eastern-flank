extends TestCase
## StrikeCommand (TASK-097a): rejections, apply order, escalation, determinism, codec, replay.

const Strikes := preload("res://tests/unit/test_strikes.gd")


static func _sim(state: OperationalState) -> OperationalSimulation:
	return OperationalSimulation.new(state)


static func _collect(sim: OperationalSimulation) -> Array[Dictionary]:
	var seen: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: seen.append(e))
	return seen


static func _reasons(sim: OperationalSimulation) -> Array[String]:
	var reasons: Array[String] = []
	sim.command_rejected.connect(func(_c: OperationalCommand, r: String) -> void: reasons.append(r))
	return reasons


static func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> Variant: return e["type"])


func _open_war() -> OperationalState:
	var state := Strikes._state()
	state.escalation_level = 2
	return state


func test_rejection_order() -> void:
	var state := _open_war()
	state.strike_stock[0][&"short"] = 5
	var sim := _sim(state)
	var reasons := _reasons(sim)
	var before := state.snapshot()
	assert_false(sim.execute(StrikeCommand.new(&"nuke", &"a1", 1)))
	assert_false(sim.execute(StrikeCommand.new(&"sure", &"a1", 0)))
	assert_false(sim.execute(StrikeCommand.new(&"sure", &"a1", 5)))
	state.strike_stock[0][&"cruise"] = 0
	assert_false(sim.execute(StrikeCommand.new(&"cruise", &"a1", 1)))
	state.strikes_left = 0
	assert_false(sim.execute(StrikeCommand.new(&"sure", &"a1", 1)))
	state.strikes_left = 2
	assert_false(sim.execute(StrikeCommand.new(&"sure", &"nope", 1)))
	assert_false(sim.execute(StrikeCommand.new(&"sure", &"pl_air", 1)))
	assert_false(sim.execute(StrikeCommand.new(&"short", &"a1", 1)))
	assert_eq(
		reasons,
		[
			"unknown_means",
			"bad_count",
			"bad_count",
			"out_of_stock",
			"no_strikes_left",
			"unknown_target",
			"unknown_target",
			"out_of_range",
		]
	)
	state.strike_stock[0][&"cruise"] = before["strike_stock"][0]["cruise"]
	assert_eq(state.snapshot(), before, "nothing changed, nothing drawn")


func test_battle_pending_comes_first() -> void:
	var state := _open_war()
	state.pending_battles.append(BattleSetup.new())
	var sim := _sim(state)
	var reasons := _reasons(sim)
	assert_false(sim.execute(StrikeCommand.new(&"nuke", &"nope", 9)))
	assert_eq(reasons, ["battle_pending"])


func test_rejected_strike_changes_and_draws_nothing() -> void:
	var state := Strikes._state()
	var sim := _sim(state)
	var before := state.snapshot()
	assert_false(sim.execute(StrikeCommand.new(&"sure", &"a1", 1)))
	assert_eq(state.snapshot(), before, "closed_country at level 1")


func test_spec_example() -> void:
	var state := _open_war()
	state.strike_stock[0][&"sure"] = 6
	var sim := _sim(state)
	var seen := _collect(sim)
	var reasons := _reasons(sim)
	var rng_before := state.rng.state
	assert_true(sim.execute(StrikeCommand.new(&"sure", &"a1", 2)))
	assert_eq(
		_types(seen).slice(0, 6),
		[
			&"strike_stock_changed",
			&"strike_launched",
			&"strike_resolved",
			&"installation_changed",
			&"sanctuary_breached",
			&"escalation_changed",
		]
	)
	assert_eq(seen[0]["count"], -2)
	assert_eq(seen[0]["source"], &"strike")
	assert_eq(seen[1]["target"], &"a1")
	assert_eq(seen[1]["class_id"], &"airfield")
	assert_eq(seen[2]["hits"], 2)
	assert_eq(StrikeRules.stock(state, 0, &"sure"), 4)
	assert_eq(state.get_installation(&"a1").integrity, 30)
	assert_eq(state.strikes_left, 1)
	assert_eq(seen[5]["level"], 3)
	assert_eq(seen[5]["previous"], 2)
	assert_eq(seen[5]["cause"], &"sanctuary_breach")
	assert_eq(state.escalation_caused, [1, 0])
	assert_true(state.rng.state != rng_before)
	seen.clear()
	assert_true(sim.execute(StrikeCommand.new(&"sure", &"a1", 2)))
	assert_eq(state.get_installation(&"a1").integrity, 0)
	assert_true(seen[3]["destroyed"])
	assert_false(_types(seen).has(&"escalation_changed"), "the breach is once")
	assert_false(sim.execute(StrikeCommand.new(&"sure", &"a1", 1)))
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_false(sim.execute(StrikeCommand.new(&"sure", &"a1", 1)))
	assert_eq(reasons, ["no_strikes_left", "target_destroyed"])


func test_rng_advances_two_per_missile() -> void:
	var state := _open_war()
	var reference := RandomNumberGenerator.new()
	reference.seed = 1
	for i in 6:
		reference.randi_range(1, 100)
	assert_true(_sim(state).execute(StrikeCommand.new(&"sure", &"a1", 3)))
	assert_eq(state.rng.state, reference.state)


func test_intercepted_strike_is_still_an_incident() -> void:
	var op := Strikes._definition()
	op.installations.append(Strikes._placement(&"ad", &"air_defence", 1, Vector2i(5, 0)))
	var state := Strikes._state(op)
	var total := AirDefenceDefinition.new()  # a made-up type that intercepts everything
	total.id = &"short"
	total.radius_hexes = 4
	for weapon_class in StrikeMeansDefinition.WEAPON_CLASSES:
		total.intercept_pct[weapon_class] = 100
	state.air_defence_types[&"short"] = total
	state.escalation_level = 2
	state.strike_means[&"sure"].interceptability_pct = 200
	var sim := _sim(state)
	var seen := _collect(sim)
	assert_true(sim.execute(StrikeCommand.new(&"sure", &"a1", 2)))
	assert_eq(seen[2]["intercepted"], 2)
	assert_eq(seen[2]["hits"], 0)
	assert_eq(state.get_installation(&"a1").integrity, 100)
	assert_true(_types(seen).has(&"sanctuary_breached"))
	assert_eq(state.escalation_level, 3)


func test_urban_strike_adds_one_once_per_side() -> void:
	var state := Strikes._state()
	state.escalation_level = 0
	state.escalation_floor = 0
	state.current_player = 1
	state.grid.set_terrain(Vector2i(1, 0), Terrain.Type.URBAN)
	var sim := _sim(state)
	assert_true(sim.execute(StrikeCommand.new(&"sure", &"b", 1)))
	assert_eq(state.escalation_level, 1)
	assert_eq(state.urban_escalated, [false, true] as Array[bool])
	assert_true(sim.execute(StrikeCommand.new(&"sure", &"b", 1)))
	assert_eq(state.escalation_level, 1, "a later urban strike by the same side adds nothing")
	assert_eq(state.escalation_caused, [0, 1])
	assert_eq(state.snapshot()["escalation"]["urban_escalated"], [false, true])


func test_urban_strike_at_the_cap_still_hits() -> void:
	var state := Strikes._state()
	state.escalation_level = 5
	state.current_player = 1
	state.grid.set_terrain(Vector2i(1, 0), Terrain.Type.URBAN)
	var sim := _sim(state)
	var seen := _collect(sim)
	assert_true(sim.execute(StrikeCommand.new(&"sure", &"b", 1)))
	assert_eq(state.escalation_level, 5)
	assert_eq(state.result, {})
	assert_true(_types(seen).has(&"strike_resolved"))
	assert_false(_types(seen).has(&"escalation_changed"))
	assert_true(state.urban_escalated[1])


func test_breach_and_urban_together() -> void:
	var state := _open_war()
	state.grid.set_terrain(Vector2i(6, 0), Terrain.Type.URBAN)
	assert_true(_sim(state).execute(StrikeCommand.new(&"sure", &"a1", 1)))
	assert_eq(state.escalation_caused[0], 2, "breach + urban")
	assert_eq(state.escalation_level, 4)


func test_strike_near_the_cap_never_ends_the_operation() -> void:
	var state := _open_war()
	state.escalation_level = 4
	state.grid.set_terrain(Vector2i(6, 0), Terrain.Type.URBAN)
	assert_eq(EscalationRules.strike_escalation(state, 0, Vector2i(6, 0)), 1, "clipped")
	var sim := _sim(state)
	var seen := _collect(sim)
	assert_true(sim.execute(StrikeCommand.new(&"sure", &"a1", 1)))
	assert_eq(state.escalation_level, 5)
	assert_eq(state.escalation_caused[0], 1, "only the real step")
	assert_eq(state.result, {})
	assert_false(_types(seen).has(&"operation_ended"))
	assert_true(state.get_country(&"russia").breached_by[0])
	assert_true(state.urban_escalated[0])


func test_mirror_gives_mirrored_result() -> void:
	var a := _open_war()
	var b := _open_war()
	b.current_player = 1
	b.first_player = 1
	a.strike_means[&"sure"] = Strikes._means(&"sure")
	assert_true(_sim(a).execute(StrikeCommand.new(&"sure", &"a1", 2)))
	assert_true(_sim(b).execute(StrikeCommand.new(&"sure", &"pl_air", 2)))
	assert_eq(StrikeRules.stock(b, 1, &"sure"), 8)
	assert_eq(b.get_installation(&"pl_air").integrity, 30)
	assert_eq(b.escalation_level, 2, "Poland is no sanctuary")
	assert_eq(b.strikes_left, 1)


func test_granted_stock_equals_starting_stock() -> void:
	var a := _open_war()
	var b := _open_war()
	StrikeRules.add_stock(b, 0, &"sure", 5, &"china_components")
	a.strike_stock[0][&"sure"] = 15
	assert_true(_sim(a).execute(StrikeCommand.new(&"sure", &"a1", 3)))
	assert_true(_sim(b).execute(StrikeCommand.new(&"sure", &"a1", 3)))
	assert_eq(a.snapshot(), b.snapshot())


func test_formation_target_and_removal() -> void:
	var state := _open_war()
	for company in state.get_formation(&"r").companies:
		company.strength = 1
	state.strike_stock[0][&"sure"] = 10
	var sim := _sim(state)
	var seen := _collect(sim)
	assert_true(sim.execute(StrikeCommand.new(&"sure", &"r", 1)))
	assert_true(_types(seen).has(&"formation_damaged"))
	assert_true(sim.execute(StrikeCommand.new(&"sure", &"r", 4)))
	assert_true(_types(seen).has(&"formation_destroyed"))
	assert_true(state.get_formation(&"r") == null)
	assert_eq(StrikeRules.targets(state, 0).size(), 2)


# --- codec ---


func test_codec_round_trip() -> void:
	var command := StrikeCommand.new(&"cruise", &"a1", 2)
	var restored := OperationalCommandCodec.from_dict(
		JSON.parse_string(JSON.stringify(command.to_dict())) as Dictionary
	)
	assert_true(restored is StrikeCommand)
	assert_eq(restored.to_dict(), command.to_dict())


func test_codec_rejects_malformed() -> void:
	var good := {"type": "strike", "means": "cruise", "target": "a1", "count": 2}
	assert_true(OperationalCommandCodec.from_dict(good) != null)
	for key in ["means", "target", "count"]:
		var missing := good.duplicate()
		missing.erase(key)
		assert_true(OperationalCommandCodec.from_dict(missing) == null, "missing " + key)
	var cases: Array[Dictionary] = [
		{"means": 1},
		{"target": 3},
		{"count": "2"},
		{"count": 1.5},
		{"count": true},
	]
	for patch in cases:
		var bad := good.duplicate()
		bad.merge(patch, true)
		assert_true(OperationalCommandCodec.from_dict(bad) == null, str(patch))
	var unknown := good.duplicate()
	unknown["means"] = "nuke"
	unknown["target"] = "nowhere"
	var command := OperationalCommandCodec.from_dict(unknown)
	assert_true(command != null)
	assert_eq(command.validate(Strikes._state()), "unknown_means")


# --- replay ---


func test_scripted_strike_sequence_replays_identically() -> void:
	var seed_value := 7
	var state := Operation.build(&"suwalki_gap", seed_value)
	var sim := _sim(state)
	var seen := _collect(sim)
	# Russia moves first: a strike on the urban Elk depot raises the level to Open war, which
	# opens Kaliningrad and Chernyakhovsk to NATO; a full round brings resupply and repair.
	var script: Array[OperationalCommand] = [
		StrikeCommand.new(&"kalibr", &"nato_depot_elk", 2),
		EndOperationalTurnCommand.new(),
		StrikeCommand.new(&"atacms", &"ru_airfield_chernyakhovsk", 2),
		EndOperationalTurnCommand.new(),
		StrikeCommand.new(&"kalibr", &"pl_tank_2", 2),
		EndOperationalTurnCommand.new(),
		EndOperationalTurnCommand.new(),
	]
	for command in script:
		assert_true(sim.execute(command), str(command.to_dict()))
	var record := CampaignRecord.from_simulation(sim, seed_value, &"russia", [])
	var replay := CampaignRecord.from_json(record.to_json()).replay()
	assert_true(replay["ok"], str(replay))
	assert_eq((replay["simulation"] as OperationalSimulation).state.snapshot(), state.snapshot())
	assert_eq(replay["events"], seen)
	var types := _types(seen)
	assert_true(types.has(&"strike_resolved"))
	assert_true(types.has(&"installation_changed"))
	assert_eq(state.escalation_level >= 2, true)


## TASK-141a: no legacy aliases – a saved operation that strikes with an old generic id (or any
## unknown means) does not load: its replay stops at that command with `unknown_means`.
func test_record_with_an_old_means_id_is_rejected() -> void:
	var seed_value := 7
	var sim := _sim(Operation.build(&"suwalki_gap", seed_value))
	assert_true(sim.execute(StrikeCommand.new(&"kalibr", &"nato_depot_elk", 2)))
	var record := CampaignRecord.from_simulation(sim, seed_value, &"russia", [])
	assert_true(CampaignRecord.from_json(record.to_json()).replay()["ok"])
	for old_id in ["cruise", "ballistic", "strike_drone"]:
		var text := record.to_json().replace('"kalibr"', '"%s"' % old_id)
		var replay := CampaignRecord.from_json(text).replay()
		assert_false(replay["ok"], old_id)
		assert_eq(replay["error"], "diverged", old_id)
		assert_eq(replay["index"], 0, old_id)
		assert_eq(replay["reason"], "unknown_means", old_id)


## A NATO player holds no Russian weapon: striking with one is out of stock.
func test_strike_with_the_other_sides_weapon_is_out_of_stock() -> void:
	var state := Operation.build(&"suwalki_gap", 7)
	state.current_player = 0
	state.escalation_level = 3
	var sim := _sim(state)
	var reasons := _reasons(sim)
	assert_false(sim.execute(StrikeCommand.new(&"iskander_m", &"ru_airfield_chernyakhovsk", 1)))
	assert_eq(reasons, ["out_of_stock"])
	var stock_before := StrikeRules.stock(state, 0, &"jassm_er")
	assert_true(sim.execute(StrikeCommand.new(&"jassm_er", &"ru_airfield_chernyakhovsk", 2)))
	assert_eq(StrikeRules.stock(state, 0, &"jassm_er"), stock_before - 2)
