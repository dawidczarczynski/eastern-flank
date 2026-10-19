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


func test_default_battle_assigns_poland_and_russia() -> void:
	var state := Scenario.default_battle(12345)
	assert_eq(state.player_factions, [&"poland", &"russia"] as Array[StringName])
	assert_eq(state.faction_of(0).id, &"poland")
	assert_eq(state.faction_of(1).id, &"russia")


func test_default_battle_with_swapped_factions() -> void:
	var state := Scenario.default_battle(12345, [&"russia", &"poland"])
	assert_eq(state.faction_of(0).id, &"russia")
	assert_eq(state.faction_of(1).id, &"poland")
	assert_eq(state.units.size(), 8)


func test_poland_fields_the_abrams_and_russia_the_generic_tank() -> void:
	var state := Scenario.default_battle(12345)
	assert_eq(state.get_unit(2).definition.id, &"m1a2_sepv3")
	assert_eq(state.get_unit(2).coord, MapGenerator.offset_to_axial(1, 5))
	assert_eq(state.get_unit(6).definition.id, &"cavalry")
	assert_eq(state.get_unit(6).coord, MapGenerator.offset_to_axial(10, 4))


## Factions pick the units (their default_force); the map, spawn tiles and unit ids stay the same.
func test_swapped_factions_swap_only_the_units() -> void:
	var a := Scenario.default_battle(12345)
	var b := Scenario.default_battle(12345, [&"russia", &"poland"])
	for c in a.grid.coords():
		assert_eq(a.grid.get_terrain(c), b.grid.get_terrain(c))
	for id in a.units:
		assert_eq((a.units[id] as Unit).coord, (b.units[id] as Unit).coord, str(id))
	assert_eq(b.get_unit(2).definition.id, &"cavalry")
	assert_eq(b.get_unit(6).definition.id, &"m1a2_sepv3")


func test_front_and_back_slots_follow_attack_range() -> void:
	var state := Scenario.default_battle(12345)
	var expected := {
		1: Vector2i(1, 3),
		2: Vector2i(1, 5),
		3: Vector2i(1, 7),
		4: Vector2i(0, 5),
		5: Vector2i(10, 2),
		6: Vector2i(10, 4),
		7: Vector2i(10, 6),
		8: Vector2i(11, 4),
	}
	for id: int in expected:
		var slot: Vector2i = expected[id]
		assert_eq(state.get_unit(id).coord, MapGenerator.offset_to_axial(slot.x, slot.y), str(id))


func test_every_spawned_unit_is_in_its_owners_roster() -> void:
	var state := Scenario.default_battle(12345)
	for unit: Unit in state.units.values():
		assert_true(state.faction_of(unit.owner_id).has_unit(unit.definition), str(unit.id))


func test_player_with_unknown_faction_gets_no_units() -> void:
	# Expected engine output: push_error about the unknown faction / skipped spawns.
	var state := Scenario.default_battle(12345, [&"poland", &"atlantis"])
	assert_eq(state.units_of(0).size(), 4)
	assert_eq(state.units_of(1).size(), 0)


func test_can_spawn_checks_the_roster() -> void:
	var state := GameState.new(HexGrid.new(), 2, 1)
	var infantry: UnitDefinition = load("res://data/units/infantry.tres")
	assert_true(Scenario.can_spawn(state, 0, infantry))
	assert_false(Scenario.can_spawn(state, 2, infantry), "no such player")
	var other := UnitDefinition.new()
	other.id = &"not_in_any_roster"
	assert_false(Scenario.can_spawn(state, 1, other))
