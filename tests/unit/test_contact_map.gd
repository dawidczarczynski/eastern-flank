extends TestCase
## The tactical map of a contact battle (TASK-094b) on a small hand-made tactical layer:
## ContactMap region, cut, deployment and objectives, TacticalLayer.region_grid.

const Fixtures := preload("res://tests/fixtures.gd")
## Hand-made layer: COLS x ROWS tactical hexes of 250 m, tile (0, 0) at E 0 / N 0.
const COLS := 60
const ROWS := 44
## The theatre: 1 km hexes, hex (0, 0) at E 7600 / N -5000 (layer tile (30, 23)).
const THEATRE_E := 7600.0
const THEATRE_N := -5000.0
const ATTACKER_HEX := Vector2i(0, 0)
const DEFENDER_HEX := Vector2i(1, 0)
## Layer tile under the midpoint of ATTACKER_HEX and DEFENDER_HEX (E 8100, N -5000).
const MID_TILE := Vector2i(32, 23)


## Plains everywhere; real metres = 100 + column; the tile (col, row) gets `overrides[tile]`.
static func _grid(overrides: Dictionary = {}) -> HexGrid:
	var grid := HexGrid.new()
	for row in ROWS:
		for col in COLS:
			var c := MapGenerator.offset_to_axial(col, row)
			var tile := Vector2i(col, row)
			grid.set_terrain(c, overrides.get(tile, Terrain.Type.PLAINS))
			grid.set_elevation_m(c, 100.0 + col)
	return grid


static func _layer(overrides: Dictionary = {}, chunk: int = 128) -> TacticalLayer:
	return TacticalLayer.from_grid(_grid(overrides), COLS, ROWS, 250.0, 0.0, 0.0, chunk)


static func _theatre() -> ImportedMap:
	var map := ImportedMap.new()
	map.hex_spacing_m = 1000.0
	map.origin_easting = THEATRE_E
	map.origin_northing = THEATRE_N
	return map


static func _settings() -> ContactSettings:
	var settings := ContactSettings.new()
	settings.width = 40
	settings.height = 30
	settings.turn_limit = 12
	settings.deploy_spacing = 2
	return settings


## A pending contact battle: `attackers` companies of player `attacker`, then `defenders` of the
## other player (coords are placeholders, as TASK-094a writes them).
static func _setup(attackers: int, defenders: int, attacker: int = 0) -> BattleSetup:
	var setup := BattleSetup.new()
	setup.seed = 7
	setup.map_id = &"test_theatre"
	setup.factions = [&"poland", &"russia"]
	setup.attacker = attacker
	setup.conditions = [BattleSetup.Conditions.new(), BattleSetup.Conditions.new()]
	for i in attackers + defenders:
		var company := BattleSetup.Company.new()
		company.player = attacker if i < attackers else 1 - attacker
		company.unit_type = &"leopard_2a4"
		company.strength = 5
		company.ref = "f/%d" % (i + 1)
		setup.companies.append(company)
	return setup


static func _build(
	layer: TacticalLayer,
	setup: BattleSetup,
	attacker_hex := ATTACKER_HEX,
	defender_hex := DEFENDER_HEX
) -> BattleSetup:
	return ContactMap.build_with(setup, attacker_hex, defender_hex, _theatre(), layer, _settings())


## Local offset (column, row) of a layer tile in `region`.
static func _local(region: Rect2i, tile: Vector2i) -> Vector2i:
	return tile - region.position


# --- region -------------------------------------------------------------------------------------


func test_contact_settings_are_shipped_and_valid() -> void:
	var settings := ContactSettings.shipped()
	assert_true(settings != null)
	assert_eq(settings.problem(), "")
	assert_eq(Vector2i(settings.width, settings.height), Vector2i(40, 30))
	assert_eq(settings.turn_limit, 12)
	assert_eq(settings.layer_for(&"suwalki_theatre"), &"suwalki_tactical")
	assert_eq(settings.layer_for(&"nowhere"), &"")


