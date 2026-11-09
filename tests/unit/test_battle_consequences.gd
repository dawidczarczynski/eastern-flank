# gdlint: disable=max-public-methods
extends TestCase
## Consequences of a battle for the operation (TASK-095): losses, retreat, readiness.

const Fixtures := preload("res://tests/fixtures.gd")


## Plains grid, radius 4 around the origin. Player 0 attacks from (0, 0) (formation "att", four
## companies of max 10), player 1 defends on (1, 0) ("def", two companies). `extras` {coord: owner}.
static func _state(extras: Dictionary = {}, radius := 4) -> OperationalState:
	var state := OperationalState.new()
	var grid := HexGrid.new()
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			if Hex.distance(Vector2i(q, r), Vector2i.ZERO) <= radius:
				grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	state.grid = grid
	state.formations.append(_formation(&"att", 0, Vector2i(0, 0), 4))
	state.formations.append(_formation(&"def", 1, Vector2i(1, 0), 2))
	var n := 0
	for coord: Vector2i in extras:
		n += 1
		state.formations.append(_formation(StringName("x%d" % n), extras[coord] as int, coord, 1))
	state.pending_battles.append(_setup(state))
	return state


static func _formation(id: StringName, owner: int, coord: Vector2i, count: int) -> Formation:
	var f := Formation.new()
	f.id = id
	f.owner_id = owner
	f.coord = coord
	f.definition = FormationDefinition.new()
	f.definition.move_points = 8
	for i in count:
		f.companies.append(Formation.Company.new(&"u", 10, "%s/%d" % [id, i + 1]))
	return f


static func _setup(state: OperationalState) -> BattleSetup:
	var setup := BattleSetup.new()
	setup.attacker = 0
	for id: StringName in [&"att", &"def"]:
		for company in state.get_formation(id).companies:
			var planned := BattleSetup.Company.new()
			planned.player = state.get_formation(id).owner_id
			planned.unit_type = company.unit_type
			planned.strength = company.strength
			planned.ref = company.ref
			setup.companies.append(planned)
	return setup


## A result: `ends` strength_end per setup company; winner/kind as given.
static func _result(
	setup: BattleSetup, ends: Array[int], winner: int, kind := BattleResult.PLAYED
) -> BattleResult:
	var result := BattleResult.new()
	result.winner = winner
	result.reason = &"eliminated"
	result.resolution = kind
	for i in setup.companies.size():
		var c := BattleResult.Company.new()
		c.player = setup.companies[i].player
		c.unit_type = setup.companies[i].unit_type
		c.ref = setup.companies[i].ref
		c.strength_start = setup.companies[i].strength
		c.strength_end = ends[i]
		result.companies.append(c)
	result.settle(setup)
	return result


func _resolve(state: OperationalState, result: BattleResult) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var sim := OperationalSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	assert_true(sim.execute(ResolveBattleCommand.new(result)))
	return events


