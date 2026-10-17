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


static func definition(t: Type) -> TerrainDefinition:
	return load(_PATHS[t] as String) as TerrainDefinition


static func move_cost(t: Type) -> int:
	var def := definition(t)
	return IMPASSABLE if def.impassable else def.move_cost
