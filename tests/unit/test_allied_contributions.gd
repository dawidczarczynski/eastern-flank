extends TestCase
## Allied contributions on joining the war (TASK-118): CountryRules.set_stance + Reinforcements.

const Data := preload("res://tests/unit/test_contribution_data.gd")


func _state(lithuania_side := 0) -> OperationalState:
	return Data.build(Data.definition(lithuania_side))


func _enemy(state: OperationalState, coord: Vector2i, id: StringName = &"enemy") -> void:
	var f := Formation.from_placement(Data.placement(id, 1, coord))
	f.owner_id = 1 - state.get_country(&"lithuania").leaning
	state.formations.append(f)


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> Variant: return e["type"])


func _join(state: OperationalState, side := 0) -> Array[Dictionary]:
	return CountryRules.set_stance(state, &"lithuania", &"belligerent", side, &"test", -1)


func test_joining_places_the_contribution() -> void:
	var state := _state()
	var events := _join(state)
	assert_eq(
		_types(events),
		[&"country_stance_changed", &"formation_joined", &"formation_joined"] as Array
	)
	assert_eq(state.formations.size(), 2)
	assert_eq(state.formations[0].id, &"a")
	assert_eq(state.formations[0].coord, Vector2i(4, 0))
	assert_eq(state.formations[1].coord, Vector2i(5, 0))
	for f in state.formations:
		assert_eq(f.owner_id, 0)
		assert_eq(f.strength(), f.max_strength())
		assert_eq(f.posture, &"defend")
		assert_true(f.order == null)
		assert_eq(f.companies[0].ref, "%s/1" % f.id)
	var joined := events[1]
	assert_eq(joined["formation_id"], &"a")
	assert_eq(joined["player"], 0)
	assert_eq(joined["country"], &"lithuania")
	assert_eq(joined["coord"], Vector2i(4, 0))
	assert_eq(joined["source"], &"contribution")
	assert_true(state.get_country(&"lithuania").contributed)


func test_side_one_mirror() -> void:
	var state := _state(1)
	var events := _join(state, 1)
	assert_eq(state.formations.size(), 2)
	for f in state.formations:
		assert_eq(f.owner_id, 1)
	assert_eq(events[1]["player"], 1)


func test_other_side_brings_nothing() -> void:
	var op := Data.definition(0)
	op.countries[1].stance = &"neutral"
	op.countries[1].side = -1
	var state := Data.build(op)
	var events := _join(state, 1)
	assert_eq(_types(events), [&"country_stance_changed"] as Array)
	assert_eq(state.formations.size(), 0)
	assert_false(state.get_country(&"lithuania").contributed)


func test_never_twice() -> void:
	var state := _state()
	_join(state)
	var again := _join(state)
	assert_eq(again.size(), 0, "belligerent is final")
	assert_eq(state.formations.size(), 2)
	assert_true(state.get_country(&"lithuania").contributed)


func test_blocked_hex_falls_back_to_the_nearest_free_one() -> void:
	var state := _state()
	_enemy(state, Vector2i(4, 0))
	var events := _join(state)
	# Ring around (4, 0) from Hex.DIRECTIONS[0]: (5, 0) is wanted by B, (5, -1) and (4, -1) are off
	# the map, (3, 0) is the next one.
	assert_eq(events[1]["coord"], Vector2i(3, 0))
	assert_eq(events[2]["coord"], Vector2i(5, 0))
	assert_eq(state.formation_at(Vector2i(4, 0)).id, &"enemy")


func test_no_free_hex_fails() -> void:
	# Poland's hexes next to Lithuania stay free: the fallback must not use them.
	var state := _state()
	for coord in state.country_map:
		if state.country_map[coord] == &"lithuania" and state.grid.move_cost(coord) > 0:
			_enemy(state, coord, StringName("e%d_%d" % [coord.x, coord.y]))
	var before := state.formations.size()
	var events := _join(state)
	assert_eq(events.size(), 3)
	assert_eq(events[1]["type"], &"formation_join_failed")
	assert_eq(events[1]["formation_id"], &"a")
	assert_eq(events[1]["country"], &"lithuania")
	assert_eq(events[1]["reason"], &"no_free_hex")
	assert_eq(state.formations.size(), before)
	assert_true(state.get_country(&"lithuania").contributed, "lost, not retried")


func test_require_open_keeps_closed_hexes_unplaced() -> void:
	var state := _state()
	# Lithuania is neutral for player 1 and the placement is for player 1: closed hexes.
	var list: Array[FormationPlacement] = [Data.placement(&"x", 1, Vector2i(4, 0))]
	var result := Reinforcements.place(state, list, 1, &"pkg", true)
	assert_eq(result["events"].size(), 0)
	assert_eq(result["unplaced"].size(), 1)
	assert_eq(state.formations.size(), 0)
	var lost := Reinforcements.place(state, list, 1, &"pkg", false)
	assert_eq(lost["events"][0]["type"], &"formation_joined", "without require_open it is placed")
	assert_eq(lost["events"][0]["source"], &"pkg")


func test_contributed_formations_are_full_formations() -> void:
	var state := _state()
	_join(state)
	var sim := OperationalSimulation.new(state)
	state.current_player = 0
	assert_true(sim.execute(IssueOrderCommand.new(&"a", Vector2i(3, 0), &"march")))
	assert_true(state.get_formation(&"a").order != null)
	var snap := state.snapshot()
	assert_eq(snap["formations"].size(), 2)
	assert_eq(snap["countries"][0]["contributed"], true)


func test_deterministic_and_no_rng() -> void:
	var a := _state()
	var b := _state()
	var rng_before := a.rng.state
	var ea := _join(a)
	var eb := _join(b)
	assert_eq(a.snapshot(), b.snapshot())
	assert_eq(ea, eb)
	assert_eq(a.rng.state, rng_before)