func test_centre_tile_is_under_the_midpoint_of_the_two_hexes() -> void:
	var layer := _layer()
	assert_eq(ContactMap.centre_tile(ATTACKER_HEX, DEFENDER_HEX, _theatre(), layer), MID_TILE)


func test_region_is_the_cut_size_centred_on_the_midpoint() -> void:
	var built := _build(_layer(), _setup(2, 2))
	assert_true(built != null)
	assert_eq(built.map_region.size, Vector2i(40, 30))
	assert_eq(built.map_region.position.y % 2, 0, "starts on an even row")
	var local := _local(built.map_region, MID_TILE)
	assert_eq(local.x, 20)
	assert_true(
		local.y == 15 or local.y == 16, "centred (one row lower when made even): %s" % local
	)


func test_region_is_clamped_into_the_layer_at_the_borders() -> void:
	var layer := _layer()
	# far north-west: hex (-7, -5) lies off the layer's corner
	var north_west := _build(layer, _setup(1, 1), Vector2i(-7, -5), Vector2i(-6, -5))
	assert_eq(north_west.map_region, Rect2i(0, 0, 40, 30))
	# far south-east
	var south_east := _build(layer, _setup(1, 1), Vector2i(8, 3), Vector2i(9, 3))
	assert_eq(south_east.map_region, Rect2i(COLS - 40, ROWS - 30, 40, 30))


func test_region_around_keeps_an_even_start_row() -> void:
	var region := ContactMap.region_around(Vector2i(30, 40), Vector2i(60, 45), Vector2i(40, 30))
	assert_eq(region, Rect2i(10, 14, 40, 30), "the last possible start row 15 is odd -> 14")
	assert_eq(
		ContactMap.region_around(Vector2i(5, 5), Vector2i(30, 30), Vector2i(40, 30)),
		Rect2i(),
		"a layer smaller than the cut"
	)


func test_a_layer_smaller_than_the_cut_builds_nothing() -> void:
	var small := TacticalLayer.from_grid(_grid(), 30, 20)
	assert_eq(_build(small, _setup(1, 1)), null)


func test_the_draft_setup_is_not_changed() -> void:
	var setup := _setup(2, 2)
	var built := _build(_layer(), setup)
	assert_eq(setup.map_id, &"test_theatre")
	assert_eq(setup.map_region, Rect2i())
	assert_eq(setup.companies[0].coord, Vector2i.ZERO)
	assert_eq(built.map_id, &"in_memory", "the layer's id")
	assert_eq(built.companies.size(), 4)
	assert_eq(built.companies[3].ref, "f/4")


# --- the cut ------------------------------------------------------------------------------------


func test_region_grid_keeps_the_layer_tiles_in_local_coordinates() -> void:
	var road_tile := Vector2i(25, 22)
	var grid := _grid({Vector2i(24, 20): Terrain.Type.FOREST, Vector2i(26, 21): Terrain.Type.WATER})
	grid.set_road_links(MapGenerator.offset_to_axial(road_tile.x, road_tile.y), 0b001001)
	grid.set_river_links(MapGenerator.offset_to_axial(24, 20), 0b000100)
	# small chunks: the cut spans several of them
	var layer := TacticalLayer.from_grid(grid, COLS, ROWS, 250.0, 0.0, 0.0, 16)
	var region := Rect2i(12, 8, 40, 30)
	var cut := layer.region_grid(region)
	assert_eq(cut.coords().size(), 1200)
	assert_true(cut.authored_elevation)
	assert_eq(cut.get_terrain(MapGenerator.offset_to_axial(12, 12)), Terrain.Type.FOREST)
	assert_eq(cut.get_terrain(MapGenerator.offset_to_axial(14, 13)), Terrain.Type.WATER)
	assert_eq(cut.road_links(MapGenerator.offset_to_axial(13, 14)), 0b001001)
	assert_eq(cut.river_links(MapGenerator.offset_to_axial(12, 12)), 0b000100)
	assert_eq(cut.elevation_m(MapGenerator.offset_to_axial(0, 0)), 112.0)
	assert_eq(layer.loaded_chunks(), 12)


