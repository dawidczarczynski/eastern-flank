extends TestCase
## Contact battles (TASK-094a): detection at the end of a turn, the pending BattleSetup,
## ResolveBattleCommand.

var _events: Array[Dictionary] = []


## Plains rows q 0…9, r 0…1. Own formation "f" (player 0, 2 companies) on (0, 0); enemy "e"
## (player 1, 1 company) on (4, 1). current_player = 0.
static func _state() -> OperationalState:
	var state := OperationalState.new()
	var grid := HexGrid.new()
	for q in range(0, 10):
		for r in range(0, 2):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	state.grid = grid
	state.operation_name = "OP_TEST"
	state.formations.append(_formation(&"f", 0, Vector2i.ZERO, 2))
	state.formations.append(_formation(&"e", 1, Vector2i(4, 1), 1))
	return state


static func _formation(id: StringName, owner: int, coord: Vector2i, n: int) -> Formation:
	var f := Formation.new()
	f.id = id
	f.display_name = "NAME_%s" % id
	f.owner_id = owner
	f.coord = coord
	f.definition = FormationDefinition.new()
	for i in n:
		f.companies.append(Formation.Company.new(&"leopard_2a4", 5, "%s/%d" % [id, i + 1]))
	f.companies[0].strength = 4
	return f


func _sim(state: OperationalState) -> OperationalSimulation:
	_events.clear()
	var sim := OperationalSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: _events.append(e))
	return sim


func _end(sim: OperationalSimulation) -> Array[Dictionary]:
	_events.clear()
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	return _events.duplicate()


func _of_type(events: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e["type"] == type:
			out.append(e)
	return out


## Orders F to (6, 0) with `posture` and plays until the contact; returns that turn's events.
func _contact(sim: OperationalSimulation, posture: StringName) -> Array:
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(6, 0), posture)))
	_end(sim)
	_end(sim)
	return _end(sim)


func _result_for(setup: BattleSetup, winner: int = -1) -> BattleResult:
	var result := BattleResult.new()
	result.winner = winner
	result.reason = &"turn_limit"
	result.turns = 8
	for company in setup.companies:
		var c := BattleResult.Company.new()
		c.player = company.player
		c.unit_type = company.unit_type
		c.ref = company.ref
		c.strength_start = company.strength
		c.strength_end = company.strength
		result.companies.append(c)
	return result


func test_battle_allowed_is_always_true() -> void:
	var state := _state()
	assert_true(ContactRules.battle_allowed(state, state.formations[0], state.formations[1]))


func test_postures_carry_position_bonus() -> void:
	assert_eq(OperationalPosture.find(&"defend").position_bonus, 1)
	assert_eq(OperationalPosture.find(&"advance").position_bonus, 0)
	assert_eq(OperationalPosture.find(&"march").position_bonus, -1)
	var posture := OperationalPosture.new()
	posture.position_bonus = 4
	assert_true(posture.problem() != "")
	posture.position_bonus = -4
	assert_true(posture.problem() != "")


func test_contact_makes_a_pending_battle() -> void:
	var state := _state()
	var sim := _sim(state)
	var events := _contact(sim, &"advance")
	var types: Array = events.map(func(e: Dictionary) -> Variant: return e["type"])
	assert_eq(
		types,
		[
			&"formation_moved",
			&"formation_halted",
			&"battle_pending",
			&"operational_turn_ended",
			&"operational_turn_started"
		]
	)
	var pending: Dictionary = events[2]
	assert_eq(pending["attacker_id"], &"f")
	assert_eq(pending["defender_id"], &"e")
	assert_eq(pending["at"], Vector2i(4, 1))
	assert_eq(pending["index"], 0)
	assert_eq(state.pending_battles.size(), 1)
	var setup := state.pending_battles[0]
	assert_eq(setup.attacker, 0)
	assert_eq(setup.terrain, &"plains")
	assert_eq(setup.operation_name, "OP_TEST")
	assert_eq(setup.factions.size(), 0 if state.player_factions.is_empty() else 2)
	assert_eq(setup.companies.size(), 3)
	assert_eq(setup.companies[0].ref, "f/1")
	assert_eq(setup.companies[0].strength, 4)
	assert_eq(setup.companies[0].player, 0)
	assert_eq(setup.companies[2].ref, "e/1")
	assert_eq(setup.companies[2].player, 1)
	assert_eq(setup.conditions[0].posture, &"advance")
	assert_eq(setup.conditions[0].position_bonus, 0)
	assert_eq(setup.conditions[1].posture, &"defend")
	assert_eq(setup.conditions[1].position_bonus, 1)
	assert_eq(setup.missions[0].task, &"attack")
	assert_eq(setup.missions[1].task, &"defend")
	assert_eq(setup.missions[0].formation_name, "NAME_f")
	assert_eq(setup.missions[1].formation_name, "NAME_e")
	assert_eq(setup.missions[0].intent_args, [6, 0])
	assert_eq(setup.companies[0].coord, Vector2i.ZERO)


