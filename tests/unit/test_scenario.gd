extends TestCase


func test_default_battle_has_four_polish_and_five_russian_units() -> void:
	var state := Scenario.default_battle(12345)
	assert_eq(state.units.size(), 9)
	assert_eq(state.units_of(0).size(), 4)
	assert_eq(state.units_of(1).size(), 5)


func test_default_battle_has_one_rocket_artillery_per_player() -> void:
	var state := Scenario.default_battle(12345)
	for player in 2:
		var artillery := 0
		for unit in state.units_of(player):
			if unit.definition.unit_class == &"mlrs":
				artillery += 1
		assert_eq(artillery, 1)


func test_units_on_plains_and_distinct_tiles() -> void:
	var state := Scenario.default_battle(7)
	var seen: Dictionary = {}
	for unit: Unit in state.units.values():
		assert_eq(state.grid.get_terrain(unit.coord), Terrain.Type.PLAINS)
		assert_false(seen.has(unit.coord))
		seen[unit.coord] = true


func test_unit_ids_are_one_to_nine_in_spawn_order() -> void:
	var state := Scenario.default_battle(12345)
	for id in range(1, 10):
		assert_true(state.get_unit(id) != null)
	assert_eq(state.get_unit(4).definition.id, &"homar_k")
	assert_eq(state.get_unit(4).coord, MapGenerator.offset_to_axial(0, 5))
	assert_eq(state.get_unit(5).owner_id, 1)
	assert_eq(state.get_unit(9).owner_id, 1)


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
	for row in Scenario.RIVER_COLUMNS.size():
		spawn_tiles[MapGenerator.offset_to_axial(Scenario.RIVER_COLUMNS[row], row)] = true
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
	assert_eq(state.units_of(0).size(), 5)
	assert_eq(state.units_of(1).size(), 4)


## [unit id, owner, definition id, offset column, offset row] of `state`'s units.
func _layout(state: GameState) -> Array:
	var result := []
	for id in range(1, state.units.size() + 1):
		var unit := state.get_unit(id)
		var offset := MapGenerator.axial_to_offset(unit.coord)
		result.append([id, unit.owner_id, unit.definition.id, offset.x, offset.y])
	return result


func test_default_force_fills_the_slots_in_order() -> void:
	var state := Scenario.default_battle(1)
	var expected := [
		[1, 0, &"pl_mech_infantry", 1, 3],
		[2, 0, &"m1a2_sepv3", 1, 5],
		[3, 0, &"pl_mech_infantry", 1, 7],
		[4, 0, &"homar_k", 0, 5],
		[5, 1, &"ru_motor_rifle", 10, 2],
		[6, 1, &"t72b3", 10, 4],
		[7, 1, &"ru_motor_rifle", 10, 6],
		[8, 1, &"t72b3", 10, 8],
		[9, 1, &"bm27_uragan", 11, 4],
	]
	assert_eq(_layout(state), expected)
	for unit: Unit in state.units.values():
		assert_eq(state.grid.get_terrain(unit.coord), Terrain.Type.PLAINS, str(unit.id))


func test_swapped_factions_take_the_other_players_slots() -> void:
	var state := Scenario.default_battle(1, [&"russia", &"poland"])
	var expected := [
		[1, 0, &"ru_motor_rifle", 1, 3],
		[2, 0, &"t72b3", 1, 5],
		[3, 0, &"ru_motor_rifle", 1, 7],
		[4, 0, &"t72b3", 1, 1],
		[5, 0, &"bm27_uragan", 0, 5],
		[6, 1, &"pl_mech_infantry", 10, 2],
		[7, 1, &"m1a2_sepv3", 10, 4],
		[8, 1, &"pl_mech_infantry", 10, 6],
		[9, 1, &"homar_k", 11, 4],
	]
	assert_eq(_layout(state), expected)
	for unit: Unit in state.units.values():
		assert_eq(state.grid.get_terrain(unit.coord), Terrain.Type.PLAINS, str(unit.id))


## Factions pick the units; the map stays the same.
func test_swapped_factions_keep_the_map_apart_from_spawn_tiles() -> void:
	var a := Scenario.default_battle(12345)
	var b := Scenario.default_battle(12345, [&"russia", &"poland"])
	var spawn_tiles := {}
	for state in [a, b]:
		for unit: Unit in (state as GameState).units.values():
			spawn_tiles[unit.coord] = true
	for c in a.grid.coords():
		if not spawn_tiles.has(c):
			assert_eq(a.grid.get_terrain(c), b.grid.get_terrain(c))


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
	var squad: UnitDefinition = load("res://data/units/pl_mech_infantry.tres")
	assert_true(Scenario.can_spawn(state, 0, squad))
	assert_false(Scenario.can_spawn(state, 1, squad), "Russia does not field the Polish squad")
	assert_false(Scenario.can_spawn(state, 2, squad), "no such player")
	var other := UnitDefinition.new()
	other.id = &"not_in_any_roster"
	assert_false(Scenario.can_spawn(state, 1, other))


func test_force_larger_than_the_slots_skips_the_extra_units() -> void:
	# Expected engine output: push_error "no free slot" for the 6th front unit.
	var poland := FactionRegistry.get_faction(&"poland")
	var saved := poland.default_force.duplicate()
	var squad := poland.find_unit(&"pl_mech_infantry")
	var force: Array[UnitDefinition] = []
	for i in 6:
		force.append(squad)
	poland.default_force = force
	var state := Scenario.default_battle(1)
	poland.default_force = saved
	assert_eq(state.units_of(0).size(), 5)
	var rows: Array[int] = []
	for unit in state.units_of(0):
		rows.append(MapGenerator.axial_to_offset(unit.coord).y)
	assert_eq(rows, [3, 5, 7, 1, 9] as Array[int])


func test_river_runs_north_to_south_with_fords() -> void:
	var state := Scenario.default_battle(12345)
	assert_eq(Scenario.RIVER_COLUMNS.size(), Scenario.MAP_HEIGHT)
	for row in Scenario.MAP_HEIGHT:
		var c := MapGenerator.offset_to_axial(Scenario.RIVER_COLUMNS[row], row)
		var expected := Terrain.Type.PLAINS if row in Scenario.RIVER_FORDS else Terrain.Type.WATER
		assert_eq(state.grid.get_terrain(c), expected, "river row %d" % row)


func test_river_tiles_are_connected() -> void:
	for row in range(1, Scenario.MAP_HEIGHT):
		var a := MapGenerator.offset_to_axial(Scenario.RIVER_COLUMNS[row - 1], row - 1)
		var b := MapGenerator.offset_to_axial(Scenario.RIVER_COLUMNS[row], row)
		assert_eq(Hex.distance(a, b), 1, "river rows %d-%d not adjacent" % [row - 1, row])


func test_armies_can_reach_each_other_across_the_river() -> void:
	for seed_value in [12345, 7]:
		var state := Scenario.default_battle(seed_value)
		var west := state.get_unit(1).coord
		var east := state.get_unit(5).coord
		assert_false(state.grid.path_to(west, east, 1000).is_empty(), "seed %d" % seed_value)


func test_default_battle_has_an_operation_name() -> void:
	assert_eq(Scenario.default_battle(12345).operation_name, "Iron Shore")


func test_replayed_match_keeps_the_operation_name() -> void:
	var record := MatchRecord.new()
	record.seed = 99
	var result := Replay.run(record)
	assert_eq(result["simulation"].state.operation_name, "Iron Shore")
