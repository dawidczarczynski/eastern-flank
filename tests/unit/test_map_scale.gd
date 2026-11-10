extends TestCase


func after_each() -> void:
	MapScale.reset()


func test_default_is_the_250_m_hex() -> void:
	assert_true(absf(MapScale.metres_per_unit - 250.0 / sqrt(3.0)) < 0.01)
	assert_true(absf(MapScale.metres_per_unit - 144.34) < 0.01)


func test_to_units_follows_the_scale() -> void:
	assert_true(absf(MapScale.to_units(144.34) - 1.0) < 0.001)
	MapScale.metres_per_unit = 72.17
	assert_true(absf(MapScale.to_units(144.34) - 2.0) < 0.001)


# TASK-110: the scale of a battle's map, from its BattleSetup map id.
func test_suwalki_battle_is_144_34_m_per_unit() -> void:
	var setup := Scenario.suwalki_battle_setup(1)
	var metres := MapScale.for_map_id(setup.map_id)
	assert_true(absf(metres - 144.34) < 0.01, "suwalki %f" % metres)


func test_generated_map_is_the_250_m_hex() -> void:
	var metres := MapScale.for_map_id(BattleSetup.MAP_GENERATED_RIVER)
	assert_true(absf(metres - 250.0 / sqrt(3.0)) < 1e-4, "generated %f" % metres)


func test_apply_map_id_sets_the_scale() -> void:
	MapScale.metres_per_unit = 10.0
	MapScale.apply_map_id(Scenario.SUWALKI_MAP_ID)
	assert_true(absf(MapScale.metres_per_unit - 144.34) < 0.01)
