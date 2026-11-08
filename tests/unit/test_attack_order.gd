extends TestCase
## Attack order on an enemy formation (follow-up of TASK-094a): the Advance posture may target an
## enemy hex; the formation halts next to it with `contact`, which starts the battle.

var _events: Array[Dictionary] = []


## Plains q 0…9, r 0…1; own "f" on (0, 0), enemy "e" (player 1) at `enemy_at`.
static func _state(enemy_at: Vector2i) -> OperationalState:
	var state := OperationalState.new()
	var grid := HexGrid.new()
	for q in range(0, 10):
		for r in range(0, 2):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	state.grid = grid
	state.formations.append(_formation(&"f", 0, Vector2i.ZERO))
	state.formations.append(_formation(&"e", 1, enemy_at))
	return state


static func _formation(id: StringName, owner: int, coord: Vector2i) -> Formation:
	var f := Formation.new()
	f.id = id
	f.owner_id = owner
	f.coord = coord
	f.definition = FormationDefinition.new()
	return f


func _sim(state: OperationalState) -> OperationalSimulation:
	var sim := OperationalSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: _events.append(e))
	return sim


func _of_type(type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _events:
		if e["type"] == type:
			out.append(e)
	return out


func test_validate_enemy_destination_by_posture() -> void:
	var state := _state(Vector2i(6, 0))
	var dest := Vector2i(6, 0)
	assert_eq(IssueOrderCommand.new(&"f", dest, &"advance").validate(state), "")
	assert_eq(IssueOrderCommand.new(&"f", dest, &"march").validate(state), "enemy_destination")
	assert_eq(IssueOrderCommand.new(&"f", dest, &"defend").validate(state), "enemy_destination")
	state.formations.append(_formation(&"mate", 0, Vector2i(3, 1)))
	assert_eq(IssueOrderCommand.new(&"f", Vector2i(3, 1), &"advance").validate(state), "occupied")


func test_plan_ends_on_enemy_hex_and_walk_halts_before_it() -> void:
	var state := _state(Vector2i(3, 0))
	var f := state.get_formation(&"f")
	var route := OperationalRoutes.plan(state, f, Vector2i(3, 0), false)
	assert_eq(route[route.size() - 1], Vector2i(3, 0))
	assert_true(OperationalRoutes.plan(state, f, Vector2i(3, 0), true).is_empty())
	var walk := OperationalRoutes.walk(state, f, f.coord, route, 99)
	assert_eq(walk["stop"], OperationalRoutes.STOP_CONTACT)
	assert_eq(walk["end"], Vector2i(2, 0))
	var forecast := OperationalRoutes.forecast(state, f, Vector2i(3, 0), 99, false)
	assert_eq(forecast[forecast.size() - 1], Vector2i(2, 0))


func test_attack_from_distance_starts_battle_and_keeps_order() -> void:
	var state := _state(Vector2i(3, 0))
	var sim := _sim(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(3, 0), &"advance")))
	_events.clear()
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	var f := state.get_formation(&"f")
	assert_true(f.coord != Vector2i(3, 0))
	assert_eq(_of_type(&"formation_halted").size(), 1)
	assert_eq(_of_type(&"battle_pending").size(), 1)
	assert_eq(state.pending_battles.size(), 1)
	assert_true(f.order != null)
	assert_eq(state.get_formation(&"e").coord, Vector2i(3, 0))


func test_attack_when_already_adjacent_does_not_move() -> void:
	var state := _state(Vector2i(1, 0))
	var sim := _sim(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(1, 0), &"advance")))
	_events.clear()
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(state.get_formation(&"f").coord, Vector2i.ZERO)
	assert_eq(_of_type(&"formation_moved").size(), 0)
	assert_eq(_of_type(&"formation_order_interrupted").size(), 0)
	var halted := _of_type(&"formation_halted")
	assert_eq(halted.size(), 1)
	assert_eq(halted[0]["reason"], &"contact")
	assert_eq(_of_type(&"battle_pending").size(), 1)


func test_target_gone_arrives_on_the_empty_hex() -> void:
	var state := _state(Vector2i(2, 0))
	var sim := _sim(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(2, 0), &"advance")))
	state.get_formation(&"e").coord = Vector2i(9, 1)
	_events.clear()
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(state.get_formation(&"f").coord, Vector2i(2, 0))
	assert_eq(_of_type(&"formation_order_completed").size(), 1)
	assert_eq(_of_type(&"battle_pending").size(), 0)


func test_target_replaced_by_own_formation_interrupts() -> void:
	var state := _state(Vector2i(4, 0))
	var sim := _sim(state)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(4, 0), &"advance")))
	state.get_formation(&"e").coord = Vector2i(9, 1)
	state.formations.append(_formation(&"mate", 0, Vector2i(4, 0)))
	_events.clear()
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	var interrupted := _of_type(&"formation_order_interrupted")
	assert_eq(interrupted.size(), 1)
	assert_eq(interrupted[0]["reason"], &"destination_occupied")
