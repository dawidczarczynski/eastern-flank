class_name MapScale
extends RefCounted
## Real-world scale of the map (TASK-108e; TASK-108b/110 reuse it): how many metres one world
## unit (TerrainField.HEX_SIZE, hex centre to corner) is. Look constants given in metres are
## converted with `to_units`. The default is the 250 m tactical hex (250 / sqrt(3) = 144.34 m per
## unit), which is also the scale of the imported Suwalki map (ImportedMap.metres_per_world_unit),
## so nothing has to set it yet; whoever builds a map of another scale assigns `metres_per_unit`
## before MapView builds it.

const DEFAULT_METRES_PER_UNIT := 250.0 / Hex.SQRT3

static var metres_per_unit := DEFAULT_METRES_PER_UNIT


## World units of `metres`.
static func to_units(metres: float) -> float:
	return metres / metres_per_unit


static func reset() -> void:
	metres_per_unit = DEFAULT_METRES_PER_UNIT
