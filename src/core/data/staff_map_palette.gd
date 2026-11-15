class_name StaffMapPalette
extends Resource
## Colours, line widths, zoom levels and relief of the staff map (TASK-093a, TASK-125, flat glow
## look since 2026-11-15; reference:
## docs/design/operational_map/README.md; names follow its
## "map.land", "road.t1" … keys with "_" for "."). One resource,
## data/operational/staff_map_palette.tres; the scene has no colour literals. Line widths are
## screen pixels per zoom level [Z0, Z1, Z2]; 0 = not drawn at that level.

const PATH := "res://data/operational/staff_map_palette.tres"
## Fill class of sea water (lakes keep Terrain.Type.WATER), see StaffMapLayers.sea_tiles.
const SEA := 100

@export_group("Map")
@export var map_void := Color("#06090c")
@export var map_land := Color("#0b1015")
@export var map_forest := Color("#0b1015")
@export var map_forest_edge := Color("#2b3d31", 0.0)
@export var map_urban := Color("#161c23")
@export var map_urban_edge := Color("#8d9585", 0.0)
## Marsh: land with a hatch of this colour (7 x 5 px tile, one 1 px dash per tile).
@export var map_marsh := Color("#0b1015")
@export var marsh_hatch_tile := Vector2(7.0, 5.0)

@export_group("Water")
@export var water_sea := Color("#06090c")
@export var water_lake := Color("#0a141b")
@export var water_shore := Color("#6fa7d8")
@export var water_label := Color("#6f95ab")
## Water below this height (metres) connected to the map edge is sea, the rest lakes.
@export var sea_max_m := 5.0

@export_group("Lines")
@export var river_major := Color("#5384a0")
@export var river_named := Color("#46728c")
@export var river_minor := Color("#3a5c70")
@export var road_t1 := Color("#b4ac98")
@export var road_t1_casing := Color("#0d100d", 0.0)
@export var road_t2 := Color("#7f7a6c")
@export var road_t3 := Color("#55534a")
@export var rail := Color("#70746b")
@export var border := Color("#a9afa1")
@export var road_t1_widths := PackedFloat32Array([1.4, 1.6, 2.0])
## Extra casing width around road t1 (both sides together), pixels.
@export var road_t1_casing_px := 2.0
@export var road_t2_widths := PackedFloat32Array([0.0, 1.3, 1.6])
@export var road_t3_widths := PackedFloat32Array([0.0, 0.0, 0.9])
@export var rail_widths := PackedFloat32Array([0.0, 1.0, 1.0])
@export var river_major_widths := PackedFloat32Array([1.6, 1.8, 2.4])
@export var river_named_widths := PackedFloat32Array([0.0, 1.4, 1.8])
@export var river_minor_widths := PackedFloat32Array([0.0, 0.0, 1.2])
## Land-cover edges and the shore line, pixels on every level.
@export var edge_widths := PackedFloat32Array([1.6, 1.6, 1.6])
## Road / river classes from the link data (no OSM classes yet, TASK-112): a road stroke (chain
## of links continued straight through junctions) at least this long is t1 / t2, shorter ones
## t3; rivers likewise major / named / minor. Tuned on the Suwalki theatre (17 000 km of road
## links): t1 ~20 %, t2 ~40 %, t3 the rest; rivers major ~25 %, named ~25 %.
@export var road_t1_min_km := 100.0
@export var road_t2_min_km := 40.0
@export var river_major_min_km := 80.0
@export var river_named_min_km := 40.0
## Chaikin passes on roads and rivers.
@export var smoothing := 2

@export_group("Sides and UI")
@export var side_own := Color("#5b93d6")
@export var side_own_ink := Color("#0f1a26")
@export var side_enemy := Color("#d76a52")
@export var side_enemy_ink := Color("#2a110b")
@export var side_neutral := Color("#a8a598")
@export var ui_amber := Color("#e8b04a")
@export var ui_text := Color("#dfe5d6")
@export var ui_muted := Color("#8d9585")
@export var ui_alert := Color("#e07c5e")
## Strike outcome tokens (strike result report, docs/design/operational_map): hit = ui.amber,
## intercepted = the water label colour, missed = ui.muted.
@export var outcome_hit := Color("#e8b04a")
@export var outcome_intercepted := Color("#6f95ab")
@export var outcome_miss := Color("#8d9585")
@export var strength_high := Color("#b9d38a")
@export var strength_mid := Color("#e2c069")
@export var label_halo := Color("#111411")
## G grid: ui.text at 12 % on every zoom level.
@export var grid := Color(0.875, 0.898, 0.839, 0.12)
@export var grid_px := 1.0
@export var hover_outline_px := 1.6
@export var hover_fill_alpha := 0.10

@export_group("Zoom levels")
## Z1 starts at this many screen pixels per km, Z2 at the second (the reference's 1.6 / 5 are for
## a continental extent; the 340 km theatre already shows 3-5 px/km in a full window).
@export var zoom_level_px_per_km := Vector2(5.0, 9.0)
## A level changes only when the threshold is passed by this fraction (both ways).
@export var zoom_hysteresis := 0.1
## Seconds a layer takes to fade in / out and lines to change width.
@export var fade_seconds := 0.15

@export_group("Glow")
## "Neon contour" look (docs/design/proposals/staff_map_glow_restyle.html, variant A): the lines
## that matter are drawn with an HDR colour (same hue, lifted to the peak brightness below) and
## the 3D environment's bloom glows everything above the threshold. 1.0 = no glow on that class.
@export var glow_enabled := true
## Brightness (max channel) from which a pixel glows, and the width of the ramp up to full glow.
@export var glow_threshold := 0.6
@export var glow_feather := 0.3
@export var glow_intensity := 2.0
@export var glow_strength := 1.0
@export var glow_coast := 1.3
@export var glow_river_major := 1.2
@export var glow_river_named := 1.0
@export var glow_road_t1 := 1.1
@export var glow_front := 1.8
@export var glow_orders := 1.5

@export_group("Relief")
## Vertical exaggeration of the ground mesh over true scale.
@export var relief_exaggeration := 20.0
## Hillshade: light azimuth (degrees clockwise from north) and altitude, soft-light strength,
## slope exaggeration of the shading (the hexes are 5 km means, real slopes are tiny), contrast of
## the shade value and its gain at the far zoom level Z0.
@export var hillshade_azimuth := 315.0
@export var hillshade_altitude := 38.0
@export var hillshade_strength := 0.0
@export var hillshade_z_factor := 20.0
@export var hillshade_contrast := 1.0
@export var hillshade_far_gain := 1.4


## The ground colour of a fill class (Terrain.Type or SEA); marsh is land under its hatch.
func fill(fill_class: int) -> Color:
	match fill_class:
		Terrain.Type.FOREST:
			return map_forest
		Terrain.Type.URBAN:
			return map_urban
		Terrain.Type.WATER:
			return water_lake
		SEA:
			return water_sea
	return map_land


## The edge line colour of a fill class; transparent = no edge.
func edge(fill_class: int) -> Color:
	match fill_class:
		Terrain.Type.FOREST:
			return map_forest_edge
		Terrain.Type.URBAN:
			return map_urban_edge
		Terrain.Type.WATER, SEA:
			return water_shore
	return Color(0, 0, 0, 0)
