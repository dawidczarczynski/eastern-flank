class_name TerrainViewSetup
extends RefCounted
## The devtools terrain viewer (docs/TOOLS.md): a BattleSetup that is only a piece of real
## terrain – the same cut of the theatre's tactical layer a contact battle fights on (ContactMap,
## ContactSettings width x height) centred on one operational hex, with no companies and no
## objectives. Pure: it reads data and returns a new setup; nothing is drawn from any RNG.

## Seed of the view (only the map's decoration reads it).
const SEED := 11


## The terrain around operational hex `hex` of the theatre `map_id`; null (with push_error) when
## the theatre or its tactical layer is missing or the hex is outside the theatre.
static func build(map_id: StringName, hex: Vector2i) -> BattleSetup:
	var settings := ContactSettings.shipped()
	var theatre := ImportedMap.find(map_id)
	var layer := TacticalLayer.find(settings.layer_for(map_id))
	if theatre == null or layer == null:
		push_error("TerrainViewSetup: no theatre map or tactical layer for '%s'" % map_id)
		return null
	return build_with(map_id, hex, theatre, layer, settings)


static func build_with(
	map_id: StringName,
	hex: Vector2i,
	theatre: ImportedMap,
	layer: TacticalLayer,
	settings: ContactSettings
) -> BattleSetup:
	var centre := ContactMap.centre_tile(hex, hex, theatre, layer)
	var region := ContactMap.region_around(
		centre, Vector2i(layer.width, layer.height), Vector2i(settings.width, settings.height)
	)
	if region.size == Vector2i.ZERO:
		push_error("TerrainViewSetup: layer '%s' is smaller than the cut" % layer.id)
		return null
	var setup := BattleSetup.new()
	setup.seed = SEED
	setup.map_id = layer.id
	setup.map_region = region
	var offset := MapGenerator.axial_to_offset(hex)
	setup.operation_name = "Terrain %d, %d" % [offset.x, offset.y]
	setup.factions = FactionRegistry.DEFAULT_IDS.duplicate()
	setup.conditions = [BattleSetup.Conditions.new(), BattleSetup.Conditions.new()]
	setup.objectives = BattleObjectives.new()
	return setup
