extends TestCase

const CAVALRY := preload("res://data/units/cavalry.tres")


func test_infantry_short_name() -> void:
	var definition: UnitDefinition = load("res://data/units/infantry.tres")
	assert_eq(definition.short_name, "INF")


func test_cavalry_short_name() -> void:
	assert_eq(CAVALRY.short_name, "CAV")


## Poland's tank: real designation, generic tank stats until TASK-039a derives its own.
func test_m1a2_sepv3_definition() -> void:
	var tank: UnitDefinition = load("res://data/units/m1a2_sepv3.tres")
	var cavalry: UnitDefinition = CAVALRY
	assert_eq(tank.id, &"m1a2_sepv3")
	assert_eq(tank.display_name, "M1A2 SEPv3 Abrams")
	assert_eq(tank.short_name, "M1A2")
	assert_eq(
		[tank.max_hp, tank.move_points, tank.attack, tank.defense, tank.attack_range],
		[cavalry.max_hp, cavalry.move_points, cavalry.attack, cavalry.defense, cavalry.attack_range]
	)
