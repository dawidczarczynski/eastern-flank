extends TestCase
## Contact maps on the real theatre (TASK-094b): the shipped tactical layer
## data/maps/suwalki_tactical/, contacts around the suwalki_gap start, build time, real terrain.

## Budget of one contact map: ContactMap.build + Scenario.from_setup (TASK-094b [ASSUMPTION]).
const BUDGET_MS := 1500
const LAYER_ID := &"suwalki_tactical"
## Operational hexes of the theatre (axial): the town of Suwalki (urban, on the Gap's roads) and
## Lake Sniardwy (a WATER hex).
const SUWALKI_HEX := Vector2i(17, 34)
const SNIARDWY_HEX := Vector2i(-3, 43)

static var _state: OperationalState


func before_all() -> void:
	_state = Operation.build(&"suwalki_gap", 1)


func after_all() -> void:
	_state = null


## A pending contact battle as TASK-094a drafts it: `attacker`'s companies, then `defender`'s.
static func _draft(attacker: Formation, defender: Formation) -> BattleSetup:
	var setup := BattleSetup.new()
	setup.seed = 11
	setup.map_id = _state.map_id
	setup.operation_name = _state.operation_name
	setup.factions = _state.player_factions.duplicate()
	setup.attacker = attacker.owner_id
	setup.conditions = [BattleSetup.Conditions.new(), BattleSetup.Conditions.new()]
	for formation in [attacker, defender]:
		for company: Formation.Company in formation.companies:
			var planned := BattleSetup.Company.new()
			planned.player = formation.owner_id
			planned.unit_type = company.unit_type
			planned.strength = company.strength
			planned.ref = company.ref
			setup.companies.append(planned)
	return setup


## The first formation of the other player whose companies the lead faction fields (stands in
## for the defender's companies at any hex).
static func _enemy_of(formation: Formation) -> Formation:
	for other in _state.formations:
		if other.owner_id != formation.owner_id and _fieldable(other):
			return other
	return null


## Whether every company of `formation` is in its player's battle faction roster.
static func _fieldable(formation: Formation) -> bool:
	var faction := FactionRegistry.get_faction(_state.player_factions[formation.owner_id])
	for company in formation.companies:
		if faction.find_unit(company.unit_type) == null:
			return false
	return true


## Contact points: every fieldable formation's hex with each passable neighbour (in
## Hex.DIRECTIONS order, at most two), plus a land hex on the theatre's west edge.
static func _contacts() -> Array:
	var result: Array = []
	for formation in _state.formations:
		if not _fieldable(formation):
			continue
		var found := 0
		for n in Hex.neighbors(formation.coord):
			if found < 2 and _state.grid.has_tile(n):
				if _state.grid.get_terrain(n) != Terrain.Type.WATER:
					result.append([formation, formation.coord, n])
					found += 1
	var edge := _west_edge_pair()
	result.append([_state.formations[0], edge[0], edge[1]])
	return result


## The first land hex of offset column 0 (north to south) with a land neighbour.
static func _west_edge_pair() -> Array[Vector2i]:
	for row in 64:
		var c := MapGenerator.offset_to_axial(0, row)
		if _state.grid.get_terrain(c) == Terrain.Type.WATER:
			continue
		for n in Hex.neighbors(c):
			if _state.grid.has_tile(n) and _state.grid.get_terrain(n) != Terrain.Type.WATER:
				return [c, n]
	return []


func test_the_layer_is_shipped_and_credited() -> void:
	var layer := TacticalLayer.find(LAYER_ID)
	assert_true(layer != null)
	assert_true(layer.sources.contains("OpenStreetMap"))
	assert_true(layer.sources.contains("Copernicus"))
	assert_true(
		FileAccess.get_file_as_string("res://data/maps/CREDITS").contains("suwalki_tactical")
	)
	var theatre := ImportedMap.find(&"suwalki_theatre")
	assert_eq(layer.crs, theatre.crs)
	var chunks := 0
	for file in DirAccess.get_files_at("res://data/maps/suwalki_tactical"):
		if file.begins_with("chunk_") and file.ends_with(".tres"):
			chunks += 1
	var per_row := ceili(float(layer.width) / layer.chunk_size)
	assert_eq(chunks, per_row * ceili(float(layer.height) / layer.chunk_size))


