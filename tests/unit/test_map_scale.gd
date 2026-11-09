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