func test_region_grid_scales_the_elevation_over_the_cut() -> void:
	var layer := _layer({Vector2i(30, 20): Terrain.Type.WATER})
	var cut := layer.region_grid(Rect2i(10, 10, 40, 30))
	var west := MapGenerator.offset_to_axial(0, 0)  # 110 m, the lowest land of the cut
	var east := MapGenerator.offset_to_axial(39, 0)  # 149 m
	assert_true(absf(cut.elevation(west) - layer.land_min) < 0.0001)
	var scale := layer.exaggeration / layer.metres_per_world_unit()
	assert_true(absf(cut.elevation(east) - (layer.land_min + 39.0 * scale)) < 0.0001)
	assert_eq(cut.elevation(MapGenerator.offset_to_axial(20, 10)), layer.water_elevation)


func test_region_grid_rejects_a_bad_region() -> void:
	var layer := _layer()
	assert_true(layer.region_problem(Rect2i(0, 1, 40, 30)).contains("odd row"))
	assert_true(layer.region_problem(Rect2i(30, 0, 40, 30)) != "", "off the east edge")
	assert_true(layer.region_problem(Rect2i()) != "", "empty")
	assert_eq(layer.region_problem(Rect2i(20, 14, 40, 30)), "")


# --- deployment ---------------------------------------------------------------------------------


func test_every_company_is_placed_on_its_own_passable_tile_spaced() -> void:
	var lake := {}
	for row in range(18, 28):
		for col in range(14, 22):
			lake[Vector2i(col, row)] = Terrain.Type.WATER
	var built := _build(_layer(lake), _setup(6, 5))
	var cut := _layer(lake).region_grid(built.map_region)
	var seen := {}
	for company in built.companies:
		assert_true(cut.has_tile(company.coord), "on the cut: %s" % company.coord)
		assert_true(cut.get_terrain(company.coord) != Terrain.Type.WATER, "not in the lake")
		assert_false(seen.has(company.coord), "no two on one tile")
		seen[company.coord] = true
	for a in built.companies:
		for b in built.companies:
			if a != b:
				assert_true(Hex.distance(a.coord, b.coord) >= 2, "%s %s" % [a.coord, b.coord])


func test_the_attacker_deploys_in_the_third_nearest_its_hex() -> void:
	# attacker in the west, defender in the east
	var built := _build(_layer(), _setup(4, 4))
	var west := _max_x(built, 0)
	var east := _min_x(built, 1)
	var third := 40.0 * Hex.SQRT3 / 3.0
	assert_true(west < east - third * 0.9, "west %s, east %s" % [west, east])
	# swapped: player 1 attacks from the east
	var swapped := _build(_layer(), _setup(4, 4, 1), DEFENDER_HEX, ATTACKER_HEX)
	assert_true(_max_x(swapped, 0) < _min_x(swapped, 1), "player 0 now defends in the west")
	# a north -> south contact (two hexes straight above each other) deploys along the rows
	var north_south := _build(_layer(), _setup(3, 3), Vector2i(0, -1), Vector2i(-1, 1))
	for company in north_south.companies:
		var row := MapGenerator.axial_to_offset(company.coord).y
		assert_true(row < 10 if company.player == 0 else row >= 20, "row %d" % row)


func _world_x(c: Vector2i) -> float:
	return Hex.to_world(c, TerrainField.HEX_SIZE).x


func _max_x(setup: BattleSetup, player: int) -> float:
	var result := -INF
	for company in setup.companies:
		if company.player == player:
			result = maxf(result, _world_x(company.coord))
	return result


func _min_x(setup: BattleSetup, player: int) -> float:
	var result := INF
	for company in setup.companies:
		if company.player == player:
			result = minf(result, _world_x(company.coord))
	return result


