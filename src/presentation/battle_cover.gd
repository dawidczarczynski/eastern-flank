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
	return LandCover.for_map(map_id, region, grid, MARGIN)