func _of_type(events: Array[Dictionary], type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e["type"] == type:
			out.append(e)
	return out


# --- losses ---


func test_losses_by_company() -> void:
	var state := _state()
	# attacker 4 x 10 -> 7 5 6 10 = 28; defender 20 -> 10 10 (draw, nobody retreats)
	var ends: Array[int] = [7, 5, 6, 10, 10, 10]
	var events := _resolve(state, _result(state.pending_battles[0], ends, -1))
	assert_eq(state.get_formation(&"att").strength(), 28)
	assert_eq(state.get_formation(&"def").strength(), 20)
	var c := _of_type(events, &"battle_consequences")
	assert_eq(c.size(), 1)
	assert_eq(c[0]["attacker_id"], &"att")
	assert_eq(c[0]["defender_id"], &"def")
	assert_eq(c[0]["losses"], [12, 0])
	assert_eq(c[0]["field_holder"], 1)
	assert_eq(c[0]["retreat"], -1)


func test_destroyed_company_and_formation_removed() -> void:
	var state := _state()
	state.get_formation(&"def").order = FormationOrder.new(Vector2i(3, 0))
	var ends: Array[int] = [10, 10, 10, 10, 0, 0]
	var events := _resolve(state, _result(state.pending_battles[0], ends, 0))
	assert_true(state.get_formation(&"def") == null)
	var d := _of_type(events, &"formation_destroyed")
	assert_eq(d.size(), 1)
	assert_eq(d[0]["formation_id"], &"def")
	assert_eq(d[0]["player"], 1)
	assert_eq(d[0]["before"], 20)
	assert_eq(d[0]["after"], 0)
	assert_eq(d[0]["cause"], &"battle")
	assert_eq(_of_type(events, &"formation_retreated").size(), 0)
	var partial := _state()
	var ends2: Array[int] = [10, 0, 10, 10, 10, 10]
	_resolve(partial, _result(partial.pending_battles[0], ends2, -1))
	assert_eq(partial.get_formation(&"att").companies.size(), 3)


func test_played_and_auto_results_give_equal_state() -> void:
	var a := Operation.build(&"suwalki_gap", 1)
	var b := Operation.build(&"suwalki_gap", 1)
	assert_false(Fixtures.theatre_contact(a).is_empty())
	assert_false(Fixtures.theatre_contact(b).is_empty())
	var auto := AutoResolve.resolve(a.pending_battles[0])
	var played := BattleResult.from_dict(auto.to_dict())
	played.resolution = BattleResult.PLAYED
	assert_true(OperationalSimulation.new(a).execute(ResolveBattleCommand.new(auto)))
	assert_true(OperationalSimulation.new(b).execute(ResolveBattleCommand.new(played)))
	assert_eq(a.snapshot(), b.snapshot())


func test_consequences_never_read_the_resolution() -> void:
	var text := FileAccess.get_file_as_string("res://src/core/operational/battle_consequences.gd")
	assert_false(text.contains("resolution"))
	var command := FileAccess.get_file_as_string(
		"res://src/core/operational/resolve_battle_command.gd"
	)
	var applied := command.substr(command.find("func apply"), command.find("func to_dict"))
	assert_false(applied.contains("resolution"))


func test_no_rng_draw() -> void:
	var state := _state()
	var before := state.rng.state
	var ends: Array[int] = [7, 5, 6, 10, 0, 3]
	_resolve(state, _result(state.pending_battles[0], ends, 0))
	assert_eq(state.rng.state, before)


# --- retreat ---


func _loser_retreats(state: OperationalState) -> Array[Dictionary]:
	# player 1 (defender) loses but keeps a company
	var ends: Array[int] = [10, 10, 10, 10, 2, 0]
	return _resolve(state, _result(state.pending_battles[0], ends, 0))


func test_retreat_moves_one_hex_away_and_drops_order() -> void:
	var state := _state()
	state.get_formation(&"def").order = FormationOrder.new(Vector2i(0, 3))
	var events := _loser_retreats(state)
	var r := _of_type(events, &"formation_retreated")
	assert_eq(r.size(), 1)
	assert_eq(r[0]["formation_id"], &"def")
	assert_eq(r[0]["from"], Vector2i(1, 0))
	assert_false(r[0]["blocked"])
	var to: Vector2i = r[0]["to"]
	assert_eq(Hex.distance(to, Vector2i(1, 0)), 1)
	assert_eq(Hex.distance(to, Vector2i(0, 0)), 2, "farthest from the enemy")
	assert_eq(state.get_formation(&"def").coord, to)
	assert_true(state.get_formation(&"def").order == null)
	var i := _of_type(events, &"formation_order_interrupted")
	assert_eq(i.size(), 1)
	assert_eq(i[0]["reason"], &"retreated")


func test_retreat_row_grid_goes_along_the_row() -> void:
	var state := OperationalState.new()
	var grid := HexGrid.new()
	for q in range(0, 5):
		grid.set_terrain(Vector2i(q, 0), Terrain.Type.PLAINS)
	state.grid = grid
	state.formations.append(_formation(&"att", 0, Vector2i(1, 0), 4))
	state.formations.append(_formation(&"def", 1, Vector2i(2, 0), 2))
	state.pending_battles.append(_setup(state))
	var events := _loser_retreats(state)
	assert_eq(_of_type(events, &"formation_retreated")[0]["to"], Vector2i(3, 0))


func test_retreat_prefers_hex_outside_zone_of_control() -> void:
	# Enemy (player 0) helper x1 next to the otherwise farthest hex (2, -1)... build explicitly:
	var state := _state({Vector2i(3, -1): 0})
	var events := _loser_retreats(state)
	var to: Vector2i = _of_type(events, &"formation_retreated")[0]["to"]
	var zone := Hex.neighbors(Vector2i(3, -1)) + Hex.neighbors(Vector2i(0, 0))
	assert_false(zone.has(to), "retreat leaves the zones of control when it can")


func test_retreat_blocked_when_surrounded() -> void:
	var extras := {}
	for n in Hex.neighbors(Vector2i(1, 0)):
		if n != Vector2i(0, 0):
			extras[n] = 0
	var state := _state(extras)
	var events := _loser_retreats(state)
	var r := _of_type(events, &"formation_retreated")
	assert_eq(r.size(), 1)
	assert_true(r[0]["blocked"])
	assert_eq(r[0]["to"], r[0]["from"])
	assert_eq(state.get_formation(&"def").coord, Vector2i(1, 0))


func test_retreat_in_a_corner() -> void:
	var state := OperationalState.new()
	var grid := HexGrid.new()
	for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		grid.set_terrain(c, Terrain.Type.PLAINS)
	state.grid = grid
	state.formations.append(_formation(&"att", 0, Vector2i(1, 0), 4))
	state.formations.append(_formation(&"def", 1, Vector2i(0, 0), 2))
	state.pending_battles.append(_setup(state))
	var events := _loser_retreats(state)
	assert_eq(_of_type(events, &"formation_retreated")[0]["to"], Vector2i(0, 1))


func test_draw_nobody_retreats_winner_stays() -> void:
	var state := _state()
	var ends: Array[int] = [10, 10, 10, 10, 2, 0]
	var events := _resolve(state, _result(state.pending_battles[0], ends, 0))
	assert_eq(state.get_formation(&"att").coord, Vector2i(0, 0), "winner does not advance")
	assert_eq(_of_type(events, &"battle_consequences")[0]["retreat"], 1)


# --- readiness ---


func test_readiness_data() -> void:
	var s := AftermathSettings.shipped()
	assert_eq(s.problem(), "")
	assert_eq(s.readiness_loss_attacker, 15)
	assert_eq(s.readiness_loss_defender, 10)
	assert_eq(s.readiness_recovery, 10)
	assert_eq(s.readiness_floor, 40)
	var bad := AftermathSettings.new()
	bad.readiness_floor = 0
	assert_true(bad.problem() != "")


func test_battle_costs_readiness() -> void:
	var state := _state()
	var ends: Array[int] = [10, 10, 10, 10, 10, 10]
	_resolve(state, _result(state.pending_battles[0], ends, -1))
	assert_eq(state.get_formation(&"att").readiness, 85)
	assert_eq(state.get_formation(&"def").readiness, 90)


func test_budget_scales_with_readiness() -> void:
	var f := _formation(&"f", 0, Vector2i.ZERO, 1)
	var march := OperationalPosture.find(&"march")
	assert_eq(OperationalOrders.budget(f, march), 8)
	f.readiness = 85
	assert_eq(OperationalOrders.budget(f, march), 6)
	f.readiness = 20
	assert_eq(OperationalOrders.budget(f, march), 3)
	f.definition.move_points = 1
	assert_eq(OperationalOrders.budget(f, march), 1, "at least 1")


func test_recovery_after_quiet_turn_only() -> void:
	var state := _state()
	var f := state.get_formation(&"att")
	var g := state.get_formation(&"def")
	state.pending_battles.clear()
	f.readiness = 70
	g.readiness = 70
	g.fought = true
	var sim := OperationalSimulation.new(state)
	assert_true(sim.execute(EndOperationalTurnCommand.new()))  # player 1 to move
	assert_eq(g.readiness, 70, "fought: no recovery")
	assert_false(g.fought)
	assert_eq(f.readiness, 70)
	assert_true(sim.execute(EndOperationalTurnCommand.new()))  # player 0 again
	assert_eq(f.readiness, 80)
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(g.readiness, 80)


func test_recovery_capped_at_100() -> void:
	var state := _state()
	state.pending_battles.clear()
	state.get_formation(&"def").readiness = 95
	var sim := OperationalSimulation.new(state)
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(state.get_formation(&"def").readiness, 100)


func test_snapshot_has_readiness_and_fought() -> void:
	var state := _state()
	var entry: Dictionary = state.snapshot()["formations"][0]
	assert_eq(entry["readiness"], 100)
	assert_eq(entry["fought"], false)


func test_forecast_uses_readiness() -> void:
	var state := _state()
	state.pending_battles.clear()
	var f := state.get_formation(&"att")
	f.readiness = 40
	var events: Array[Dictionary] = []
	var sim := OperationalSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: events.append(e))
	state.formations.erase(state.get_formation(&"def"))
	assert_true(sim.execute(IssueOrderCommand.new(&"att", Vector2i(4, 0), &"march")))
	# budget 8 * 40 % = 3 points: one hex per... plains cost -> forecast has more than 1 stop
	var fast := _state()
	fast.pending_battles.clear()
	fast.formations.erase(fast.get_formation(&"def"))
	var events2: Array[Dictionary] = []
	var sim2 := OperationalSimulation.new(fast)
	sim2.event_emitted.connect(func(e: Dictionary) -> void: events2.append(e))
	assert_true(sim2.execute(IssueOrderCommand.new(&"att", Vector2i(4, 0), &"march")))
	var slow_stops: Array = _of_type(events, &"formation_order_issued")[0]["forecast"]
	var fast_stops: Array = _of_type(events2, &"formation_order_issued")[0]["forecast"]
	assert_true(slow_stops.size() > fast_stops.size())
	assert_eq(slow_stops.back(), Vector2i(4, 0))
