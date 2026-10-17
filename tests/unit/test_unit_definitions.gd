extends TestCase


func test_infantry_short_name() -> void:
	var definition: UnitDefinition = load("res://data/units/infantry.tres")
	assert_eq(definition.short_name, "INF")


func test_cavalry_short_name() -> void:
	var definition: UnitDefinition = load("res://data/units/cavalry.tres")
	assert_eq(definition.short_name, "CAV")
