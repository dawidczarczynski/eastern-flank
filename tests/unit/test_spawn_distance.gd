extends TestCase
## Turn-1 spawn distance with realistic weapon ranges (TASK-131a): no enemy pair starts within
## the 8-hex effective range of the tank guns, so the first turn is spent moving into position.

## The longest direct-fire effective range of the shipped units (tank guns, 2000 m).
const TANK_EFFECTIVE_HEXES := 8


func _closest_enemy_pair(state: GameState) -> int:
	var best := 1 << 30
	for a: Unit in state.units.values():
		for b: Unit in state.units.values():
			if a.owner_id < b.owner_id:
				best = mini(best, Hex.distance(a.coord, b.coord))
	return best


func test_tank_effective_range_is_the_longest_direct_one() -> void:
	var longest := 0
	for faction in FactionRegistry.all():
		for definition: UnitDefinition in faction.default_force:
			if not definition.is_indirect():
				longest = maxi(longest, definition.effective_hexes())
	assert_eq(longest, TANK_EFFECTIVE_HEXES)


func test_default_battle_spawns_out_of_effective_range() -> void:
	for factions: Array[StringName] in [
		[&"poland", &"russia"] as Array[StringName], [&"russia", &"poland"] as Array[StringName]
	]:
		var state := Scenario.default_battle(1, factions)
		assert_true(_closest_enemy_pair(state) > TANK_EFFECTIVE_HEXES, str(factions))


func test_suwalki_battle_spawns_out_of_effective_range() -> void:
	var state := Scenario.suwalki_battle(1)
	assert_true(state.units.size() > 0)
	assert_true(_closest_enemy_pair(state) > TANK_EFFECTIVE_HEXES, str(_closest_enemy_pair(state)))


func test_artillery_spawns_in_the_back_column() -> void:
	var setup := Scenario.default_battle_setup(1)
	for company in setup.companies:
		var definition := FactionRegistry.get_faction(setup.factions[company.player]).find_unit(
			company.unit_type
		)
		var column := MapGenerator.axial_to_offset(company.coord).x
		var back: int = Scenario.BACK_SLOTS[company.player][0]
		assert_eq(column == back, definition.is_indirect(), String(company.unit_type))
