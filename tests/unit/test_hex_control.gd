extends TestCase
## Hex control (TASK-107a): initial holders, taking a hex by ending a move or winning a battle,
## the `objective_changed` event, saving and replay.

const Politics := preload("res://tests/unit/test_country_rules.gd")
const Battle := preload("res://tests/unit/test_battle_consequences.gd")

var _events: Array[Dictionary] = []


## Strip state (poland q0-1, lithuania q2-3, belarus q4-5, russia q6-7; two rows) with an
## objective on (4, 0) scored by side 1.
static func _strip() -> OperationalState:
	var s := Politics._strip()
	var objective := OperationObjective.new()
	objective.id = &"gate"
	objective.coord = Vector2i(4, 0)
	objective.side = 1
	var def := OperationDefinition.new()
	def.objectives = [objective] as Array[OperationObjective]
	s.definition = def
	s.first_player = 1
	s.current_player = 1
	return s


static func _red(s: OperationalState, id: StringName, at: Vector2i) -> Formation:
	var f := Formation.new()
	f.id = id
	f.owner_id = 1
	f.coord = at
	f.definition = FormationDefinition.new()
	f.companies.append(Formation.Company.new(&"t72b3", 5, "%s/1" % id))
	s.formations.append(f)
	return f


func _run(s: OperationalState, commands: Array[OperationalCommand]) -> void:
	_events.clear()
	var sim := OperationalSimulation.new(s)
	sim.event_emitted.connect(func(e: Dictionary) -> void: _events.append(e))
	for command in commands:
		assert_true(sim.execute(command))


func _changes() -> Array[Dictionary]:
	return _events.filter(func(e: Dictionary) -> bool: return e["type"] == &"objective_changed")


func test_initial_holders_follow_the_country() -> void:
	var s := Politics._strip()
	assert_eq(HexControl.holder(s, Vector2i(0, 0)), 0, "Polish hex")
	assert_eq(HexControl.holder(s, Vector2i(2, 1)), 0, "Lithuania aligned with side 0")
	assert_eq(HexControl.holder(s, Vector2i(7, 1)), 1, "Russian hex")
	assert_eq(HexControl.holder(s, Vector2i(99, 99)), -1, "off the map")


func test_country_with_no_side_starts_unheld() -> void:
	var op := Politics._definition()
	op.countries[2] = Politics._setup(&"belarus", &"neutral", -1, 1)
	var s := Politics._strip(op)
	assert_eq(HexControl.holder(s, Vector2i(5, 0)), -1)
	assert_eq(HexControl.holder(s, Vector2i(7, 0)), 1)


func test_start_formation_hex_belongs_to_its_side() -> void:
	var s := Politics._strip()
	_red(s, &"r", Vector2i(0, 0))
	assert_eq(HexControl.holder(s, Vector2i(0, 0)), 0, "before the setup")
	HexControl.setup(s)
	assert_eq(HexControl.holder(s, Vector2i(0, 0)), 1)


func test_installation_hex_is_held_with_its_hex() -> void:
	var s := _strip()
	s.installations.append(Installation.new())
	s.installations[0].id = &"depot"
	s.installations[0].coord = Vector2i(4, 1)
	var objective := OperationObjective.new()
	objective.installation_id = &"depot"
	assert_eq(HexControl.holder(s, objective.hex_in(s)), 1)
	s.hex_holders[Vector2i(4, 1)] = 0
	assert_eq(HexControl.holder(s, objective.hex_in(s)), 0)


func test_ending_a_move_takes_the_hex_passing_through_does_not() -> void:
	var s := _strip()
	var f := _red(s, &"r", Vector2i(7, 0))
	s.hex_holders[Vector2i(5, 0)] = 0
	s.hex_holders[Vector2i(4, 0)] = 0
	var orders: Array[OperationalCommand] = [
		IssueOrderCommand.new(&"r", Vector2i(4, 0), &"march"), EndOperationalTurnCommand.new()
	]
	_run(s, orders)
	assert_eq(f.coord, Vector2i(4, 0))
	assert_eq(HexControl.holder(s, Vector2i(4, 0)), 1, "the move ended there")
	assert_eq(HexControl.holder(s, Vector2i(5, 0)), 0, "passed through")
	assert_eq(_changes().size(), 1)
	assert_eq(_changes()[0]["hex"], Vector2i(4, 0))
	assert_eq(_changes()[0]["holder"], 1)
	assert_eq(_changes()[0]["previous"], 0)


