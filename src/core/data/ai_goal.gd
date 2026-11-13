class_name AiGoal
extends Resource
## One objective of the operational AI (TASK-102a, GDD "Operational AI"): a hex or an
## installation of the map with a weight and a role. Kept per side on OperationDefinition.ai_goals;
## a goal may name a victory objective (`objective_id`, TASK-107a) and then takes its hex from it.

const TAKE := &"take"
const HOLD := &"hold"
const ROLES: Array[StringName] = [TAKE, HOLD]

## Unique id within the operation, e.g. &"ru_take_suwalki".
@export var id: StringName
## Id of an OperationObjective whose hex is the goal; &"" = the goal is an installation or `coord`.
@export var objective_id: StringName = &""
## The player (index into OperationDefinition.sides) whose AI pursues this goal.
@export_range(0, 1) var player: int = 0
## Id of an installation whose hex is the goal; &"" = the goal is `coord`.
@export var installation_id: StringName = &""
## The goal hex when `installation_id` is empty.
@export var coord: Vector2i = Vector2i.ZERO
## How much the goal is worth (> 0); scales the AI's score.
@export var weight: int = 1
## `take` (go there) or `hold` (stand on it in the defend posture).
@export var role: StringName = TAKE


## The goal hex in `state`; Vector2i.MAX when the installation is unknown.
func hex_in(state: OperationalState) -> Vector2i:
	if objective_id != &"":
		var objective := state.get_objective(objective_id)
		return Vector2i.MAX if objective == null else objective.hex_in(state)
	if installation_id == &"":
		return coord
	var installation := state.get_installation(installation_id)
	return Vector2i.MAX if installation == null else installation.coord
