class_name InstallationPlacement
extends Resource
## One installation of an operation at its hex (a sub-resource of OperationDefinition, TASK-097a).

## Unique installation id within the operation, e.g. &"nato_airfield_olsztyn".
@export var id: StringName
## Translation key (English), e.g. "Olsztyn-Mazury airfield".
@export var display_name: String
## Installation.CLASSES: airfield, depot, c2 or air_defence.
@export var class_id: StringName
## Owning player (index into OperationDefinition.sides).
@export var owner: int
## Hex, axial coordinates on the operation's map.
@export var coord: Vector2i
## Air-defence type id (AirDefenceDefinition) of an `air_defence` installation; &"" otherwise.
@export var ad_type: StringName = &""
