class_name HexGrid
extends RefCounted
## Map: a set of hex tiles with a terrain type and an elevation.

const _INF := 1 << 30

## Continuous height field the map was generated from; null for hand-made/test grids.
var field: TerrainField

var _terrain: Dictionary = {}  # Vector2i -> Terrain.Type
var _elevation: Dictionary = {}  # Vector2i -> float


func set_terrain(c: Vector2i, t: Terrain.Type) -> void:
	_terrain[c] = t


func has_tile(c: Vector2i) -> bool:
	return _terrain.has(c)


func get_terrain(c: Vector2i) -> Terrain.Type:
	return _terrain.get(c, Terrain.Type.WATER)


func set_elevation(c: Vector2i, e: float) -> void:
	_elevation[c] = e


## Stored elevation of the tile; if never set, the terrain type's default; 0 off the map.
func elevation(c: Vector2i) -> float:
	if not has_tile(c):
		return 0.0
	if _elevation.has(c):
		return _elevation[c]
	return Terrain.default_elevation(get_terrain(c))


func coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_terrain.keys())
	return result


## Defense bonus of the tile's terrain; 0 off the map.
func defense_bonus(c: Vector2i) -> int:
	if not has_tile(c):
		return 0
	return Terrain.definition(get_terrain(c)).defense_bonus


func move_cost(c: Vector2i) -> int:
	if not has_tile(c):
		return Terrain.IMPASSABLE
	return Terrain.move_cost(get_terrain(c))


## Tiles reachable from `origin` with `budget` movement points (Dijkstra).
## Returns a Vector2i -> path cost dictionary (also contains `origin` with cost 0).
## `blocked` – tiles that can't be entered (e.g. occupied by units).
func reachable(origin: Vector2i, budget: int, blocked: Dictionary = {}) -> Dictionary:
	return _search(origin, budget, blocked)["costs"]


## Cheapest path from `origin` to `target` within `budget` (same search as `reachable`).
## The result excludes `origin` and ends with `target`. Empty when `target == origin`
## or `target` is off the map, impassable, blocked or not reachable within `budget`.
## Ties are broken deterministically by discovery order (`Hex.DIRECTIONS`).
func path_to(
	origin: Vector2i, target: Vector2i, budget: int, blocked: Dictionary = {}
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if target == origin:
		return path
	var parents: Dictionary = _search(origin, budget, blocked)["parents"]
	if not parents.has(target):
		return path
	var current := target
	while current != origin:
		path.append(current)
		current = parents[current]
	path.reverse()
	return path


## Shared Dijkstra. Returns {"costs": Vector2i -> int, "parents": Vector2i -> Vector2i}.
## A parent is replaced only on a strictly lower cost, so the first discovery wins.
func _search(origin: Vector2i, budget: int, blocked: Dictionary) -> Dictionary:
	var costs := {origin: 0}
	var parents := {}
	var frontier: Array[Vector2i] = [origin]
	while not frontier.is_empty():
		# Maps are small – linear minimum search instead of a heap.
		# The first minimum by index is taken, which keeps the search deterministic.
		var best_i := 0
		for i in range(1, frontier.size()):
			if costs[frontier[i]] < costs[frontier[best_i]]:
				best_i = i
		var current: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		for n in Hex.neighbors(current):
			var step := move_cost(n)
			if step == Terrain.IMPASSABLE or blocked.has(n):
				continue
			var new_cost: int = costs[current] + step
			if new_cost <= budget and new_cost < costs.get(n, _INF):
				costs[n] = new_cost
				parents[n] = current
				frontier.append(n)
	return {"costs": costs, "parents": parents}
