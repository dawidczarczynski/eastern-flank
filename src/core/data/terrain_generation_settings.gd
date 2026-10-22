class_name TerrainGenerationSettings
extends Resource
## Numbers of the elevation/moisture terrain generator (TerrainField, MapGenerator).
## They decide the terrain mix, so they are balance data: data/map/terrain_generation.tres.

@export_group("Height")
## Height of flat lowland before hills, mountains, lakes and detail.
@export var base_height: float = 0.2
@export var hills_frequency: float = 0.11
@export var hills_gain: float = 2.4
@export var hills_weight: float = 0.85
## Where mountains may appear (fbm mask smoothed between `from` and `to`).
@export var mountain_mask_frequency: float = 0.05
@export var mountain_mask_from: float = 0.62
@export var mountain_mask_to: float = 0.85
@export var mountain_frequency: float = 0.17
@export var mountain_gain: float = 2.1
## Lakes: fbm smoothed between `from` and `to`, scaled by `lake_depth` and subtracted.
@export var lake_frequency: float = 0.09
@export var lake_from: float = 0.6
@export var lake_to: float = 0.75
@export var lake_depth: float = 1.0
@export var detail_frequency: float = 0.7
@export var detail_amplitude: float = 0.07

@export_group("Moisture")
@export var moisture_frequency: float = 0.13

@export_group("Classification")
## Below → WATER.
@export var water_level: float = 0.02
## Above → HILLS (or FOREST when wetter than `highland_forest_moisture`).
@export var hills_level: float = 0.7
## Lowland wetter than this → FOREST.
@export var forest_moisture: float = 0.61
@export var highland_forest_moisture: float = 0.66

@export_group("Forcing bands")
## Elevation bands that MapGenerator.force_terrain clamps a tile into.
@export var land_min: float = 0.12
@export var land_max: float = 0.7
@export var hills_min: float = 0.71
@export var hills_max: float = 2.2
@export var water_min: float = -0.75
@export var water_max: float = -0.2