func test_deployment_is_deterministic() -> void:
	var a := _build(_layer(), _setup(5, 5))
	var b := _build(_layer(), _setup(5, 5))
	assert_eq(a.to_dict(), b.to_dict())


func test_too_many_companies_for_the_third_overflow_into_the_cut() -> void:
	# a cut of 6 x 4 hexes: a third holds ~8 tiles, 9 companies per side spill into the cut
	var settings := _settings()
	settings.width = 6
	settings.height = 4
	var built := ContactMap.build_with(
		_setup(9, 9), ATTACKER_HEX, DEFENDER_HEX, _theatre(), _layer(), settings
	)
	assert_true(built != null)
	var seen := {}
	for company in built.companies:
		assert_false(seen.has(company.coord))
		seen[company.coord] = true
	assert_false(seen.has(built.objectives.hexes[0]), "never on the objective")


func test_no_room_builds_nothing() -> void:
	var settings := _settings()
	settings.width = 3
	settings.height = 3
	assert_eq(
		ContactMap.build_with(
			_setup(5, 5), ATTACKER_HEX, DEFENDER_HEX, _theatre(), _layer(), settings
		),
		null
	)


# --- objectives ---------------------------------------------------------------------------------


func test_objective_is_the_centre_hex_held_by_the_defender() -> void:
	var built := _build(_layer(), _setup(2, 2, 1), DEFENDER_HEX, ATTACKER_HEX)
	var objectives := built.objectives
	assert_eq(objectives.problem(2), "")
	assert_eq(objectives.turn_limit, 12)
	assert_eq(objectives.hexes, [MapGenerator.offset_to_axial(20, 15)] as Array[Vector2i])
	assert_eq(objectives.initial_owners, [0] as Array[int], "player 0 defends")
	assert_eq(objectives.conditions_for(1, VictoryCondition.Kind.TAKE_HEXES).size(), 1)
	assert_eq(objectives.conditions_for(0, VictoryCondition.Kind.TAKE_HEXES).size(), 0)
	assert_eq(objectives.conditions_for(0, VictoryCondition.Kind.HOLD_HEXES).size(), 1)
	assert_eq(objectives.conditions_for(1, VictoryCondition.Kind.HOLD_HEXES).size(), 0)
	assert_eq(objectives.conditions_for(1, VictoryCondition.Kind.ELIMINATE).size(), 1)


func test_objective_moves_off_water_to_the_nearest_passable_hex() -> void:
	var region := Rect2i(12, 8, 40, 30)
	var centre := region.position + Vector2i(20, 15)
	var built := _build(_layer({centre: Terrain.Type.WATER}), _setup(1, 1))
	var hex := built.objectives.hexes[0]
	assert_eq(Hex.distance(hex, MapGenerator.offset_to_axial(20, 15)), 1)


## Plays the contact objectives on a small plains state: attacker 0 at `attacker_at`, defender 1
## far away; returns the state after the attacker's first turn or after the turn limit.
func _play(attacker_at: Vector2i, turns: int) -> GameState:
	var hex := Vector2i(1, 0)
	var state := GameState.new(Fixtures.plains_grid(4), 2, 1)
	state.add_unit(0, Fixtures.infantry(), attacker_at)
	state.add_unit(1, Fixtures.infantry(), Vector2i(-3, 3))
	state.set_objectives(ContactMap.objectives(0, hex, turns))
	state.record_starting_hp()
	var sim := GameSimulation.new(state)
	for i in turns * 2:
		if state.is_over():
			break
		sim.execute(EndTurnCommand.new())
	return state


func test_an_attacker_on_the_centre_at_the_end_of_its_turn_wins() -> void:
	var state := _play(Vector2i(1, 0), 12)
	assert_eq(state.winner, 0)
	assert_eq(state.end_reason, &"objective_taken")


func test_otherwise_the_defender_wins_at_the_turn_limit() -> void:
	var state := _play(Vector2i(0, 0), 3)
	assert_eq(state.winner, 1)
	assert_eq(state.end_reason, &"turn_limit")
