# gdlint: disable=max-public-methods
extends TestCase
## Order execution at the end of a side's operational turn (TASK-092e).

var _events: Array[Dictionary] = []


## Plains rows q 0…9, r 0…1 (all land). Own formation "f" (player 0, 8 move points) on (0, 0), the
## extras {coord: owner}. current_player = 0.
static func _state(extras: Dictionary = {}) -> OperationalState:
	var state := OperationalState.new()
	var grid := HexGrid.new()
	for q in range(0, 10):
		for r in range(0, 2):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
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


func _sim(state: OperationalState) -> OperationalSimulation:
	_events.clear()
	var sim := OperationalSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: _events.append(e))
	return sim


func _order(sim: OperationalSimulation, id: StringName, to: Vector2i, posture: StringName) -> void:
	assert_true(sim.execute(IssueOrderCommand.new(id, to, posture)))


## Ends the current player's turn; returns the events of that command only.
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


## Closes the contact battle a halt started (TASK-094a) as a draw so the turns can go on.
func _resolve_pending(sim: OperationalSimulation, state: OperationalState) -> void:
	assert_eq(state.pending_battles.size(), 1)
	var result := BattleResult.new()
	for company in state.pending_battles[0].companies:
		var c := BattleResult.Company.new()
		c.player = company.player
		c.unit_type = company.unit_type
		c.ref = company.ref
		c.strength_start = company.strength
		c.strength_end = company.strength
		result.companies.append(c)
	assert_true(sim.execute(ResolveBattleCommand.new(result)))


func _round(sim: OperationalSimulation) -> Array[Dictionary]:
	var events := _end(sim)
	events.append_array(_end(sim))
	return events


# --- examples ---


func test_march_over_two_turns() -> void:
	var state := _state()
	var sim := _sim(state)
	_order(sim, &"f", Vector2i(6, 0), &"march")
	var events := _end(sim)
	var f := state.formations[0]
	assert_eq(f.coord, Vector2i(4, 0))
	assert_eq(f.order.destination, Vector2i(6, 0))
	assert_eq(events[0]["type"], &"formation_moved")
	assert_eq(events[0]["formation_id"], &"f")
	assert_eq(events[0]["from"], Vector2i(0, 0))
	assert_eq(events[0]["to"], Vector2i(4, 0))
	assert_eq(
		events[0]["path"],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)] as Array[Vector2i]
	)
	assert_eq(events[0]["cost"], 8)
	assert_eq(events[1]["type"], &"operational_turn_ended")
	# Player 1 ends: F unchanged.
	_end(sim)
	assert_eq(f.coord, Vector2i(4, 0))
	events = _end(sim)
	assert_eq(f.coord, Vector2i(6, 0))
	assert_eq(events[0]["type"], &"formation_moved")
	assert_eq(events[1]["type"], &"formation_order_completed")
	assert_eq(events[1]["destination"], Vector2i(6, 0))
	assert_eq(events[2]["type"], &"operational_turn_ended")
	assert_true(f.order == null)
	assert_eq(f.posture, &"march")


func test_defend_and_advance_pace() -> void:
	var state := _state()
	var sim := _sim(state)
	_order(sim, &"f", Vector2i(6, 0), &"defend")
	var stops: Array[Vector2i] = []
	for _i in 3:
		_end(sim)
		stops.append(state.formations[0].coord)
		_end(sim)
	assert_eq(stops, [Vector2i(2, 0), Vector2i(4, 0), Vector2i(6, 0)] as Array[Vector2i])
	assert_true(state.formations[0].order == null)
	assert_eq(state.formations[0].posture, &"defend")
	var state2 := _state()
	var sim2 := _sim(state2)
	_order(sim2, &"f", Vector2i(6, 0), &"advance")
	_end(sim2)
	assert_eq(state2.formations[0].coord, Vector2i(3, 0))
	_end(sim2)
	_end(sim2)
	assert_eq(state2.formations[0].coord, Vector2i(6, 0))
	assert_true(state2.formations[0].order == null)


func test_posture_change_between_turns() -> void:
	var state := _state()
	var sim := _sim(state)
	_order(sim, &"f", Vector2i(6, 0), &"march")
	_end(sim)
	_end(sim)
	assert_true(sim.execute(SetPostureCommand.new(&"f", &"defend")))
	var events := _end(sim)
	assert_eq(state.formations[0].coord, Vector2i(6, 0))
	assert_eq(_of_type(events, &"formation_moved")[0]["cost"], 4)


