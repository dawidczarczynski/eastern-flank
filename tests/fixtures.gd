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


## A MapView built on `grid` with `quality`, outside a scene tree (its _ready() is run here).
## The caller frees it.
static func map_view(grid: HexGrid, quality: Dictionary = {}) -> MapView:
	var view := MapView.new()
	view._ready()
	view.quality = quality
	view.build(grid)
	return view


## Undoes what tests change on a MapView shared between them (TestCase.before_all): highlights,
## hover, path dots, grid mode and camera distance. The built terrain stays.
static func reset_map_view(view: MapView) -> void:
	view.clear_highlights()
	view.set_hover(null)
	view.clear_path()
	if not view._grid_auto:
		view.cycle_grid_mode()
	view.set_camera_distance(CameraRig.DEFAULT_DISTANCE)


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


## The generic cavalry calibration unit of the GDD (8 HP, move 5, A5 D2, range 1), class tank.
static func generic_tank() -> UnitDefinition:
	var definition := UnitDefinition.new()
	definition.id = &"test_generic_tank"
	definition.display_name = "Test Tank"
	definition.short_name = "TNK"
	definition.unit_class = &"tank"
	definition.mobility = &"tracked"
	definition.max_hp = 8
	definition.move_points = 5
	definition.attack = 5
	definition.defense = 2
	definition.attack_range = 1
	return definition


## Victory condition of `kind` (VictoryCondition.Kind) for `player` (-1 = both).
static func condition(
	kind: VictoryCondition.Kind, player: int, hexes: Array[Vector2i] = [], share_percent: int = 0
) -> VictoryCondition:
	return VictoryCondition.make(kind, player, hexes, share_percent)


## BattleObjectives with `turn_limit`, objective `hexes` (initial owners parallel to them,
## -1 = neutral) and `conditions`.
static func objectives(
	turn_limit: int, hexes: Array[Vector2i], owners: Array[int], conditions: Array[VictoryCondition]
) -> BattleObjectives:
	var result := BattleObjectives.new()
	result.turn_limit = turn_limit
	result.hexes = hexes
	result.initial_owners = owners
	result.conditions = conditions
	return result
