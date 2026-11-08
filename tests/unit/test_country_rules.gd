extends TestCase
## Countries and stances in the operational state (TASK-114).

const COUNTRY_COLUMNS: Array[StringName] = [&"poland", &"lithuania", &"belarus", &"russia"]


static func _grid() -> HexGrid:
	var grid := HexGrid.new()
	for q in range(0, 8):
		for r in range(0, 2):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	return grid


static func _country_map() -> Dictionary:
	var result := {}
	for q in range(0, 8):
		for r in range(0, 2):
			result[Vector2i(q, r)] = COUNTRY_COLUMNS[q / 2]
	return result


static func _setup(
	country_id: StringName, stance: StringName, side: int, leaning: int
) -> CountrySetup:
	var setup := CountrySetup.new()
	setup.country = CountryDefinition.find(country_id)
	setup.stance = stance
	setup.side = side
	setup.leaning = leaning
	return setup


static func _definition() -> OperationDefinition:
	var op := OperationDefinition.new()
	op.id = &"strip"
	op.display_name = "Strip"
	op.map_id = &"none"
	var blue := SideDefinition.new()
	blue.id = &"blue"
	blue.lead_faction = &"poland"
	blue.factions = [&"poland"] as Array[StringName]
	var red := SideDefinition.new()
	red.id = &"red"
	red.lead_faction = &"russia"
	red.factions = [&"russia"] as Array[StringName]
	op.sides = [blue, red] as Array[SideDefinition]
	op.countries = (
		[
			_setup(&"poland", &"belligerent", 0, 0),
			_setup(&"lithuania", &"aligned", 0, 0),
			_setup(&"belarus", &"aligned", 1, 1),
			_setup(&"russia", &"belligerent", 1, 1),
		]
		as Array[CountrySetup]
	)
	return op


static func _strip(op: OperationDefinition = null) -> OperationalState:
	return Operation.from_definition(
		op if op != null else _definition(), 1, _grid(), _country_map()
	)


func test_data_files() -> void:
	var expected := {&"poland": "PL", &"lithuania": "LT", &"belarus": "BY", &"russia": "RU"}
	for id: StringName in expected:
		var country := CountryDefinition.find(id)
		assert_true(country != null, String(id))
		assert_eq(country.id, id)
		assert_eq(country.iso_code, expected[id])
		assert_eq(country.sanctuary, id == &"russia", "%s sanctuary" % id)
		assert_eq(CountryDefinition.find_by_iso(expected[id]).id, id)
	assert_true(CountryDefinition.find(&"nowhere") == null)
	assert_true(CountryDefinition.find_by_iso("XX") == null)


func test_state_from_definition() -> void:
	var state := _strip()
	assert_eq(state.countries.size(), 4)
	assert_eq(state.countries[0].id, &"poland")
	var belarus := state.get_country(&"belarus")
	assert_eq(belarus.stance, &"aligned")
	assert_eq(belarus.side, 1)
	assert_eq(belarus.leaning, 1)
	assert_eq(belarus.casus_belli, [false, false] as Array[bool])
	assert_eq(belarus.breached_by, [false, false] as Array[bool])
	assert_eq(belarus.declared_by, [false, false] as Array[bool])
	assert_true(state.get_country(&"zz") == null)
	assert_eq(state.country_at(Vector2i(5, 1)), &"belarus")
	assert_eq(state.country_at(Vector2i(50, 1)), &"")


func test_snapshot_sorted() -> void:
	var snap := _strip().snapshot()["countries"] as Array
	var ids: Array = []
	for entry: Dictionary in snap:
		ids.append(entry["id"])
	assert_eq(ids, [&"belarus", &"lithuania", &"poland", &"russia"])
	assert_eq(snap[0]["stance"], &"aligned")
	assert_eq(snap[0]["side"], 1)
	assert_eq(snap[0]["casus_belli"], [false, false])