func test_contacts_of_the_suwalki_gap_start_start_battles_within_the_budget() -> void:
	var contacts := _contacts()
	assert_true(contacts.size() >= 20, "%d contact points" % contacts.size())
	var slowest := 0
	var total := 0
	for contact: Array in contacts:
		var attacker: Formation = contact[0]
		var started := Time.get_ticks_usec()
		var setup := ContactMap.build(_draft(attacker, _enemy_of(attacker)), contact[1], contact[2])
		var state := Scenario.from_setup(setup) if setup != null else null
		var elapsed := (Time.get_ticks_usec() - started) / 1000
		assert_true(state != null, "contact %s -> %s" % [contact[1], contact[2]])
		if state == null:
			continue
		assert_eq(state.units.size(), setup.companies.size())
		assert_eq(state.grid.coords().size(), 40 * 30)
		slowest = maxi(slowest, elapsed)
		total += elapsed
	print(
		(
			"  contact maps: %d built, slowest %d ms, mean %d ms"
			% [contacts.size(), slowest, total / maxi(1, contacts.size())]
		)
	)
	assert_true(slowest <= BUDGET_MS, "slowest contact map %d ms" % slowest)


func test_a_contact_on_the_gap_road_keeps_the_roads() -> void:
	var defender := SUWALKI_HEX + Hex.DIRECTIONS[0]
	var setup := ContactMap.build(
		_draft(_state.formations[0], _enemy_of(_state.formations[0])), SUWALKI_HEX, defender
	)
	var grid := TacticalLayer.find(setup.map_id).region_grid(setup.map_region)
	var roads := 0
	for c in grid.coords():
		if grid.road_links(c) != 0:
			roads += 1
	assert_true(roads >= 20, "%d road tiles in the cut around Suwalki" % roads)
	var types := {}
	for c in grid.coords():
		types[grid.get_terrain(c)] = true
	assert_true(types.has(Terrain.Type.URBAN), "the town")


## The layer has farmland (the lu1 land-use tiles): the cut around Suwalki is largely fields,
## and plains stay for the unclassified open land.
func test_the_cut_around_suwalki_has_fields() -> void:
	var defender := SUWALKI_HEX + Hex.DIRECTIONS[0]
	var setup := ContactMap.build(
		_draft(_state.formations[0], _enemy_of(_state.formations[0])), SUWALKI_HEX, defender
	)
	var grid := TacticalLayer.find(setup.map_id).region_grid(setup.map_region)
	var fields := 0
	var plains := 0
	for c in grid.coords():
		if grid.get_terrain(c) == Terrain.Type.FIELDS:
			fields += 1
		elif grid.get_terrain(c) == Terrain.Type.PLAINS:
			plains += 1
	assert_true(fields >= 200, "%d fields tiles in the cut around Suwalki" % fields)
	assert_true(plains > 0, "%d plains tiles in the cut around Suwalki" % plains)


func test_a_lake_hex_is_water_in_the_cut() -> void:
	var theatre := ImportedMap.find(&"suwalki_theatre")
	assert_eq(_state.grid.get_terrain(SNIARDWY_HEX), Terrain.Type.WATER, "the theatre's lake hex")
	var layer := TacticalLayer.find(LAYER_ID)
	var centre := ContactMap.centre_tile(SNIARDWY_HEX, SNIARDWY_HEX, theatre, layer)
	assert_eq(layer.terrain_at(centre), Terrain.Type.WATER)
	var region := ContactMap.region_around(
		centre, Vector2i(layer.width, layer.height), Vector2i(40, 30)
	)
	var grid := layer.region_grid(region)
	var water := 0
	for c in grid.coords():
		if grid.get_terrain(c) == Terrain.Type.WATER:
			water += 1
	assert_true(water >= 300, "%d water tiles in the cut on the lake" % water)
