class_name RealParcelLook
extends Resource
## The look numbers of the real field parcels (TASK-215b, ADR 0032; RealParcels, ParcelFill,
## TerrainGround, ScatterPlanner.plan_hedges), kept as data/fields/real_parcels.tres. Look data
## only: the simulation never reads it.

const DEFAULT_PATH := "res://data/fields/real_parcels.tres"

## OSM polygons larger than this are cut across their long axis into parcels of equal area
## (ceil(area / large_parcel_ha)).
@export var large_parcel_ha: float = 5.0
## Open land without an OSM polygon is filled with procedural parcels (ParcelFill): field systems
## of a jittered grid of fill_cell_m (jitter as a share of it), each with one direction (the nearest
## OSM parcel's, else hashed), recursively split across their longer side into parcels of about
## fill_target_ha (x 1 +- fill_size_spread); pieces under min_parcel_ha are dropped.
@export var fill_cell_m: float = 650.0
@export_range(0.0, 0.5) var fill_jitter: float = 0.35
@export var fill_target_ha: float = 4.0
@export_range(0.0, 0.9) var fill_size_spread: float = 0.6
@export var min_parcel_ha: float = 0.15
## Share of the field system borders and of the inner parcel splits that carry a hedge (balk and
## a tree line).
@export_range(0.0, 1.0) var system_hedge_share: float = 0.7
@export_range(0.0, 1.0) var split_hedge_share: float = 0.3
## Width (m) of the pale balk drawn along a track edge.
@export var track_m: float = 7.0
## Tree line along the hedges (ScatterPlanner.plan_hedges): one item every hedge_step_m, a gap
## with hedge_gap_chance, a tree (else a shrub) with hedge_tree_chance.
@export var hedge_step_m: float = 12.0
@export_range(0.0, 1.0) var hedge_gap_chance: float = 0.2
@export_range(0.0, 1.0) var hedge_tree_chance: float = 0.7
## Satellite colour on a real parcel: the share of the layer's hue (at the crop's luminance) at
## every distance, instead of the layer's own colour far away (which blurs the edges and washes
## out the contrast); and the crop tint / saturation of the `true` look while real parcels show.
@export_range(0.0, 1.0) var satellite_hue: float = 0.15
@export_range(0.0, 1.0) var crop_tint: float = 0.12
@export var crop_saturation: float = 1.2


## The shipped look (ResourceLoader caches it).
static func load_default() -> RealParcelLook:
	return load(DEFAULT_PATH) as RealParcelLook
