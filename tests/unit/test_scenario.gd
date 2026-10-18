extends TestCase


func test_default_battle_has_four_units_per_player() -> void:
	var state := Scenario.default_battle(12345)
	assert_eq(state.units.size(), 8)
	assert_eq(state.units_of(0).size(), 4)
	assert_eq(state.units_of(1).size(), 4)


func test_default_battle_has_one_rocket_artillery_per_player() -> void:
	var state := Scenario.default_battle(12345)
	for player in 2:
		var artillery := 0
		for unit in state.units_of(player):
			if unit.definition.id == &"rocket_artillery":
				artillery += 1
		assert_eq(artillery, 1)


func test_units_on_plains_and_distinct_tiles() -> void:
	var state := Scenario.default_battle(7)
	var seen: Dictionary = {}
	for unit: Unit in state.units.values():
		assert_eq(state.grid.get_terrain(unit.coord), Terrain.Type.PLAINS)
		assert_false(seen.has(unit.coord))
		seen[unit.coord] = true


func test_unit_ids_are_one_to_eight_in_spawn_order() -> void:
	var state := Scenario.default_battle(12345)
	for id in range(1, 9):
		assert_true(state.get_unit(id) != null)
	assert_eq(state.get_unit(4).definition.id, &"rocket_artillery")
	assert_eq(state.get_unit(4).coord, MapGenerator.offset_to_axial(0, 5))
	assert_eq(state.get_unit(8).owner_id, 1)


func test_same_seed_gives_identical_battle() -> void:
	var a := Scenario.default_battle(12345)
	var b := Scenario.default_battle(12345)
	for c in a.grid.coords():
		assert_eq(a.grid.get_terrain(c), b.grid.get_terrain(c))
	for id in a.units:
		var ua: Unit = a.units[id]
		var ub: Unit = b.units[id]
		assert_eq(ua.coord, ub.coord)
		assert_eq(ua.definition.id, ub.definition.id)
		assert_eq(ua.owner_id, ub.owner_id)


func test_terrain_matches_map_generator_apart_from_spawn_tiles() -> void:
	var state := Scenario.default_battle(12345)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var expected := MapGenerator.generate(12, 10, rng)
	var spawn_tiles: Dictionary = {}
	for unit: Unit in state.units.values():
		spawn_tiles[unit.coord] = true
	assert_eq(state.grid.coords().size(), expected.coords().size())
	for c in expected.coords():
		if not spawn_tiles.has(c):
			assert_eq(state.grid.get_terrain(c), expected.get_terrain(c))
