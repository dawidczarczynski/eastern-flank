class_name Terrain
extends RefCounted
## Terrain types and their rules.
## Eventually to be moved to data resources (see docs/tasks/BACKLOG.md).

enum Type { PLAINS, FOREST, HILLS, WATER }

const IMPASSABLE := -1


static func move_cost(t: Type) -> int:
	match t:
		Type.PLAINS:
			return 1
		Type.FOREST, Type.HILLS:
			return 2
	return IMPASSABLE
