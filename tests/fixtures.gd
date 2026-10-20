extends RefCounted
## Shared test data. Usage: const Fixtures := preload("res://tests/fixtures.gd")


## Hexagonal all-plains map with radius `radius` around (0, 0).
static func plains_grid(radius: int) -> HexGrid:
	var grid := HexGrid.new()
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			var c := Vector2i(q, r)
			if Hex.distance(Vector2i.ZERO, c) <= radius:
				grid.set_terrain(c, Terrain.Type.PLAINS)
	return grid


static func infantry() -> UnitDefinition:
	var definition := UnitDefinition.new()
	definition.id = &"test_infantry"
	definition.max_hp = 10
	definition.move_points = 3
	definition.attack = 4
	definition.defense = 2
	return definition


## Unit definition with custom combat stats (3 move points).
static func fighter(
	attack: int, defense: int, max_hp: int = 10, attack_range: int = 1
) -> UnitDefinition:
	var definition := infantry()
	definition.id = &"test_fighter"
	definition.attack = attack
	definition.defense = defense
	definition.max_hp = max_hp
	definition.attack_range = attack_range
	return definition


## The generic infantry calibration unit of the GDD (10 HP, move 3, A4 D3, range 1), translated
## name "Infantry". For presentation tests that need a unit with a CSV-keyed name.
static func generic_infantry() -> UnitDefinition:
	var definition := UnitDefinition.new()
	definition.id = &"test_generic_infantry"
	definition.display_name = "Infantry"
	definition.short_name = "INF"
	definition.unit_class = &"infantry"
	definition.mobility = &"foot"
	definition.max_hp = 10
	definition.move_points = 3
	definition.attack = 4
	definition.defense = 3
	definition.attack_range = 1
	return definition


## The generic cavalry calibration unit of the GDD (8 HP, move 5, A5 D2, range 1), class tank.
static func generic_tank() -> UnitDefinition:
	var definition := UnitDefinition.new()
	definition.id = &"test_generic_tank"
	definition.display_name = "Cavalry"
	definition.short_name = "TNK"
	definition.unit_class = &"tank"
	definition.mobility = &"tracked"
	definition.max_hp = 8
	definition.move_points = 5
	definition.attack = 5
	definition.defense = 2
	definition.attack_range = 1
	return definition
