# gdlint: disable=max-public-methods
extends TestCase
## Formation orders (TASK-092d): postures as data, issue / cancel order, set posture, codec.

const Fixtures := preload("res://tests/fixtures.gd")

var _events: Array[Dictionary] = []


## Plains rows q 0…9, r 0…1. Own formation "f" (player 0, 8 move points) on (0, 0), the
## extras {coord: owner}. current_player = 0.
static func _state(extras: Dictionary = {}) -> OperationalState:
	var state := OperationalState.new()
	var grid := HexGrid.new()
	for q in range(0, 10):
		for r in range(0, 2):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	grid.set_terrain(Vector2i(1, 1), Terrain.Type.WATER)
	state.grid = grid
	state.formations.append(_formation(&"f", 0, Vector2i.ZERO))
	var n := 0
	for coord: Vector2i in extras:
		n += 1
		state.formations.append(_formation(StringName("x%d" % n), extras[coord] as int, coord))
	return state


static func _formation(id: StringName, owner: int, coord: Vector2i) -> Formation:
	var f := Formation.new()
	f.id = id
	f.owner_id = owner
	f.coord = coord
	f.definition = FormationDefinition.new()
	return f


## `state` with the enemy of TASK-092c's contact grid on (4, 1).
static func _contact_state() -> OperationalState:
	return _state({Vector2i(4, 1): 1})


func _sim(state: OperationalState) -> OperationalSimulation:
	_events.clear()
	var sim := OperationalSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: _events.append(e))
	return sim


func _reason(state: OperationalState, command: OperationalCommand) -> String:
	return command.validate(state)


# --- posture data ---


func test_shipped_postures() -> void:
	assert_eq(OperationalPosture.NAMES, [&"march", &"advance", &"defend"] as Array[StringName])
	var expected := {&"march": [100, true], &"advance": [75, false], &"defend": [50, true]}
	for id: StringName in expected:
		var p := OperationalPosture.find(id)
		assert_true(p != null, str(id))
		assert_eq(p.id, id)
		assert_eq(p.problem(), "")
		assert_true(p.display_name != "")
		assert_eq([p.move_percent, p.avoids_contact], expected[id])
	assert_true(OperationalPosture.find(&"nope") == null)


func test_budget() -> void:
	var march := OperationalPosture.find(&"march")
	var advance := OperationalPosture.find(&"advance")
	var defend := OperationalPosture.find(&"defend")
	assert_eq([march.budget(8), advance.budget(8), defend.budget(8)], [8, 6, 4])
	assert_eq(advance.budget(5), 3)
	assert_eq(defend.budget(1), 1)


func test_problem() -> void:
	var p := OperationalPosture.new()
	p.move_percent = 0
	assert_true(p.problem() != "")
	p.move_percent = 101
	assert_true(p.problem() != "")
	p.move_percent = 1
	assert_eq(p.problem(), "")
	p.move_percent = 100
	assert_eq(p.problem(), "")


# --- state ---


func test_shipped_operation_starts_in_defend_without_orders() -> void:
	var state := Operation.build(&"suwalki_gap", 3)
	assert_eq(OperationDefinition.find(&"suwalki_gap").initial_posture, &"defend")
	for entry: Dictionary in state.snapshot()["formations"]:
		assert_eq(entry["posture"], "defend")
		assert_true(entry["order"] == null)
	for f in state.formations:
		assert_eq(f.posture, &"defend")
		assert_true(f.order == null)


func test_unknown_initial_posture_rejected() -> void:
	var definition := OperationDefinition.find(&"suwalki_gap").duplicate() as OperationDefinition
	definition.initial_posture = &"nope"
	assert_true(Operation.from_definition(definition, 1) == null)


func test_initial_posture_applies() -> void:
	var definition := OperationDefinition.find(&"suwalki_gap").duplicate() as OperationDefinition
	definition.initial_posture = &"march"
	var state := Operation.from_definition(definition, 1)
	assert_true(state != null)
	assert_eq(state.formations[0].posture, &"march")


