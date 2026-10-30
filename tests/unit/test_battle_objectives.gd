# gdlint: disable=max-public-methods
extends TestCase
## Per-battle victory conditions and turn limit (TASK-088): BattleObjectives, BattleRules and the
## commands that call them.

const Fixtures := preload("res://tests/fixtures.gd")
const OBJECTIVE := Vector2i(1, 0)

var state: GameState
var sim: GameSimulation
var unit: Unit
var enemy: Unit
var events: Array[Dictionary] = []
var rejections: Array[String] = []


func before_each() -> void:
	state = GameState.new(Fixtures.plains_grid(4), 2, 1)
	unit = state.add_unit(0, Fixtures.infantry(), Vector2i(0, 0))
	enemy = state.add_unit(1, Fixtures.infantry(), Vector2i(3, 0))
	_restart()


## A fresh simulation on `state` (after units or objectives changed), with recorded events.
func _restart() -> void:
	state.record_starting_hp()
	sim = GameSimulation.new(state)
	events.clear()
	rejections.clear()
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	sim.command_rejected.connect(
		func(_c: Command, reason: String) -> void: rejections.append(reason)
	)


func _use(objectives: BattleObjectives) -> void:
	state.set_objectives(objectives)
	_restart()


func _events_of(type: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for e in events:
		if e["type"] == type:
			result.append(e)
	return result


func _end_turns(count: int) -> void:
	for i in count:
		assert_true(sim.execute(EndTurnCommand.new()), "end turn %d" % i)


# --- data ---------------------------------------------------------------------------------------


func test_default_objectives_are_eliminate_for_both_without_a_limit() -> void:
	var o := BattleObjectives.default_objectives()
	assert_eq(o.turn_limit, 0)
	assert_eq(o.hexes.size(), 0)
	assert_eq(o.conditions.size(), 1)
	assert_eq(o.conditions[0].kind, VictoryCondition.Kind.ELIMINATE)
	assert_eq(o.conditions[0].player, -1)


func test_new_state_runs_with_default_objectives() -> void:
	assert_false(state.is_over())
	assert_eq(state.end_reason, &"")
	assert_eq(state.winner, -1)
	assert_eq(state.objectives.to_dict(), BattleObjectives.default_objectives().to_dict())
	assert_eq(state.objective_owners, {})


func test_set_objectives_copies_initial_owners() -> void:
	_use(Fixtures.objectives(0, [OBJECTIVE, Vector2i(0, 1)], [1, -1], []))
	assert_eq(state.objective_owners, {OBJECTIVE: 1, Vector2i(0, 1): -1})


func test_starting_hp_per_player() -> void:
	state.add_unit(1, Fixtures.fighter(4, 2, 6), Vector2i(-3, 0))
	state.record_starting_hp()
	assert_eq(state.starting_hp, [10, 16] as Array[int])


# --- ownership ----------------------------------------------------------------------------------


func test_ending_a_move_on_an_objective_captures_it() -> void:
	_use(Fixtures.objectives(0, [OBJECTIVE], [1], []))
	assert_true(sim.execute(MoveUnitCommand.new(unit.id, OBJECTIVE)))
	assert_eq(state.objective_owners[OBJECTIVE], 0)
	assert_eq(events.size(), 2)
	assert_eq(events[0]["type"], &"unit_moved")
	assert_eq(
		events[1],
		{"type": &"objective_captured", "coord": OBJECTIVE, "player": 0, "previous_owner": 1}
	)


func test_neutral_objective_is_captured_from_minus_one() -> void:
	_use(Fixtures.objectives(0, [OBJECTIVE], [-1], []))
	sim.execute(MoveUnitCommand.new(unit.id, OBJECTIVE))
	assert_eq(_events_of(&"objective_captured")[0]["previous_owner"], -1)


func test_passing_through_an_objective_does_not_capture_it() -> void:
	_use(Fixtures.objectives(0, [OBJECTIVE], [1], []))
	assert_true(sim.execute(MoveUnitCommand.new(unit.id, Vector2i(2, 0))))
	assert_true((events[0]["path"] as Array).has(OBJECTIVE), "the path crosses the objective")
	assert_eq(state.objective_owners[OBJECTIVE], 1)
	assert_eq(_events_of(&"objective_captured").size(), 0)


func test_entering_an_own_objective_emits_nothing() -> void:
	_use(Fixtures.objectives(0, [OBJECTIVE], [0], []))
	sim.execute(MoveUnitCommand.new(unit.id, OBJECTIVE))
	assert_eq(state.objective_owners[OBJECTIVE], 0)
	assert_eq(_events_of(&"objective_captured").size(), 0)


func test_owner_stays_after_the_unit_leaves() -> void:
	_use(Fixtures.objectives(0, [OBJECTIVE], [1], []))
	sim.execute(MoveUnitCommand.new(unit.id, OBJECTIVE))
	sim.execute(MoveUnitCommand.new(unit.id, Vector2i(1, 1)))
	assert_eq(state.objective_owners[OBJECTIVE], 0)


# --- eliminate ----------------------------------------------------------------------------------


func test_eliminate_ends_with_reason_eliminated() -> void:
	enemy.coord = Vector2i(1, 0)
	enemy.hp = 2
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_true(state.is_over())
	assert_eq(state.end_reason, &"eliminated")
	assert_eq(events[2], {"type": &"game_over", "winner": 0, "reason": &"eliminated"})


func test_wiping_out_a_side_without_an_eliminate_condition_does_not_end_the_battle() -> void:
	_use(Fixtures.objectives(3, [], [], [Fixtures.condition(VictoryCondition.Kind.ELIMINATE, 1)]))
	enemy.coord = Vector2i(1, 0)
	enemy.hp = 2
	assert_true(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_false(enemy.is_alive())
	assert_false(state.is_over())
	assert_eq(_events_of(&"game_over").size(), 0)
	assert_true(sim.execute(EndTurnCommand.new()), "the battle goes on")


# --- destroy share ------------------------------------------------------------------------------


func test_destroy_share_wins_once_the_enemy_lost_the_share() -> void:
	var second := state.add_unit(1, Fixtures.infantry(), Vector2i(-1, 0))
	var other := state.add_unit(0, Fixtures.infantry(), Vector2i(-1, 1))
	enemy.coord = Vector2i(1, 0)
	_use(
		Fixtures.objectives(
			0, [], [], [Fixtures.condition(VictoryCondition.Kind.DESTROY_SHARE, 0, [], 20)]
		)
	)
	assert_eq(state.starting_hp, [20, 20] as Array[int])
	sim.execute(AttackCommand.new(unit.id, enemy.id))  # 2 of 20 = 10 %
	assert_false(state.is_over())
	sim.execute(AttackCommand.new(other.id, second.id))  # 4 of 20 = 20 %
	assert_true(state.is_over())
	assert_eq(state.winner, 0)
	assert_eq(state.end_reason, &"enemy_destroyed")
	assert_eq(events.back(), {"type": &"game_over", "winner": 0, "reason": &"enemy_destroyed"})


func test_destroy_share_win_skips_the_counter() -> void:
	enemy.coord = Vector2i(1, 0)
	_use(
		Fixtures.objectives(
			0, [], [], [Fixtures.condition(VictoryCondition.Kind.DESTROY_SHARE, -1, [], 10)]
		)
	)
	sim.execute(AttackCommand.new(unit.id, enemy.id))
	assert_eq(state.winner, 0, "the striker's side is checked first")
	assert_eq(unit.hp, 10, "no counter after the battle ended")
	assert_eq(_events_of(&"unit_attacked").size(), 1)


func test_a_counter_can_win_by_destroy_share() -> void:
	enemy.coord = Vector2i(1, 0)
	_use(
		Fixtures.objectives(
			0, [], [], [Fixtures.condition(VictoryCondition.Kind.DESTROY_SHARE, 1, [], 20)]
		)
	)
	sim.execute(AttackCommand.new(unit.id, enemy.id))
	assert_eq(unit.hp, 8)
	assert_eq(state.winner, 1)
	assert_eq(state.end_reason, &"enemy_destroyed")


# --- take hexes ---------------------------------------------------------------------------------


func _take_both(player: int) -> BattleObjectives:
	var hexes: Array[Vector2i] = [OBJECTIVE, Vector2i(0, 1)]
	return Fixtures.objectives(
		0, hexes, [1, 1], [Fixtures.condition(VictoryCondition.Kind.TAKE_HEXES, player, hexes)]
	)


func test_take_hexes_wins_at_the_end_of_the_own_turn() -> void:
	unit.coord = OBJECTIVE
	state.add_unit(0, Fixtures.infantry(), Vector2i(0, 1))
	_use(_take_both(0))
	assert_true(sim.execute(EndTurnCommand.new()))
	assert_eq(events.size(), 2)
	assert_eq(events[0], {"type": &"turn_ended", "player": 0})
	assert_eq(events[1], {"type": &"game_over", "winner": 0, "reason": &"objective_taken"})
	assert_eq(state.turn, 1)
	assert_eq(state.current_player, 0)


func test_take_hexes_needs_every_hex() -> void:
	unit.coord = OBJECTIVE
	_use(_take_both(0))
	sim.execute(EndTurnCommand.new())
	assert_false(state.is_over())
	assert_eq(state.current_player, 1)


func test_take_hexes_is_checked_only_for_the_player_ending_the_turn() -> void:
	enemy.coord = OBJECTIVE
	state.add_unit(1, Fixtures.infantry(), Vector2i(0, 1))
	_use(_take_both(1))
	sim.execute(EndTurnCommand.new())  # player 0 ends
	assert_false(state.is_over())
	sim.execute(EndTurnCommand.new())  # player 1 ends
	assert_eq(state.winner, 1)
	assert_eq(state.end_reason, &"objective_taken")


func test_owning_without_a_unit_does_not_take() -> void:
	var hexes: Array[Vector2i] = [OBJECTIVE]
	_use(
		Fixtures.objectives(
			0, hexes, [0], [Fixtures.condition(VictoryCondition.Kind.TAKE_HEXES, 0, hexes)]
		)
	)
	sim.execute(EndTurnCommand.new())
	assert_false(state.is_over())


# --- turn limit ---------------------------------------------------------------------------------


func _hold(turn_limit: int, owner: int, conditions: Array[VictoryCondition]) -> BattleObjectives:
	return Fixtures.objectives(turn_limit, [OBJECTIVE], [owner], conditions)


func _hold_for(player: int) -> VictoryCondition:
	return Fixtures.condition(
		VictoryCondition.Kind.HOLD_HEXES, player, [OBJECTIVE] as Array[Vector2i]
	)


func test_turn_limit_hold_hexes_winner() -> void:
	_use(_hold(2, 1, [_hold_for(1)]))
	_end_turns(3)
	assert_false(state.is_over(), "not before the last player's turn of the last turn")
	events.clear()
	assert_true(sim.execute(EndTurnCommand.new()))
	assert_eq(state.winner, 1)
	assert_eq(state.end_reason, &"turn_limit")
	assert_eq(
		events,
		(
			[
				{"type": &"turn_ended", "player": 1},
				{"type": &"game_over", "winner": 1, "reason": &"turn_limit"},
			]
			as Array[Dictionary]
		)
	)
	assert_eq(state.turn, 2, "the turn does not advance")


func test_turn_limit_without_a_qualifying_player_is_a_draw() -> void:
	_use(_hold(1, -1, [_hold_for(1)]))
	_end_turns(2)
	assert_true(state.is_over())
	assert_eq(state.winner, -1)
	assert_eq(state.end_reason, &"turn_limit")
	assert_eq(events.back(), {"type": &"game_over", "winner": -1, "reason": &"turn_limit"})


func test_capturing_a_held_hex_denies_the_holder() -> void:
	_use(_hold(1, 1, [_hold_for(1)]))
	sim.execute(MoveUnitCommand.new(unit.id, OBJECTIVE))
	_end_turns(2)
	assert_eq(state.winner, -1)


func test_capturing_wins_with_an_own_hold_condition() -> void:
	_use(_hold(1, 1, [_hold_for(-1)]))
	sim.execute(MoveUnitCommand.new(unit.id, OBJECTIVE))
	_end_turns(2)
	assert_eq(state.winner, 0)


func test_two_qualifying_players_draw() -> void:
	var hexes: Array[Vector2i] = [OBJECTIVE, Vector2i(0, 1)]
	var conditions: Array[VictoryCondition] = [
		Fixtures.condition(VictoryCondition.Kind.HOLD_HEXES, 0, [OBJECTIVE] as Array[Vector2i]),
		Fixtures.condition(
			VictoryCondition.Kind.HOLD_HEXES, 1, [Vector2i(0, 1)] as Array[Vector2i]
		),
	]
	_use(Fixtures.objectives(1, hexes, [0, 1], conditions))
	_end_turns(2)
	assert_true(state.is_over())
	assert_eq(state.winner, -1)


func test_no_turn_limit_never_ends() -> void:
	_use(_hold(0, 1, [_hold_for(1)]))
	_end_turns(40)
	assert_false(state.is_over())


func test_commands_are_rejected_after_a_draw() -> void:
	_use(_hold(1, -1, []))
	_end_turns(2)
	rejections.clear()
	assert_false(sim.execute(MoveUnitCommand.new(unit.id, Vector2i(0, 1))))
	assert_false(sim.execute(AttackCommand.new(unit.id, enemy.id)))
	assert_false(sim.execute(EndTurnCommand.new()))
	assert_eq(rejections, ["game_over", "game_over", "game_over"] as Array[String])


func test_take_hexes_is_checked_before_the_turn_limit() -> void:
	var hexes: Array[Vector2i] = [OBJECTIVE]
	var conditions: Array[VictoryCondition] = [
		Fixtures.condition(VictoryCondition.Kind.TAKE_HEXES, 1, hexes), _hold_for(0)
	]
	_use(Fixtures.objectives(1, hexes, [0], conditions))
	enemy.coord = OBJECTIVE
	_end_turns(2)
	assert_eq(state.winner, 1)
	assert_eq(state.end_reason, &"objective_taken")


# --- snapshot -----------------------------------------------------------------------------------


func test_snapshot_has_end_reason_and_sorted_objective_owners() -> void:
	assert_eq(state.snapshot()["end_reason"], "")
	assert_eq(state.snapshot()["objectives"], [])
	_use(Fixtures.objectives(1, [Vector2i(1, 0), Vector2i(-1, 2), Vector2i(-1, 1)], [1, -1, 0], []))
	sim.execute(MoveUnitCommand.new(unit.id, OBJECTIVE))
	_end_turns(2)
	var snap := state.snapshot()
	assert_eq(snap["end_reason"], "turn_limit")
	assert_eq(snap["objectives"], [[-1, 1, 0], [-1, 2, -1], [1, 0, 0]])
	var parsed: Dictionary = MatchRecord.normalize(JSON.parse_string(JSON.stringify(snap)))
	assert_eq(parsed, snap, "JSON-safe")


# --- JSON ---------------------------------------------------------------------------------------


static func _json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func _sample() -> BattleObjectives:
	var hexes: Array[Vector2i] = [Vector2i(6, 2), Vector2i(4, 7)]
	return (
		Fixtures
		. objectives(
			8,
			hexes,
			[1, -1],
			[
				Fixtures.condition(VictoryCondition.Kind.TAKE_HEXES, 0, hexes),
				Fixtures.condition(
					VictoryCondition.Kind.HOLD_HEXES, 1, [Vector2i(4, 7)] as Array[Vector2i]
				),
				Fixtures.condition(VictoryCondition.Kind.DESTROY_SHARE, -1, [], 60),
				Fixtures.condition(VictoryCondition.Kind.ELIMINATE, -1),
			]
		)
	)


func test_objectives_survive_a_json_round_trip() -> void:
	var o := _sample()
	var loaded := BattleObjectives.from_dict(_json(o.to_dict()))
	assert_true(loaded != null)
	assert_eq(loaded.to_dict(), o.to_dict())
	assert_eq(loaded.turn_limit, 8)
	assert_eq(loaded.hexes, o.hexes)
	assert_eq(loaded.initial_owners, [1, -1] as Array[int])
	assert_eq(loaded.conditions[2].share_percent, 60)
	assert_eq(loaded.conditions[0].kind, VictoryCondition.Kind.TAKE_HEXES)
	assert_eq(o.to_dict()["conditions"][0]["kind"], "take_hexes")


func test_empty_dict_gives_default_objectives() -> void:
	var loaded := BattleObjectives.from_dict({})
	assert_eq(loaded.to_dict(), BattleObjectives.default_objectives().to_dict())


func test_malformed_objectives_are_rejected() -> void:
	var good := _json(_sample().to_dict())
	for key: String in good.keys():
		var missing := good.duplicate(true)
		missing.erase(key)
		assert_true(BattleObjectives.from_dict(missing) == null, "without %s" % key)
	var cases := {
		"negative limit": func(d: Dictionary) -> void: d["turn_limit"] = -1,
		"float limit": func(d: Dictionary) -> void: d["turn_limit"] = 1.5,
		"owners size": func(d: Dictionary) -> void: d["initial_owners"].pop_back(),
		"bad hex": func(d: Dictionary) -> void: d["hexes"][0] = [1, "a"],
		"duplicate hex": func(d: Dictionary) -> void: d["hexes"][1] = d["hexes"][0],
		"unknown kind": func(d: Dictionary) -> void: d["conditions"][0]["kind"] = "survive",
		"no player": func(d: Dictionary) -> void: d["conditions"][0].erase("player"),
		"not an objective": func(d: Dictionary) -> void: d["conditions"][1]["hexes"] = [[0, 0]],
		"empty take": func(d: Dictionary) -> void: d["conditions"][0]["hexes"] = [],
		"share 0": func(d: Dictionary) -> void: d["conditions"][2]["share_percent"] = 0,
		"share 101": func(d: Dictionary) -> void: d["conditions"][2]["share_percent"] = 101,
		"condition not a dict": func(d: Dictionary) -> void: d["conditions"][0] = 3,
		"player -2": func(d: Dictionary) -> void: d["conditions"][0]["player"] = -2,
	}
	for name: String in cases:
		var bad := good.duplicate(true)
		(cases[name] as Callable).call(bad)
		assert_true(BattleObjectives.from_dict(bad) == null, name)


func test_setup_objectives_round_trip_and_default() -> void:
	var setup := Scenario.default_battle_setup(5)
	assert_eq(setup.objectives.to_dict(), BattleObjectives.default_objectives().to_dict())
	setup.objectives = _sample()
	var loaded := BattleSetup.from_dict(_json(setup.to_dict()))
	assert_eq(loaded.to_dict(), setup.to_dict())
	var legacy := _json(setup.to_dict())
	legacy["objectives"] = {}
	assert_eq(
		BattleSetup.from_dict(legacy).objectives.to_dict(),
		BattleObjectives.default_objectives().to_dict()
	)
	var bad := _json(setup.to_dict())
	bad["objectives"]["turn_limit"] = "8"
	assert_true(BattleSetup.from_dict(bad) == null)


# --- scenario / result --------------------------------------------------------------------------


func test_from_setup_copies_objectives_and_starting_hp() -> void:
	var setup := Scenario.default_battle_setup(5)
	var spawn := setup.companies[0].coord
	setup.objectives = Fixtures.objectives(
		4, [spawn], [1], [Fixtures.condition(VictoryCondition.Kind.ELIMINATE, -1)]
	)
	var s := Scenario.from_setup(setup)
	assert_eq(s.objectives.turn_limit, 4)
	assert_eq(s.objective_owners, {spawn: 1}, "spawning on an objective does not capture it")
	var totals: Array[int] = [0, 0]
	for company in setup.companies:
		totals[company.player] += company.strength
	assert_eq(s.starting_hp, totals)


func test_from_setup_forces_water_objectives_to_plains() -> void:
	var setup := Scenario.default_battle_setup(5)
	var ford_free_river := MapGenerator.offset_to_axial(Scenario.RIVER_COLUMNS[0], 0)
	setup.objectives = Fixtures.objectives(0, [ford_free_river], [-1], [])
	var s := Scenario.from_setup(setup)
	assert_eq(s.grid.get_terrain(ford_free_river), Terrain.Type.PLAINS)


func test_from_setup_rejects_bad_objectives() -> void:
	# Expected engine output: push_error for each rejected setup.
	var off_map := Scenario.default_battle_setup(5)
	off_map.objectives = Fixtures.objectives(0, [Vector2i(99, 99)], [-1], [])
	assert_true(Scenario.from_setup(off_map) == null)
	var bad_owner := Scenario.default_battle_setup(5)
	bad_owner.objectives = Fixtures.objectives(0, [Vector2i(3, 3)], [2], [])
	assert_true(Scenario.from_setup(bad_owner) == null)
	var bad_player := Scenario.default_battle_setup(5)
	bad_player.objectives = Fixtures.objectives(
		0, [], [], [Fixtures.condition(VictoryCondition.Kind.ELIMINATE, 2)]
	)
	assert_true(Scenario.from_setup(bad_player) == null)


func test_battle_result_reports_the_end_reason() -> void:
	var setup := Scenario.default_battle_setup(5)
	var s := Scenario.from_setup(setup)
	s.finish(-1, &"turn_limit")
	var result := BattleResult.from_battle(setup, s)
	assert_eq(result.winner, -1)
	assert_eq(result.reason, &"turn_limit")
