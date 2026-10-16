class_name HexGrid
extends RefCounted
## Map: a set of hex tiles with a terrain type.

const _INF := 1 << 30

var _terrain: Dictionary = {}  # Vector2i -> Terrain.Type


func set_terrain(c: Vector2i, t: Terrain.Type) -> void:
	_terrain[c] = t


func has_tile(c: Vector2i) -> bool:
	return _terrain.has(c)


func get_terrain(c: Vector2i) -> Terrain.Type:
	return _terrain.get(c, Terrain.Type.WATER)


func coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_terrain.keys())
	return result


func move_cost(c: Vector2i) -> int:
	if not has_tile(c):
		return Terrain.IMPASSABLE
	return Terrain.move_cost(get_terrain(c))


## Tiles reachable from `origin` with `budget` movement points (Dijkstra).
## Returns a Vector2i -> path cost dictionary (also contains `origin` with cost 0).
## `blocked` – tiles that can't be entered (e.g. occupied by units).
func reachable(origin: Vector2i, budget: int, blocked: Dictionary = {}) -> Dictionary:
	var costs := {origin: 0}
	var frontier: Array[Vector2i] = [origin]
	while not frontier.is_empty():
		# Maps are small – linear minimum search instead of a heap.
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
				frontier.append(n)
	return costs
