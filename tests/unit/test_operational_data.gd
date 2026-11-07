extends TestCase
## Operational data (TASK-092b): formation types, sides and the Suwałki Gap operation.

const TYPE_STRENGTHS := {
	&"pl_mech_battalion": 40,
	&"pl_tank_battalion": 40,
	&"pl_mlrs_squadron": 18,
	&"ru_motor_rifle_battalion": 38,
	&"ru_tank_battalion": 34,
	&"ru_mlrs_battalion": 18,
}
const _MBT := &"m1a2_sepv3"
const _MR := &"ru_motor_rifle"
const TYPE_COMPANIES := {
	&"pl_mech_battalion": [&"pl_mech_infantry", &"pl_mech_infantry", &"pl_mech_infantry", _MBT],
	&"pl_tank_battalion": [&"m1a2_sepv3", &"m1a2_sepv3", &"m1a2_sepv3", &"pl_mech_infantry"],
	&"pl_mlrs_squadron": [&"homar_k", &"homar_k", &"homar_k"],
	&"ru_motor_rifle_battalion": [_MR, _MR, _MR, &"t72b3"],
	&"ru_tank_battalion": [&"t72b3", &"t72b3", &"t72b3", &"ru_motor_rifle"],
	&"ru_mlrs_battalion": [&"bm27_uragan", &"bm27_uragan", &"bm27_uragan"],
}


static func _type(type_id: StringName) -> FormationDefinition:
	return load("res://data/formations/%s.tres" % type_id) as FormationDefinition


func test_formation_types_have_their_companies_and_strength() -> void:
	for type_id: StringName in TYPE_STRENGTHS:
		var def := _type(type_id)
		assert_true(def != null, "%s loads" % type_id)
		if def == null:
			continue
		assert_eq(def.id, type_id)
		assert_eq(def.echelon, &"battalion")
		assert_eq(def.move_points, 8, "%s move points" % type_id)
		assert_eq(def.strength(), TYPE_STRENGTHS[type_id], "%s strength" % type_id)
		var ids: Array = []
		for unit in def.companies:
			ids.append(unit.id)
		assert_eq(ids, TYPE_COMPANIES[type_id], "%s companies" % type_id)
		var faction := FactionRegistry.get_faction(def.faction)
		assert_true(faction != null, "%s faction" % type_id)
		for unit in def.companies:
			assert_true(faction != null and faction.has_unit(unit), "%s in roster" % unit.id)
		assert_false(def.display_name.is_empty())


func test_formation_classes() -> void:
	assert_eq(_type(&"pl_mech_battalion").formation_class, &"mechanised")
	assert_eq(_type(&"ru_motor_rifle_battalion").formation_class, &"mechanised")
	assert_eq(_type(&"pl_tank_battalion").formation_class, &"armoured")
	assert_eq(_type(&"ru_tank_battalion").formation_class, &"armoured")
	assert_eq(_type(&"pl_mlrs_squadron").formation_class, &"artillery")
	assert_eq(_type(&"ru_mlrs_battalion").formation_class, &"artillery")


func test_sides() -> void:
	var nato := SideDefinition.find(&"nato")
	var russia := SideDefinition.find(&"russia")
	assert_true(nato != null and russia != null)
	assert_eq(nato.display_name, "NATO")
	assert_eq(nato.lead_faction, &"poland")
	assert_eq(nato.factions, [&"poland"] as Array[StringName])
	assert_eq(russia.display_name, "Russia")
	assert_eq(russia.lead_faction, &"russia")
	assert_eq(russia.factions, [&"russia"] as Array[StringName])
	assert_true(SideDefinition.find(&"nobody") == null)
	assert_true(SideDefinition.find(&"../factions/poland") == null)


func test_suwalki_gap_definition() -> void:
	var op := OperationDefinition.find(&"suwalki_gap")
	assert_true(op != null)
	assert_eq(op.map_id, &"suwalki_theatre")
	assert_eq(op.sides.size(), 2)
	assert_eq(op.sides[0].id, &"nato")
	assert_eq(op.sides[1].id, &"russia")
	assert_eq(op.first_player, 1)
	var counts := [0, 0]
	var strength := [0, 0]
	var types := [{}, {}]
	for p in op.formations:
		counts[p.player] += 1
		strength[p.player] += p.definition.strength()
		types[p.player][p.definition.id] = int(types[p.player].get(p.definition.id, 0)) + 1
		assert_false(p.display_name.is_empty(), "%s name" % p.id)
		assert_false(p.parent.is_empty(), "%s parent" % p.id)
	assert_eq(counts, [8, 10])
	assert_eq(strength, [276, 332])
	assert_eq(
		types[0], {&"pl_mech_battalion": 4, &"pl_tank_battalion": 2, &"pl_mlrs_squadron": 2}
	)
	assert_eq(
		types[1],
		{&"ru_motor_rifle_battalion": 6, &"ru_tank_battalion": 2, &"ru_mlrs_battalion": 2}
	)


func test_suwalki_gap_sides_keep_their_distance() -> void:
	var op := OperationDefinition.find(&"suwalki_gap")
	var map := ImportedMap.find(op.map_id).to_grid()
	for a in op.formations:
		assert_true(map.has_tile(a.coord), "%s on the map" % a.id)
		assert_true(map.move_cost(a.coord) != Terrain.IMPASSABLE, "%s on land" % a.id)
		for b in op.formations:
			if a.player == 0 and b.player == 1:
				var d := Hex.distance(a.coord, b.coord)
				assert_true(d >= 3, "%s – %s only %d hexes apart" % [a.id, b.id, d])