func test_seed_is_drawn_from_the_operational_rng() -> void:
	var a := _state()
	a.rng.seed = 5
	var b := _state()
	b.rng.seed = 5
	_contact(_sim(a), &"advance")
	_contact(_sim(b), &"advance")
	var expected := RandomNumberGenerator.new()
	expected.seed = 5
	assert_eq(a.pending_battles[0].seed, expected.randi())
	assert_eq(a.pending_battles[0].seed, b.pending_battles[0].seed)
	assert_eq(a.rng.state, expected.state)


func test_terrain_is_the_defenders_hex() -> void:
	var state := _state()
	state.grid.set_terrain(Vector2i(4, 1), Terrain.Type.FOREST)
	_contact(_sim(state), &"advance")
	assert_eq(state.pending_battles[0].terrain, &"forest")


func test_defender_on_the_march_holds_out() -> void:
	var state := _state()
	state.formations[1].posture = &"march"
	_contact(_sim(state), &"advance")
	var setup := state.pending_battles[0]
	assert_eq(setup.missions[1].task, &"hold_out")
	assert_eq(setup.conditions[1].position_bonus, -1)


func test_arriving_next_to_an_enemy_starts_no_battle() -> void:
	var state := _state()
	var sim := _sim(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(4, 0), &"march")))
	_end(sim)
	assert_eq(state.formations[0].coord, Vector2i(4, 0))
	assert_true(state.pending_battles.is_empty())


func test_an_enemy_takes_part_in_one_battle_per_step() -> void:
	var state := _state()
	state.formations.append(_formation(&"g", 0, Vector2i(2, 1), 1))
	state.formations[0].coord = Vector2i(3, 0)
	var sim := _sim(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(6, 0), &"advance")))
	assert_true(sim.execute(IssueOrderCommand.new(&"g", Vector2i(6, 1), &"advance")))
	var events := _end(sim)
	assert_eq(_of_type(events, &"formation_halted").size(), 2)
	assert_eq(_of_type(events, &"battle_pending").size(), 1)
	assert_eq(state.pending_battles.size(), 1)
	assert_eq(state.pending_battles[0].companies[0].ref, "f/1")
	assert_true(state.formations[2].order != null)


func test_pending_battle_blocks_turns_until_resolved() -> void:
	var state := _state()
	var sim := _sim(state)
	_contact(sim, &"advance")
	assert_false(sim.execute(EndOperationalTurnCommand.new()))
	var setup := state.pending_battles[0]
	_events.clear()
	assert_true(sim.execute(ResolveBattleCommand.new(_result_for(setup, 0))))
	assert_true(state.pending_battles.is_empty())
	assert_eq(_events.size(), 1)
	assert_eq(_events[0]["type"], &"battle_resolved")
	assert_eq(_events[0]["attacker_id"], &"f")
	assert_eq(_events[0]["defender_id"], &"e")
	assert_eq(_events[0]["winner"], 0)
	assert_eq(_events[0]["reason"], &"turn_limit")
	assert_true(sim.execute(EndOperationalTurnCommand.new()))


