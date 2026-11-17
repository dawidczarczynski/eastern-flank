extends TestCase
## ContactRules.force_contact (debug tool, F10 with --debug): the player's formation nearest to
## an enemy is placed next to it and the battle starts at once.


func _state() -> OperationalState:
	var state := OperationalState.new()
	var grid := HexGrid.new()
	for q in range(0, 10):
		for r in range(0, 2):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	state.grid = grid
	state.operation_name = "OP_TEST"
	state.formations.append(_formation(&"far", 0, Vector2i(0, 0), 2))
	state.formations.append(_formation(&"near", 0, Vector2i(3, 0), 2))
	state.formations.append(_formation(&"e", 1, Vector2i(8, 1), 1))
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
	return f


func test_nearest_formation_is_placed_next_to_the_enemy_and_a_battle_is_pending() -> void:
	var state := _state()
	var events := ContactRules.force_contact(state, 0)
	var near := state.get_formation(&"near")
	assert_eq(Hex.distance(near.coord, Vector2i(8, 1)), 1)
	assert_eq(state.pending_battles.size(), 1)
	assert_eq(state.pending_battles[0].attacker, 0)
	var types: Array[StringName] = []
	for e in events:
		types.append(e["type"])
	assert_true(types.has(&"formation_moved") and types.has(&"battle_pending"))


func test_nothing_happens_without_an_enemy_or_a_free_hex() -> void:
	var state := _state()
	state.formations.remove_at(2)
	assert_eq(ContactRules.force_contact(state, 0).size(), 0)
	assert_eq(state.pending_battles.size(), 0)


func test_works_across_a_closed_border() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	assert_true(ContactRules.force_contact(state, 0).size() > 0)
	assert_eq(state.pending_battles.size(), 1)
