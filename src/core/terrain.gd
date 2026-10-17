class_name Terrain
extends RefCounted
## Terrain types. Each enum value maps to a TerrainDefinition in data/terrain/*.tres,
## which is the source of truth for move cost, defense bonus and look.

enum Type { PLAINS, FOREST, HILLS, WATER }

const IMPASSABLE := -1

## Keep in sync with Type. load() (cached) instead of preload(): a preloaded const
## resolved to a plain Resource due to the circular Terrain <-> TerrainDefinition reference.
const _PATHS: Dictionary = {
	Type.PLAINS: "res://data/terrain/plains.tres",
	Type.FOREST: "res://data/terrain/forest.tres",
	Type.HILLS: "res://data/terrain/hills.tres",
	Type.WATER: "res://data/terrain/water.tres",
}

## Loaded definitions. load() goes through the resource cache by path on every call, which is
## slow enough to matter in pathfinding (move_cost per neighbour): ~19 ms per HexGrid search.
static var _definitions: Dictionary = {}  # Type -> TerrainDefinition


static func definition(t: Type) -> TerrainDefinition:
	if not _definitions.has(t):
		_definitions[t] = load(_PATHS[t] as String) as TerrainDefinition
	return _definitions[t]


static func move_cost(t: Type) -> int:
	var def := definition(t)
	return IMPASSABLE if def.impassable else def.move_cost


## Elevation of a tile of type `t` that has no stored elevation (see HexGrid.elevation).
static func default_elevation(t: Type) -> float:
	return definition(t).default_elevation
