class_name TerrainFeatures
extends Resource
## Rule numbers of the linear map features (TASK-108): roads and rivers, stored per tile as 6-bit
## link masks in HexGrid (bit i = a link towards tile + Hex.DIRECTIONS[i]). One instance:
## data/terrain/features.tres, loaded by Terrain.features().

## Cost of a step from A to B when A has a road link towards B, whatever B's terrain
## (an impassable B stays impassable).
@export var road_move_cost: int = 1
## Added to the terrain cost when entering a river hex (a tile with a river link), unless the
## step follows a road link (a bridge). Leaving a river hex costs nothing extra.
@export var river_extra_cost: int = 1