func test_no_event_for_a_hex_without_an_objective() -> void:
	var s := _strip()
	_red(s, &"r", Vector2i(7, 0))
	s.hex_holders[Vector2i(6, 0)] = 0
	var orders: Array[OperationalCommand] = [
		IssueOrderCommand.new(&"r", Vector2i(6, 0), &"march"), EndOperationalTurnCommand.new()
	]
	_run(s, orders)
	assert_eq(HexControl.holder(s, Vector2i(6, 0)), 1)
	assert_eq(_changes().size(), 0)


func test_chain_hex_change_emits_an_event() -> void:
	var s := _strip()
	s.definition.gap_chain = [Vector2i(6, 0), Vector2i(7, 0), Vector2i(7, 1)] as Array[Vector2i]
	var events := HexControl.take(s, Vector2i(7, 1), 0)
	assert_eq(events.size(), 1)
	var expected := {
		"type": &"objective_changed", "hex": Vector2i(7, 1), "holder": 0, "previous": 1
	}
	assert_eq(events[0], expected)
	assert_eq(HexControl.take(s, Vector2i(7, 1), 0), [] as Array[Dictionary], "no change")


# --- battle ---


## The Battle fixture state (att side 0 on (0, 0) attacks def side 1 on (1, 0)) with an objective
## on the defender's hex that side 1 holds.
func _battle_state() -> OperationalState:
	var s := Battle._state()
	var objective := OperationObjective.new()
	objective.id = &"ridge"
	objective.coord = Vector2i(1, 0)
	objective.side = 0
	s.definition = OperationDefinition.new()
	s.definition.objectives = [objective] as Array[OperationObjective]
	s.hex_initial = {Vector2i(0, 0): 0, Vector2i(1, 0): 1}
	return s


func _resolve(s: OperationalState, ends: Array[int], winner: int) -> void:
	var result := Battle._result(s.pending_battles[0], ends, winner)
	_run(s, [ResolveBattleCommand.new(result)] as Array[OperationalCommand])


func test_attacker_that_wins_takes_the_hex() -> void:
	var s := _battle_state()
	_resolve(s, [10, 10, 10, 10, 0, 0] as Array[int], 0)
	assert_eq(HexControl.holder(s, Vector2i(1, 0)), 0)
	assert_eq(_changes().size(), 1)
	assert_eq(_changes()[0]["previous"], 1)


func test_drawn_or_lost_battle_changes_nothing() -> void:
	var drawn := _battle_state()
	_resolve(drawn, [5, 5, 5, 5, 5, 5] as Array[int], -1)
	assert_eq(HexControl.holder(drawn, Vector2i(1, 0)), 1)
	var lost := _battle_state()
	_resolve(lost, [0, 0, 0, 0, 10, 10] as Array[int], 1)
	assert_eq(HexControl.holder(lost, Vector2i(1, 0)), 1)
	assert_eq(_changes().size(), 0)


# --- saving and replay ---


func test_holders_are_saved_and_replay_is_identical() -> void:
	var a := _strip()
	_red(a, &"r", Vector2i(7, 0))
	a.hex_holders[Vector2i(4, 0)] = 0
	var snapshot := a.snapshot()
	assert_eq(snapshot["hex_holders"], [[4, 0, 0]])
	var orders: Array[OperationalCommand] = [
		IssueOrderCommand.new(&"r", Vector2i(4, 0), &"march"), EndOperationalTurnCommand.new()
	]
	_run(a, orders)
	var b := _strip()
	_red(b, &"r", Vector2i(7, 0))
	b.hex_holders[Vector2i(4, 0)] = 0
	_run(b, orders)
	assert_eq(a.snapshot(), b.snapshot())
	assert_eq(a.snapshot()["hex_holders"], [[4, 0, 1]])