func test_rejects_invalid_setups() -> void:
	var op := _definition()
	op.countries[0].stance = &"allied"
	assert_true(_strip(op) == null, "unknown stance")
	op = _definition()
	op.countries[0] = _setup(&"poland", &"neutral", 0, 0)
	assert_true(_strip(op) == null, "neutral with a side")
	op = _definition()
	op.countries[0] = _setup(&"poland", &"aligned", -1, 0)
	assert_true(_strip(op) == null, "aligned without a side")
	op = _definition()
	op.countries[0] = _setup(&"poland", &"belligerent", 2, 0)
	assert_true(_strip(op) == null, "side 2")
	op = _definition()
	op.countries[0].leaning = 2
	assert_true(_strip(op) == null, "leaning 2")
	op = _definition()
	op.countries.append(_setup(&"poland", &"neutral", -1, 0))
	assert_true(_strip(op) == null, "duplicate country")
	op = _definition()
	op.countries.pop_back()
	assert_true(_strip(op) == null, "country on the map without a setup")


func test_rejects_unknown_map_iso() -> void:
	var map := ImportedMap.new()
	map.id = &"iso_test"
	map.countries = PackedStringArray(["XX"])
	assert_true(CountryDefinition.find_by_iso("XX") == null)
	assert_true(Operation._map_countries(map).has(&"error"))


func test_rejects_formation_on_closed_hex() -> void:
	var op := _definition()
	var type := FormationDefinition.new()
	type.id = &"t"
	type.faction = &"poland"
	type.formation_class = &"mechanised"
	type.companies.append(load("res://data/units/pl_mech_infantry.tres") as UnitDefinition)
	var placement := FormationPlacement.new()
	placement.id = &"p"
	placement.player = 0
	placement.definition = type
	placement.coord = Vector2i(4, 0)
	op.formations.append(placement)
	assert_true(_strip(op) == null, "player 0 on hostile Belarus")
	placement.coord = Vector2i(2, 0)
	assert_true(_strip(op) != null, "player 0 on aligned Lithuania")


func test_relation() -> void:
	var s := _strip()
	var expected := [
		[&"own", &"own", &"hostile", &"enemy"],
		[&"enemy", &"hostile", &"own", &"own"],
	]
	for player in 2:
		for i in 4:
			assert_eq(
				CountryRules.relation(s, player, COUNTRY_COLUMNS[i]),
				expected[player][i],
				"player %d %s" % [player, COUNTRY_COLUMNS[i]]
			)
	assert_eq(CountryRules.relation(s, 0, &""), &"none")


func test_neutral_relation() -> void:
	var op := _definition()
	op.countries[1] = _setup(&"lithuania", &"neutral", -1, 0)
	var s := _strip(op)
	assert_eq(CountryRules.relation(s, 0, &"lithuania"), &"neutral")
	assert_false(CountryRules.may_enter(s, 0, Vector2i(2, 0)))
	assert_false(CountryRules.may_enter(s, 1, Vector2i(2, 0)))


func test_may_enter_and_breach() -> void:
	var s := _strip()
	assert_true(CountryRules.may_enter(s, 0, Vector2i(1, 0)))
	assert_true(CountryRules.may_enter(s, 0, Vector2i(2, 0)))
	assert_false(CountryRules.may_enter(s, 0, Vector2i(4, 0)))
	assert_false(CountryRules.may_enter(s, 0, Vector2i(6, 0)), "sanctuary")
	s.get_country(&"russia").breached_by[0] = true
	assert_true(CountryRules.may_enter(s, 0, Vector2i(6, 0)))
	assert_true(CountryRules.may_enter(s, 1, Vector2i(0, 0)))
	assert_false(CountryRules.may_enter(s, 1, Vector2i(2, 0)))
	assert_true(CountryRules.may_enter(s, 1, Vector2i(4, 0)))
	assert_true(CountryRules.may_enter(s, 0, Vector2i(30, 30)), "no country")


func test_side_symmetry_of_sanctuary() -> void:
	var s := _strip()
	var poland := CountryDefinition.new()
	poland.id = &"poland"
	poland.iso_code = "PL"
	poland.sanctuary = true
	s.get_country(&"poland").definition = poland
	assert_false(CountryRules.may_enter(s, 1, Vector2i(0, 0)))
	s.get_country(&"poland").breached_by[1] = true
	assert_true(CountryRules.may_enter(s, 1, Vector2i(0, 0)))


func test_may_strike() -> void:
	var s := _strip()
	assert_false(CountryRules.may_strike(s, 0, Vector2i(1, 0)), "own soil")
	assert_false(CountryRules.may_strike(s, 0, Vector2i(2, 0)), "own aligned soil")
	assert_false(CountryRules.may_strike(s, 0, Vector2i(4, 0)))
	assert_false(CountryRules.may_strike(s, 0, Vector2i(6, 0)))
	assert_true(CountryRules.may_strike(s, 1, Vector2i(0, 0)))
	s.get_country(&"russia").breached_by[0] = true
	assert_true(CountryRules.may_strike(s, 0, Vector2i(6, 0)))


