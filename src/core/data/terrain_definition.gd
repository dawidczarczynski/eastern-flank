class_name TerrainDefinition
extends Resource
## Static data for a terrain type. Instances are kept as .tres files in data/terrain/.
## Core rules read only the gameplay properties; the "Presentation" group is for the view layer.

@export var id: StringName
@export var display_name: String
@export var move_cost: int = 1
@export var impassable: bool = false
## Flat bonus added to the defense of a unit standing on this terrain.
@export var defense_bonus: int = 0

@export_group("Presentation")
@export var color: Color = Color.WHITE
@export var height: float = 0.2