func test_snapshot_has_order() -> void:
	var state := _state()
	assert_true(state.snapshot()["formations"][0]["order"] == null)
	assert_true(_sim(state).execute(IssueOrderCommand.new(&"f", Vector2i(5, 0), &"advance")))
	var entry: Dictionary = state.snapshot()["formations"][0]
	assert_eq(entry["order"], [5, 0])
	assert_eq(entry["posture"], "advance")


# --- IssueOrderCommand ---


func test_issue_rejections_in_order() -> void:
	var state := _state({Vector2i(7, 0): 1, Vector2i(6, 0): 0})
	var dest := Vector2i(5, 0)
	assert_eq(_reason(state, IssueOrderCommand.new(&"nope", dest, &"march")), "formation_not_found")
	assert_eq(_reason(state, IssueOrderCommand.new(&"x1", dest, &"march")), "not_your_formation")
	assert_eq(_reason(state, IssueOrderCommand.new(&"f", dest, &"nope")), "unknown_posture")
	for bad in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(20, 0)]:
		assert_eq(
			_reason(state, IssueOrderCommand.new(&"f", bad, &"march")),
			"invalid_destination",
			str(bad)
		)
	assert_eq(_reason(state, IssueOrderCommand.new(&"f", Vector2i(6, 0), &"march")), "occupied")
	assert_eq(
		_reason(state, IssueOrderCommand.new(&"f", Vector2i(7, 0), &"march")), "enemy_destination"
	)
	assert_eq(_reason(state, IssueOrderCommand.new(&"f", dest, &"march")), "")


func test_issue_battle_pending_first() -> void:
	var state := _state()
	state.pending_battles.append(BattleSetup.new())
	assert_eq(
		_reason(state, IssueOrderCommand.new(&"nope", Vector2i(5, 0), &"x")), "battle_pending"
	)


func test_issue_no_route() -> void:
	var state := _contact_state()
	var march := IssueOrderCommand.new(&"f", Vector2i(6, 0), &"march")
	assert_eq(march.validate(state), "no_route")
	assert_eq(IssueOrderCommand.new(&"f", Vector2i(6, 0), &"advance").validate(state), "")


func test_issue_apply_and_forecast() -> void:
	var state := _state()
	state.formations[0].definition.move_points = 8
	var sim := _sim(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(6, 0), &"advance")))
	var f := state.formations[0]
	assert_eq(f.coord, Vector2i.ZERO)
	assert_eq(f.posture, &"advance")
	assert_eq(f.order.destination, Vector2i(6, 0))
	assert_eq(_events.size(), 1)
	var e := _events[0]
	assert_eq(e["type"], &"formation_order_issued")
	assert_eq(e["formation_id"], &"f")
	assert_eq(e["destination"], Vector2i(6, 0))
	assert_eq(e["posture"], &"advance")
	assert_eq(e["forecast"], [Vector2i(3, 0), Vector2i(6, 0)] as Array[Vector2i])
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(6, 0), &"defend")))
	assert_eq(
		_events[1]["forecast"], [Vector2i(2, 0), Vector2i(4, 0), Vector2i(6, 0)] as Array[Vector2i]
	)


func test_issue_twice_replaces_order() -> void:
	var state := _state()
	var sim := _sim(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(3, 0), &"march")))
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(5, 0), &"march")))
	assert_eq(state.formations[0].order.destination, Vector2i(5, 0))


func test_order_survives_a_round() -> void:
	var state := _state()
	state.first_player = 0
	var sim := _sim(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(5, 0), &"march")))
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(state.formations[0].coord, Vector2i(4, 0))
	assert_eq(state.formations[0].order.destination, Vector2i(5, 0))


# --- CancelOrderCommand ---