func test_contact_halts_and_keeps_order() -> void:
	var state := _state({Vector2i(4, 1): 1})
	var sim := _sim(state)
	_order(sim, &"f", Vector2i(6, 0), &"advance")
	var f := state.formations[0]
	var events := _end(sim)
	assert_eq(f.coord, Vector2i(3, 0))
	assert_eq(_of_type(events, &"formation_halted").size(), 0)
	_end(sim)
	events = _end(sim)
	assert_eq(f.coord, Vector2i(4, 0))
	assert_true(f.order != null)
	var halted := _of_type(events, &"formation_halted")
	assert_eq(halted.size(), 1)
	assert_eq(halted[0]["formation_id"], &"f")
	assert_eq(halted[0]["at"], Vector2i(4, 0))
	assert_eq(halted[0]["reason"], &"contact")
	assert_eq(events[0]["type"], &"formation_moved")
	_resolve_pending(sim, state)
	_end(sim)
	events = _end(sim)
	assert_eq(f.coord, Vector2i(5, 0))
	assert_eq(_of_type(events, &"formation_halted").size(), 1)
	_resolve_pending(sim, state)
	_end(sim)
	events = _end(sim)
	assert_eq(f.coord, Vector2i(6, 0))
	assert_eq(_of_type(events, &"formation_order_completed").size(), 1)
	assert_true(f.order == null)


func test_no_route_at_execution() -> void:
	var state := _state({Vector2i(6, 1): 1})
	var sim := _sim(state)
	_order(sim, &"f", Vector2i(6, 0), &"march")
	state.formations[1].coord = Vector2i(4, 1)
	var events := _end(sim)
	var f := state.formations[0]
	assert_eq(f.coord, Vector2i.ZERO)
	assert_true(f.order == null)
	var interrupted := _of_type(events, &"formation_order_interrupted")
	assert_eq(interrupted.size(), 1)
	assert_eq(interrupted[0]["reason"], &"no_route")
	assert_eq(interrupted[0]["at"], Vector2i.ZERO)
	assert_eq(_of_type(events, &"formation_moved").size(), 0)


func test_destination_occupied_is_deterministic() -> void:
	for f_first in [true, false]:
		var state := _state()
		state.formations.clear()
		var f := _formation(&"f", 0, Vector2i(0, 0))
		var g := _formation(&"g", 0, Vector2i(0, 1))
		state.formations.append(f if f_first else g)
		state.formations.append(g if f_first else f)
		var sim := _sim(state)
		_order(sim, &"f", Vector2i(4, 0), &"march")
		_order(sim, &"g", Vector2i(4, 0), &"march")
		var events := _end(sim)
		var winner := f if f_first else g
		var loser := g if f_first else f
		assert_eq(winner.coord, Vector2i(4, 0))
		assert_true(winner.order == null)
		var interrupted := _of_type(events, &"formation_order_interrupted")
		assert_eq(interrupted.size(), 1)
		assert_eq(interrupted[0]["formation_id"], loser.id)
		assert_eq(interrupted[0]["reason"], &"destination_occupied")
		assert_eq(interrupted[0]["at"], loser.coord)
		assert_eq(_of_type(events, &"formation_order_completed").size(), 1)
		assert_true(loser.order == null)


func test_blocked_by_own_formations() -> void:
	var state := _state({Vector2i(1, 0): 0, Vector2i(2, 0): 0})
	var sim := _sim(state)
	_order(sim, &"f", Vector2i(5, 0), &"defend")
	var events := _end(sim)
	assert_eq(state.formations[0].coord, Vector2i.ZERO)
	assert_true(state.formations[0].order == null)
	var interrupted := _of_type(events, &"formation_order_interrupted")
	assert_eq(interrupted.size(), 1)
	assert_eq(interrupted[0]["reason"], &"blocked")


func test_only_current_player_executes() -> void:
	var state := _state({Vector2i(9, 0): 1})
	var sim := _sim(state)
	_order(sim, &"f", Vector2i(2, 0), &"march")
	_end(sim)
	assert_eq(state.formations[0].coord, Vector2i(2, 0))
	assert_true(sim.execute(IssueOrderCommand.new(&"x1", Vector2i(5, 0), &"march")))
	# A formation without an order stays; the other side's order has not moved so far.
	assert_eq(state.formations[1].coord, Vector2i(9, 0))
	var events := _end(sim)
	assert_eq(state.formations[1].coord, Vector2i(5, 0))
	assert_eq(_of_type(events, &"formation_moved").size(), 1)


