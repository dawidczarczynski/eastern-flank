class_name BattleCover
extends RefCounted
## The land cover (TASK-108g, LandCover) under a battle the view is about to build: the battle's
## map (BattleSetup.map_id / map_region, or the map of a named scenario) with a margin wide
## enough for the off-map margin and the backdrop ring around the playable mesh, so they continue
## the real land cover beyond the cut. Generated maps get LandCover's fallback (no raster: the
## view keeps its hex-type look). Read-only; GameState does not know its map id, so the view
## asks here.

## World units of land cover around the cut: MapView's off-map margin, its backdrop ring and a
## little more for the backdrop scatter.
const MARGIN := MapView.EXTENT + MapView.BACKDROP_WIDTH + 2.0


## The cover of the battle of `setup` (when set) or of the scenario `scenario_name` (seed
## `seed_value`) whose rules grid is `grid`. Never null.
static func for_battle(
	setup: BattleSetup, scenario_name: String, seed_value: int, grid: HexGrid
) -> LandCover:
	var where := battle_map(setup, scenario_name, seed_value)
	return LandCover.for_map(where[0], where[1], grid, MARGIN)


## The satellite colour layer (TASK-192b, SatelliteColour) of the same battle and margin; null
## when its map has none or the `true` VisualScale preset is off.
static func colour_for_battle(
	setup: BattleSetup, scenario_name: String, seed_value: int
) -> SatelliteColour:
	var where := battle_map(setup, scenario_name, seed_value)
	return SatelliteColour.for_map(where[0], where[1], MARGIN)


## The real field parcels (TASK-215b, RealParcels) of the battle's imported map; null when the map
## has no parcel polygons (generated maps, tactical layers) or the `true` VisualScale preset is
## off (`balanced` keeps the procedural strips).
static func parcels_for_battle(
	setup: BattleSetup, scenario_name: String, seed_value: int
) -> RealParcels:
	var where := battle_map(setup, scenario_name, seed_value)
	if not VisualScale.is_true_size() or where[0] == BattleSetup.MAP_GENERATED_RIVER:
		return null
	if TacticalLayer.find(where[0]) != null:
		return null
	return RealParcels.from_imported(ImportedMap.find(where[0]))


## [map id (StringName), map region (Rect2i)] of the battle of `setup` or of the scenario.
static func battle_map(setup: BattleSetup, scenario_name: String, seed_value: int) -> Array:
	var map_id := BattleSetup.MAP_GENERATED_RIVER
	var region := Rect2i()
	if setup != null:
		map_id = setup.map_id
		region = setup.map_region
	elif scenario_name == "suwalki_battle":
		map_id = Scenario.SUWALKI_MAP_ID
	elif scenario_name == "contact_battle":
		var contact := Scenario.contact_battle_setup(seed_value)
		if contact != null:
			map_id = contact.map_id
			region = contact.map_region
	return [map_id, region]
