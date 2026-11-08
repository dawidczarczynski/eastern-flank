extends TestCase
## Allied contributions, data and validation (TASK-118).

const COLUMNS: Array[StringName] = [&"poland", &"lithuania"]


static func _grid() -> HexGrid:
	var grid := HexGrid.new()
	for q in range(0, 6):
		for r in range(0, 2):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	grid.set_terrain(Vector2i(5, 1), Terrain.Type.WATER)
	return grid


static func _country_map() -> Dictionary:
	var result := {}
	for q in range(0, 6):
		for r in range(0, 2):
			result[Vector2i(q, r)] = COLUMNS[q / 3]
	return result


static func _side(id: StringName, faction: StringName) -> SideDefinition:
	var side := SideDefinition.new()
	side.id = id
	side.lead_faction = faction
	side.factions = [faction] as Array[StringName]
	return side


static func _type(faction: StringName, unit_id: StringName) -> FormationDefinition:
	var def := FormationDefinition.new()
	def.id = &"test_type"
	def.faction = faction
	def.formation_class = &"mechanised"
	def.companies.append(load("res://data/units/%s.tres" % unit_id) as UnitDefinition)
	return def


static func placement(id: StringName, player: int, coord: Vector2i) -> FormationPlacement:
	var p := FormationPlacement.new()
	p.id = id
	p.display_name = String(id)
	p.parent = "Brigade"
	p.player = player
	p.coord = coord
	p.definition = (
		_type(&"poland", &"pl_mech_infantry") if player == 0 else _type(&"russia", &"t72b3")
	)
	return p


static func setup(
	country_id: StringName,
	stance: StringName,
	side: int,
	leaning: int,
	contribution: Array[FormationPlacement] = []
) -> CountrySetup:
	var s := CountrySetup.new()
	s.country = CountryDefinition.find(country_id)
	s.stance = stance
	s.side = side
	s.leaning = leaning
	s.contribution = contribution
	return s


## Poland (q 0-2) and Lithuania (q 3-5), `lithuania_side` = the side Lithuania is aligned with and
## leans to; contributions A on (4, 0), B on (5, 0).
static func definition(lithuania_side := 0, contribution_player := -1) -> OperationDefinition:
	var op := OperationDefinition.new()
	op.id = &"strip"
	op.display_name = "Strip"
	op.map_id = &"none"
	op.sides = [_side(&"blue", &"poland"), _side(&"red", &"russia")] as Array[SideDefinition]
	var player := lithuania_side if contribution_player < 0 else contribution_player
	var list: Array[FormationPlacement] = [
		placement(&"a", player, Vector2i(4, 0)), placement(&"b", player, Vector2i(5, 0))
	]
	op.countries = (
		[
			setup(&"poland", &"belligerent", 1 - lithuania_side, 1 - lithuania_side),
			setup(&"lithuania", &"aligned", lithuania_side, lithuania_side, list),
		]
		as Array[CountrySetup]
	)
	return op


static func build(op: OperationDefinition) -> OperationalState:
	return Operation.from_definition(op, 1, _grid(), _country_map())


func _contribution(op: OperationDefinition) -> Array[FormationPlacement]:
	return op.countries[1].contribution


func test_valid_definition_builds() -> void:
	var state := build(definition())
	assert_true(state != null)
	var lithuania := state.get_country(&"lithuania")
	assert_eq(lithuania.contribution.size(), 2)
	assert_false(lithuania.contributed)
	assert_eq(lithuania.snapshot()["contributed"], false)
	assert_eq(state.formations.size(), 0, "nothing on the map before the country joins")


func test_wrong_side_is_rejected() -> void:
	assert_true(build(definition(0, 1)) == null)


func test_contribution_without_leaning_is_rejected() -> void:
	var op := definition()
	op.countries[1].leaning = -1
	assert_true(build(op) == null)


func test_coord_outside_the_country_is_rejected() -> void:
	var op := definition()
	_contribution(op)[0].coord = Vector2i(1, 0)
	assert_true(build(op) == null)


func test_impassable_coord_is_rejected() -> void:
	var op := definition()
	_contribution(op)[0].coord = Vector2i(5, 1)
	assert_true(build(op) == null)


func test_repeated_id_is_rejected() -> void:
	var inner := definition()
	_contribution(inner)[1].id = &"a"
	assert_true(build(inner) == null, "repeated inside the contribution")
	var outer := definition()
	var start := placement(&"a", 0, Vector2i(0, 0))
	outer.formations.append(start)
	assert_true(build(outer) == null, "repeats a start formation")
	var other := definition()
	other.countries[0].contribution = (
		[placement(&"b", 1, Vector2i(0, 0))] as Array[FormationPlacement]
	)
	assert_true(build(other) == null, "repeats another country's contribution")


func test_foreign_faction_is_rejected() -> void:
	var op := definition()
	_contribution(op)[0].definition = _type(&"russia", &"t72b3")
	assert_true(build(op) == null)


func test_suwalki_gap_contributions() -> void:
	var state := Operation.build(&"suwalki_gap", 1)
	assert_true(state != null)
	var expected := {&"lithuania": [3, 120, 0], &"belarus": [3, 110, 1]}
	for id: StringName in expected:
		var country := state.get_country(id)
		assert_eq(country.contribution.size(), expected[id][0], "%s count" % id)
		var total := 0
		for p in country.contribution:
			assert_eq(state.country_at(p.coord), id, "%s hex in country" % p.id)
			assert_eq(p.player, expected[id][2])
			total += Formation.from_placement(p).strength()
		assert_eq(total, expected[id][1], "%s strength" % id)
