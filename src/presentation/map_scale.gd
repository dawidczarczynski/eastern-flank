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


## Metres per world unit of a battle's map (BattleSetup.map_id): a theatre's tactical layer or an
## imported map gives its own scale (250 m hexes -> 144.34), the generated map the default.
static func for_map_id(map_id: StringName) -> float:
	if map_id != BattleSetup.MAP_GENERATED_RIVER:
		var layer := TacticalLayer.find(map_id)
		if layer != null:
			return layer.metres_per_world_unit()
		var imported := ImportedMap.find(map_id)
		if imported != null:
			return imported.metres_per_world_unit()
	return DEFAULT_METRES_PER_UNIT


## Makes the scale of a battle's map the active one (before MapView builds it).
static func apply_map_id(map_id: StringName) -> void:
	metres_per_unit = for_map_id(map_id)


static func reset() -> void:
	metres_per_unit = DEFAULT_METRES_PER_UNIT
