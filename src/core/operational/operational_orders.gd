class_name OperationalOrders
extends RefCounted
## Checks shared by the order commands (TASK-092d).


## The common rejection reason: battle_pending, formation_not_found or not_your_formation;
## "" when `formation_id` names a formation of the current player.
static func formation_problem(state: OperationalState, formation_id: StringName) -> String:
	if not state.pending_battles.is_empty():
		return "battle_pending"
	var formation := state.get_formation(formation_id)
	if formation == null:
		return "formation_not_found"
	if formation.owner_id != state.current_player:
		return "not_your_formation"
	return ""


## Move points a formation spends per turn on an order: `posture.budget(move_points)` scaled by
## its readiness (at least `readiness_floor` %), rounded down, at least 1 (TASK-095). The one
## helper used by the route forecast (IssueOrderCommand) and by order execution.
static func budget(
	formation: Formation, posture: OperationalPosture, settings: AftermathSettings = null
) -> int:
	if settings == null:
		settings = AftermathSettings.shipped()
	var share := maxi(settings.readiness_floor, formation.readiness)
	return maxi(1, posture.budget(formation.definition.move_points) * share / 100)
