class_name TerrainDefinition
extends Resource
## Static data for a terrain type. Instances are kept as .tres files in data/terrain/.
## Only gameplay data: the view derives terrain looks from type and elevation (TerrainSplat).

@export var id: StringName
@export var display_name: String
@export var move_cost: int = 1
@export var impassable: bool = false
## Flat bonus added to the defense of a unit standing on this terrain.
@export var defense_bonus: int = 0
## Elevation of a tile of this type when the map has no generated elevation
## (hand-made/test grids). Generated maps store per-tile elevation in HexGrid.
@export var default_elevation: float = 0.2
