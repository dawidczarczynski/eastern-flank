extends TestCase
## The Suwalki battle (TASK-087): the default forces on the real-terrain map data/maps/suwalki.tres
## (`tools/run.sh --scenario=suwalki_battle`).

static var _state: GameState


func before_all() -> void:
	_state = Scenario.suwalki_battle(12345)


func after_all() -> void:
	_state = null


func test_battle_is_on_the_imported_map() -> void:
	var setup := Scenario.suwalki_battle_setup(12345)
	assert_eq(setup.map_id, Scenario.SUWALKI_MAP_ID)
	var map := ImportedMap.find(Scenario.SUWALKI_MAP_ID)
	assert_eq(_state.grid.coords().size(), map.width * map.height)
	assert_true(_state.grid.authored_elevation)
	assert_eq(_state.operation_name, Scenario.SUWALKI_OPERATION_NAME)


func test_the_map_is_the_human_s_tactical_scale() -> void:
	var map := ImportedMap.find(Scenario.SUWALKI_MAP_ID)
	assert_eq([map.width, map.height, map.hex_spacing_m], [30, 24, 250.0])
	assert_eq(map.crs, "EPSG:32634", "UTM 34N")
	assert_eq(map.problem(), "")


func _open_ground(t: Terrain.Type) -> bool:
	return t == Terrain.Type.PLAINS or t == Terrain.Type.FIELDS


func test_default_forces_on_distinct_plains_tiles_in_their_halves() -> void:
	assert_eq(_state.units_of(0).size(), 4)
	assert_eq(_state.units_of(1).size(), 5)
	var map := ImportedMap.find(Scenario.SUWALKI_MAP_ID)
	var seen := {}
	for unit: Unit in _state.units.values():
		assert_true(_open_ground(_state.grid.get_terrain(unit.coord)), str(unit.coord))
		assert_false(seen.has(unit.coord))
		seen[unit.coord] = true
		var col := MapGenerator.axial_to_offset(unit.coord).x
		if unit.owner_id == 0:
			assert_true(col < map.width / 2.0, "player 0 in the west: %s" % unit.coord)
		else:
			assert_true(col >= map.width / 2.0, "player 1 in the east: %s" % unit.coord)


func test_spawn_tiles_keep_their_real_terrain_and_elevation() -> void:
	var grid := ImportedMap.find(Scenario.SUWALKI_MAP_ID).to_grid()
	for unit: Unit in _state.units.values():
		assert_eq(grid.get_terrain(unit.coord), _state.grid.get_terrain(unit.coord), "real terrain")
		assert_true(_open_ground(grid.get_terrain(unit.coord)), "spawned on plains or fields")
		assert_eq(_state.grid.elevation(unit.coord), grid.elevation(unit.coord))


func test_armies_can_reach_each_other() -> void:
	var west := _state.units_of(0)[0].coord
	var east := _state.units_of(1)[0].coord
	assert_false(_state.grid.path_to(west, east, 1000).is_empty())


func test_same_seed_gives_the_same_battle() -> void:
	assert_eq(Scenario.suwalki_battle(12345).snapshot(), _state.snapshot())


func test_build_by_name() -> void:
	var built := Scenario.build("suwalki_battle", 12345, FactionRegistry.DEFAULT_IDS)
	assert_eq(built.snapshot(), _state.snapshot())


func test_setup_round_trips_through_json() -> void:
	var setup := Scenario.suwalki_battle_setup(12345)
	var copy := BattleSetup.from_dict(JSON.parse_string(JSON.stringify(setup.to_dict())))
	assert_eq(Scenario.from_setup(copy).snapshot(), _state.snapshot())


func test_unknown_map_id_is_rejected() -> void:
	var setup := Scenario.suwalki_battle_setup(12345)
	setup.map_id = &"atlantis"
	assert_true(Scenario.from_setup(setup) == null)


func test_maps_are_credited() -> void:
	var credits := FileAccess.get_file_as_string("res://data/maps/CREDITS")
	assert_true(credits.contains("OpenStreetMap"), "OSM attribution")
	assert_true(credits.contains("ODbL"), "OSM licence")
	assert_true(credits.contains("Copernicus"), "DEM attribution")
	for file in DirAccess.get_files_at("res://data/maps"):
		if file.ends_with(".tres"):
			var map := load("res://data/maps/" + file) as ImportedMap
			assert_true(map != null, file)
			assert_true(map.sources.contains("OpenStreetMap"), file)
			assert_true(map.sources.contains("Copernicus"), file)
			assert_true(credits.contains(file), "%s listed in CREDITS" % file)