func test_cancel_rejections_and_apply() -> void:
	var state := _state({Vector2i(7, 0): 1})
	var sim := _sim(state)
	assert_eq(CancelOrderCommand.new(&"nope").validate(state), "formation_not_found")
	assert_eq(CancelOrderCommand.new(&"x1").validate(state), "not_your_formation")
	assert_eq(CancelOrderCommand.new(&"f").validate(state), "no_order")
	state.pending_battles.append(BattleSetup.new())
	assert_eq(CancelOrderCommand.new(&"f").validate(state), "battle_pending")
	state.pending_battles.clear()
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(5, 0), &"advance")))
	assert_true(sim.execute(CancelOrderCommand.new(&"f")))
	assert_true(state.formations[0].order == null)
	assert_eq(state.formations[0].posture, &"advance")
	assert_eq(_events[1], {"type": &"formation_order_cancelled", "formation_id": &"f"})


# --- SetPostureCommand ---


func test_set_posture_rejections() -> void:
	var state := _state({Vector2i(7, 0): 1})
	assert_eq(SetPostureCommand.new(&"nope", &"march").validate(state), "formation_not_found")
	assert_eq(SetPostureCommand.new(&"x1", &"march").validate(state), "not_your_formation")
	assert_eq(SetPostureCommand.new(&"f", &"nope").validate(state), "unknown_posture")
	assert_eq(SetPostureCommand.new(&"f", &"defend").validate(state), "same_posture")
	state.pending_battles.append(BattleSetup.new())
	assert_eq(SetPostureCommand.new(&"f", &"march").validate(state), "battle_pending")


func test_set_posture_keeps_order() -> void:
	var state := _state()
	var sim := _sim(state)
	assert_true(sim.execute(SetPostureCommand.new(&"f", &"march")))
	assert_eq(
		_events[0],
		{
			"type": &"formation_posture_changed",
			"formation_id": &"f",
			"posture": &"march",
			"previous": &"defend",
		}
	)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(5, 0), &"march")))
	assert_true(sim.execute(SetPostureCommand.new(&"f", &"advance")))
	assert_eq(state.formations[0].posture, &"advance")
	assert_eq(state.formations[0].order.destination, Vector2i(5, 0))


# --- codec ---


func _round_trip(command: OperationalCommand) -> Dictionary:
	var json := JSON.stringify(command.to_dict())
	var back := OperationalCommandCodec.from_dict(JSON.parse_string(json) as Dictionary)
	assert_true(back != null)
	assert_eq(back.to_dict(), command.to_dict())
	return back.to_dict()


func test_codec_round_trip() -> void:
	assert_eq(
		_round_trip(IssueOrderCommand.new(&"f", Vector2i(5, -2), &"advance")),
		{"type": "issue_order", "formation_id": "f", "destination": [5, -2], "posture": "advance"}
	)
	assert_eq(
		_round_trip(CancelOrderCommand.new(&"f")), {"type": "cancel_order", "formation_id": "f"}
	)
	assert_eq(
		_round_trip(SetPostureCommand.new(&"f", &"march")),
		{"type": "set_posture", "formation_id": "f", "posture": "march"}
	)


func test_codec_rejects_bad_input() -> void:
	var issue := {
		"type": "issue_order", "formation_id": "f", "destination": [1, 2], "posture": "march"
	}
	assert_true(OperationalCommandCodec.from_dict(issue) != null)
	var bad_values := {
		"formation_id": [5, null, ["f"]],
		"posture": [5, null],
		"destination": [[1], [1, 2, 3], [1.5, 2], ["1", 2], [1, null], "1,2", null],
	}
	for key: String in bad_values:
		for value: Variant in bad_values[key]:
			var d := issue.duplicate()
			d[key] = value
			assert_true(OperationalCommandCodec.from_dict(d) == null, "%s=%s" % [key, value])
		var missing := issue.duplicate()
		missing.erase(key)
		assert_true(OperationalCommandCodec.from_dict(missing) == null, "missing " + key)
	assert_true(
		OperationalCommandCodec.from_dict({"type": "cancel_order", "formation_id": 3}) == null
	)
	assert_true(OperationalCommandCodec.from_dict({"type": "cancel_order"}) == null)
	assert_true(
		OperationalCommandCodec.from_dict({"type": "set_posture", "formation_id": "f"}) == null
	)
	issue["posture"] = "nope"
	assert_true(OperationalCommandCodec.from_dict(issue) != null)
