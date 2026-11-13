class_name OperationObjective
extends Resource
## A victory objective of an operation (TASK-107a, GDD "Sides" Victory): a hex or an installation
## worth `points` at the end of the operation. Kept on OperationDefinition.objectives; the AI goals
## (AiGoal.objective_id) reuse the same hexes, so there is one source of truth.

## The points go to `side` while it holds the hex.
const OWN_SIDE := &"own_side"
## The points go to whoever holds the hex at the end (`side` is ignored).
const ANY := &"any"
const HOLDER_RULES: Array[StringName] = [OWN_SIDE, ANY]

## Unique id within the operation, e.g. &"grodno".
@export var id: StringName
## Translation key (English).
@export var display_name: String
## Id of an installation whose hex is the objective; &"" = the objective is `coord`.
@export var installation_id: StringName = &""
## The objective hex when `installation_id` is empty.
@export var coord: Vector2i = Vector2i.ZERO
## The side that scores it (`own_side` rule); -1 for `any`.
@export var side: int = -1
## Points at the end of the operation (> 0).
@export var points: int = 1
## `own_side` or `any`.
@export var holder_rule: StringName = OWN_SIDE


## The objective hex in `state`; Vector2i.MAX when the installation is unknown.
func hex_in(state: OperationalState) -> Vector2i:
	if installation_id == &"":
		return coord
	var installation := state.get_installation(installation_id)
	return Vector2i.MAX if installation == null else installation.coord


## The side that scores the objective when `holder` holds its hex: -1 when nobody does.
func scorer(holder: int) -> int:
	if holder != 0 and holder != 1:
		return -1
	if holder_rule == ANY:
		return holder
	return holder if holder == side else -1
