class_name StrikeCommand
extends OperationalCommand
## A deep strike by the current player (TASK-097a, GDD "Deep strikes"): a salvo of one means at an
## enemy installation or formation. Rejections, in order: battle_pending, unknown_means,
## bad_count, out_of_stock, no_strikes_left, then StrikeRules.target_problem (unknown_target,
## target_destroyed, own_soil, closed_country, roe_class, out_of_range). Every accepted strike is
## an escalation incident, whatever its result. Draws 2 x count values from `state.rng`.

const TYPE := "strike"

var means_id: StringName
var target_id: StringName
var count: int


func _init(p_means_id: StringName = &"", p_target_id: StringName = &"", p_count: int = 1) -> void:
	means_id = p_means_id
	target_id = p_target_id
	count = p_count


func validate(state: OperationalState) -> String:
	var player := state.current_player
	if not state.pending_battles.is_empty():
		return "battle_pending"
	var means: StrikeMeansDefinition = state.strike_means.get(means_id)
	if means == null:
		return "unknown_means"
	if count < 1 or count > means.max_salvo:
		return "bad_count"
	if StrikeRules.stock(state, player, means_id) < count:
		return "out_of_stock"
	if state.strikes_left < 1:
		return "no_strikes_left"
	return StrikeRules.target_problem(state, player, target_id, means_id)


func apply(state: OperationalState) -> Array[Dictionary]:
	var player := state.current_player
	var target := StrikeRules.find_target(state, player, target_id)
	var coord: Vector2i = target["coord"]
	var means: StrikeMeansDefinition = state.strike_means[means_id]
	var origin := StrikeRules.launch_origin(state, player, means_id, coord)
	var events: Array[Dictionary] = [StrikeRules.spend(state, player, means_id, count)]
	state.strikes_left -= 1
	(
		events
		. append(
			{
				"type": &"strike_launched",
				"player": player,
				"means": means_id,
				"count": count,
				"target": target_id,
				"coord": coord,
				"class_id": target["class_id"],
				"launcher_kind": String(means.launcher_kind),
				"origin": origin,
			}
		)
	)
	events.append_array(StrikeRules.resolve(state, player, means_id, target, count))
	events.append_array(EscalationRules.on_strike(state, player, coord))
	return events


func to_dict() -> Dictionary:
	return {
		"type": TYPE,
		"means": String(means_id),
		"target": String(target_id),
		"count": count,
	}