func test_resolve_rejections() -> void:
	var state := _state()
	var sim := _sim(state)
	var empty := ResolveBattleCommand.new(BattleResult.new())
	assert_eq(empty.validate(state), "no_pending_battle")
	_contact(sim, &"advance")
	var setup := state.pending_battles[0]
	var fewer := _result_for(setup)
	fewer.companies.pop_back()
	assert_eq(ResolveBattleCommand.new(fewer).validate(state), "result_mismatch")
	var other_ref := _result_for(setup)
	other_ref.companies[1].ref = "zzz/1"
	assert_eq(ResolveBattleCommand.new(other_ref).validate(state), "result_mismatch")
	var other_start := _result_for(setup)
	other_start.companies[0].strength_start += 1
	assert_eq(ResolveBattleCommand.new(other_start).validate(state), "result_mismatch")
	assert_eq(state.pending_battles.size(), 1)


func test_resolve_codec_round_trip() -> void:
	var state := _state()
	_contact(_sim(state), &"advance")
	var command := ResolveBattleCommand.new(_result_for(state.pending_battles[0], 1))
	var d := JSON.parse_string(JSON.stringify(command.to_dict())) as Dictionary
	assert_eq(d["type"], "resolve_battle")
	var decoded := OperationalCommandCodec.from_dict(d)
	assert_true(decoded is ResolveBattleCommand)
	assert_eq(decoded.to_dict(), command.to_dict())
	assert_true(OperationalCommandCodec.from_dict({"type": "resolve_battle"}) == null)
	assert_true(OperationalCommandCodec.from_dict({"type": "resolve_battle", "result": 3}) == null)


func test_setup_fields_survive_json() -> void:
	var state := _state()
	state.player_factions = [&"poland", &"russia"]
	_contact(_sim(state), &"advance")
	var setup := state.pending_battles[0]
	var loaded := BattleSetup.from_dict(JSON.parse_string(JSON.stringify(setup.to_dict())))
	assert_true(loaded != null)
	assert_eq(loaded.to_dict(), setup.to_dict())
	assert_eq(loaded.missions[0].intent_args, [6, 0])
	assert_eq(loaded.attacker, 0)
	for key: String in ["attacker", "terrain", "missions"]:
		var missing := setup.to_dict()
		missing.erase(key)
		assert_true(BattleSetup.from_dict(missing) == null, key)
	var no_posture := setup.to_dict()
	no_posture["conditions"][0].erase("posture")
	assert_true(BattleSetup.from_dict(no_posture) == null)


func test_scenario_battle_has_no_contact_fields() -> void:
	var setup := Scenario.default_battle_setup(3)
	assert_eq(setup.attacker, -1)
	assert_eq(setup.terrain, &"")
	assert_eq(setup.conditions[0].posture, &"")
	assert_true(setup.missions.is_empty())
	assert_true(BattleSetup.from_dict(setup.to_dict()) != null)


func test_defender_is_first_enemy_in_direction_order() -> void:
	var state := _state()
	state.formations[0].coord = Vector2i(3, 3)
	var near: Array[Vector2i] = [Hex.neighbors(Vector2i(3, 3))[3], Hex.neighbors(Vector2i(3, 3))[1]]
	for i in near.size():
		state.formations.append(_formation(StringName("x%d" % i), 1, near[i], 1))
	var halted: Array[Dictionary] = [
		{"type": &"formation_halted", "formation_id": &"f", "reason": &"contact"}
	]
	ContactRules.start_battles(state, halted)
	assert_eq(halted.size(), 2)
	assert_eq(halted[1]["defender_id"], &"x1")


func test_contact_replay_from_dicts_is_identical() -> void:
	var runs: Array = []
	for i in 2:
		var state := _state()
		state.rng.seed = 42
		var sim := _sim(state)
		var all: Array[Dictionary] = []
		sim.execute(
			OperationalCommandCodec.from_dict(
				IssueOrderCommand.new(&"f", Vector2i(6, 0), &"advance").to_dict()
			)
		)
		for t in 3:
			all.append_array(_end(sim))
		var setup := state.pending_battles[0]
		var cmd := OperationalCommandCodec.from_dict(
			ResolveBattleCommand.new(_result_for(setup)).to_dict()
		)
		assert_true(sim.execute(cmd))
		all.append_array(_events)
		runs.append(
			[
				state.snapshot(),
				all,
				state.pending_battles.map(func(b: BattleSetup) -> Dictionary: return b.to_dict())
			]
		)
	assert_eq(runs[0], runs[1])