func test_set_stance_example() -> void:
	var s := _strip()
	var events := CountryRules.set_stance(s, &"belarus", &"belligerent", 1, &"test", 0)
	var belarus := s.get_country(&"belarus")
	assert_eq(belarus.stance, &"belligerent")
	assert_eq(belarus.side, 1)
	assert_eq(CountryRules.relation(s, 0, &"belarus"), &"enemy")
	assert_true(CountryRules.may_enter(s, 0, Vector2i(4, 0)))
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], &"country_stance_changed")
	assert_eq(events[0]["country"], &"belarus")
	assert_eq(events[0]["stance"], &"belligerent")
	assert_eq(events[0]["side"], 1)
	assert_eq(events[0]["previous_stance"], &"aligned")
	assert_eq(events[0]["previous_side"], 1)
	assert_eq(events[0]["cause"], &"test")
	assert_eq(events[0]["by"], 0)
	var again := CountryRules.set_stance(s, &"belarus", &"neutral", -1, &"test", 0)
	assert_true(again.is_empty())
	assert_eq(belarus.stance, &"belligerent")


func test_set_stance_legal_transitions() -> void:
	var op := _definition()
	op.countries[0] = _setup(&"poland", &"neutral", -1, 0)
	var s := _strip(op)
	var poland := s.get_country(&"poland")
	poland.casus_belli = [true, true]
	poland.breached_by = [true, false]
	poland.declared_by = [false, true]
	assert_eq(CountryRules.set_stance(s, &"poland", &"aligned", 1, &"x", -1).size(), 1)
	assert_eq(poland.side, 1)
	assert_eq(poland.casus_belli, [false, false] as Array[bool], "casus belli resets")
	assert_eq(poland.breached_by, [true, false] as Array[bool])
	assert_eq(poland.declared_by, [false, true] as Array[bool])
	assert_eq(CountryRules.set_stance(s, &"poland", &"neutral", -1, &"x", 0).size(), 1)
	assert_eq(poland.stance, &"neutral")
	assert_eq(CountryRules.set_stance(s, &"poland", &"belligerent", 0, &"x", 0).size(), 1)
	assert_eq(poland.stance, &"belligerent")


func test_set_stance_illegal_transitions() -> void:
	var s := _strip()
	# [country, stance, side]
	var cases := [
		[&"lithuania", &"aligned", 0],
		[&"lithuania", &"aligned", 1],
		[&"lithuania", &"belligerent", 1],
		[&"lithuania", &"neutral", 0],
		[&"lithuania", &"belligerent", 2],
		[&"lithuania", &"war", 0],
		[&"poland", &"neutral", -1],
		[&"poland", &"aligned", 0],
		[&"poland", &"belligerent", 1],
		[&"poland", &"belligerent", 0],
	]
	for c: Array in cases:
		var before := s.snapshot()
		assert_true(CountryRules.set_stance(s, c[0], c[1], c[2], &"x", 0).is_empty(), str(c))
		assert_eq(s.snapshot(), before, str(c))
	var neutral_op := _definition()
	neutral_op.countries[0] = _setup(&"poland", &"neutral", -1, 0)
	var n := _strip(neutral_op)
	assert_true(CountryRules.set_stance(n, &"poland", &"neutral", -1, &"x", 0).is_empty())
	assert_true(CountryRules.set_stance(n, &"poland", &"neutral", 0, &"x", 0).is_empty())
	assert_true(CountryRules.set_stance(n, &"poland", &"aligned", -1, &"x", 0).is_empty())
	assert_true(CountryRules.set_stance(n, &"nowhere", &"aligned", 0, &"x", 0).is_empty())


func test_shipped_operation_start_is_open() -> void:
	var s := Operation.build(&"suwalki_gap", 7)
	assert_eq(s.countries.size(), 4)
	for f in s.formations:
		assert_true(CountryRules.may_enter(s, f.owner_id, f.coord), String(f.id))
		var country := s.country_at(f.coord)
		if f.owner_id == 0:
			assert_eq(country, &"poland", String(f.id))
		else:
			assert_true([&"russia", &"belarus"].has(country), "%s in %s" % [f.id, country])
