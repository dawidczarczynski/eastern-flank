class_name OperationalMovement
extends Resource
## Movement costs of the operational layer (TASK-092c, GDD "Movement costs"), kept in
## data/operational/movement.tres. Independent of the tactical Terrain.features() costs.

const PATH := "res://data/operational/movement.tres"

static var _default: OperationalMovement

## Cost of entering a hex of each Terrain.Type (index = enum value); 0 = impassable.
@export var move_costs: PackedInt32Array = PackedInt32Array()
## Cost of a step along a road link.
@export var road_cost: int = 1
## Extra cost of entering a river hex without a road link.
@export var river_extra_cost: int = 2


## The shipped data/operational/movement.tres, loaded once.
static func shipped() -> OperationalMovement:
	if _default == null:
		_default = load(PATH) as OperationalMovement
	return _default


## "" when the data is valid, otherwise the first problem found.
func problem() -> String:
	var types := Terrain.Type.size()
	if move_costs.size() != types:
		return "move_costs needs %d entries, has %d" % [types, move_costs.size()]
	for i in move_costs.size():
		if move_costs[i] < 0:
			return "move_costs[%d] is negative" % i
	if road_cost < 1:
		return "road_cost must be at least 1"
	if river_extra_cost < 0:
		return "river_extra_cost is negative"
	return ""


## Movement points of one step from `from` into its neighbour `to`; Terrain.IMPASSABLE when `to`
## is off the map or water. Reads terrain, road links and river links of the grid.
func step_cost(grid: HexGrid, from: Vector2i, to: Vector2i) -> int:
	# Off-map hexes read as water.
	var terrain := grid.get_terrain(to)
	var cost := move_costs[terrain]
	if cost <= 0:
		return Terrain.IMPASSABLE
	if grid.has_road(from, to):
		return road_cost
	if grid.is_river(to):
		return cost + river_extra_cost
	return cost