func test_formations_see_earlier_positions() -> void:
	# g (placed second) heads for the hex f vacates only if f moves first.
	var state := _state({Vector2i(0, 1): 0})
	var sim := _sim(state)
	_order(sim, &"f", Vector2i(3, 0), &"march")
	state.formations[1].order = FormationOrder.new(Vector2i(0, 0))
	var events := _end(sim)
	# x1's destination (0, 0) was just freed by f.
	assert_eq(state.formations[1].coord, Vector2i(0, 0))
	assert_eq(_of_type(events, &"formation_order_completed").size(), 2)


# --- invariants ---


func test_gap_run_invariants() -> void:
	var state := Operation.build(&"suwalki_gap", 7)
	var sim := _sim(state)
	_give_far_orders(sim, state)
	for _i in 12:
		var events := _end(sim)
		_check_invariants(state)
		for e in events:
			if e["type"] == &"formation_order_interrupted":
				var reasons: Array[StringName] = [&"destination_occupied", &"no_route", &"blocked"]
				assert_true(reasons.has(e["reason"]))


func _give_far_orders(sim: OperationalSimulation, state: OperationalState) -> void:
	var postures: Array[StringName] = [&"march", &"advance", &"defend"]
	var i := 0
	var used := {}
	for f in state.formations.duplicate():
		i += 1
		var posture := postures[i % 3]
		var c := _far_hex(state, f, used)
		if c != f.coord:
			f.posture = posture
			f.order = FormationOrder.new(c)
	assert_true(sim != null)


func _check_invariants(state: OperationalState) -> void:
	var seen := {}
	for f in state.formations:
		assert_false(seen.has(f.coord), "two formations on %s" % f.coord)
		seen[f.coord] = true
		assert_true(state.grid.has_tile(f.coord))
		assert_true(state.grid.get_terrain(f.coord) != Terrain.Type.WATER)


# --- determinism ---


func _script(state: OperationalState) -> Array[Dictionary]:
	var player0: Array[Formation] = []
	for f in state.formations:
		if f.owner_id == state.current_player:
			player0.append(f)
	var a := player0[0]
	var b := player0[1]
	var c := player0[2]
	var used := {}
	var far_a := _far_hex(state, a, used)
	var far_b := _far_hex(state, b, used)
	var far_c := _far_hex(state, c, used)
	var cmds: Array[OperationalCommand] = [
		IssueOrderCommand.new(a.id, far_a, &"march"),
		IssueOrderCommand.new(b.id, far_b, &"advance"),
		IssueOrderCommand.new(c.id, far_c, &"defend"),
		SetPostureCommand.new(b.id, &"march"),
		EndOperationalTurnCommand.new(),
		EndOperationalTurnCommand.new(),
		CancelOrderCommand.new(c.id),
		IssueOrderCommand.new(&"nobody", Vector2i.ZERO, &"march"),
		EndOperationalTurnCommand.new(),
		EndOperationalTurnCommand.new(),
		EndOperationalTurnCommand.new(),
		EndOperationalTurnCommand.new(),
	]
	var dicts: Array[Dictionary] = []
	for cmd in cmds:
		dicts.append(cmd.to_dict())
	return dicts


## A reachable free hex 6 … 9 away that no earlier call picked (`used` collects the picks).
func _far_hex(state: OperationalState, f: Formation, used: Dictionary) -> Vector2i:
	for c in state.grid.coords():
		var d := Hex.distance(c, f.coord)
		if d < 6 or d > 9 or used.has(c) or state.formation_at(c) != null:
			continue
		if not OperationalRoutes.plan(state, f, c, false).is_empty():
			used[c] = true
			return c
	return f.coord


func _run(state: OperationalState, dicts: Array[Dictionary]) -> Array[Dictionary]:
	var sim := _sim(state)
	var all: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: all.append(e))
	for d in dicts:
		var cmd := OperationalCommandCodec.from_dict(
			JSON.parse_string(JSON.stringify(d)) as Dictionary
		)
		sim.execute(cmd)
	return all


func test_replay_is_identical_and_draws_no_rng() -> void:
	var first := Operation.build(&"suwalki_gap", 7)
	var dicts := _script(first)
	var rng_before := first.rng.state
	var events_a := _run(first, dicts)
	# Execution itself draws nothing; a contact draws one value per battle (TASK-094a), so the
	# state may only be compared on a run without one.
	assert_true(_of_type(events_a, &"battle_pending").is_empty(), "script must not make contact")
	assert_eq(first.rng.state, rng_before)
	var second := Operation.build(&"suwalki_gap", 7)
	var events_b := _run(second, dicts)
	assert_eq(first.snapshot(), second.snapshot())
	assert_eq(str(events_a), str(events_b))
	assert_true(_of_type(events_a, &"formation_moved").size() > 0)
