class_name FormationPlacement
extends Resource
## One named formation of an operation at its start hex (a sub-resource of OperationDefinition).

## Unique formation id within the operation, e.g. &"pl_mech_1".
@export var id: StringName
## Translation key (English), e.g. "1st Mechanised Battalion".
@export var display_name: String
## Brigade / corps label (translation key), e.g. "15th Mechanised Brigade"; no rule reads it.
@export var parent: String
## Owning player (index into OperationDefinition.sides).
@export var player: int
@export var definition: FormationDefinition
## Battle faction the formation fights under (identity: flag, colours); &"" = the side's lead
## faction. Must be one of the side's factions and field the same units as the type's faction.
@export var faction: StringName = &""
## Start hex, axial coordinates on the operation's map.
@export var coord: Vector2i
