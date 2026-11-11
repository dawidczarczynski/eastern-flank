class_name EndOperationalTurnCommand
extends OperationalCommand
## Ends the current player's move on the staff map (TASK-093b): the other player becomes current
## and `turn` rises when the move returns to `first_player` (both blocs move inside one 12 h
## turn). Rejected while a contact battle is waiting to be fought.
## Before the turn ends, the current player's formations carry out their orders (TASK-092e): in
## placement order, each one walks its route as far as its posture's budget allows. Execution
## draws nothing from `state.rng`; afterwards every formation that halted on contact attacks an
## adjacent enemy (ContactRules.start_battles, TASK-094a), which draws one value per battle.

const TYPE := "end_operational_turn"


func validate(state: OperationalState) -> String:
	if not state.pending_battles.is_empty():
		return "battle_pending"
	return ""


func apply(state: OperationalState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ended_before := not state.result.is_empty()
	for formation in state.formations:
		if formation.owner_id == state.current_player and formation.order != null:
			_execute_order(state, formation, events)
			if not ended_before and not state.result.is_empty():
				return events  # the operation ended mid-execution: nothing else happens
	if state.result.is_empty():
		ContactRules.start_battles(state, events)
	events.append({"type": &"operational_turn_ended", "player": state.current_player})
	_switch_side(state)
	events.append_array(BattleConsequences.recover_readiness(state))
	if state.current_player == state.first_player and state.result.is_empty():
		events.append_array(EscalationRules.end_round(state))
		events.append_array(StrikeRules.end_round(state))
	(
		events
		. append(
			{
				"type": &"operational_turn_started",
				"player": state.current_player,
				"turn": state.turn,
			}
		)
	)
	return events


func to_dict() -> Dictionary:
	return {"type": TYPE}


static func _interrupt(formation: Formation, reason: StringName, events: Array[Dictionary]) -> void:
	formation.order = null
	(
		events
		. append(
			{
				"type": &"formation_order_interrupted",
				"formation_id": formation.id,
				"reason": reason,
				"at": formation.coord,
			}
		)
	)


## One formation's order for this turn (see TASK-092e): checks, route, walk, events.
static func _execute_order(
	state: OperationalState, formation: Formation, events: Array[Dictionary]
) -> void:
	var destination := formation.order.destination
	var posture := OperationalPosture.find(formation.posture)
	if OperationalRoutes.destination_closed(state, formation, destination):
		_interrupt(formation, &"closed_country", events)
		return
	var holder := state.formation_at(destination)
	if holder != null and (holder.owner_id == formation.owner_id or posture.avoids_contact):
		_interrupt(formation, &"destination_occupied", events)
		return
	var route := OperationalRoutes.plan(state, formation, destination, posture.avoids_contact)
	if route.is_empty():
		_interrupt(formation, &"no_route", events)
		return
	var budget := OperationalOrders.budget(formation, posture)
	var walk := OperationalRoutes.walk(state, formation, formation.coord, route, budget)
	var steps: Array[Vector2i] = walk["steps"]
	var stop: StringName = walk["stop"]
	if steps.is_empty() and stop == OperationalRoutes.STOP_OUT_OF_POINTS:
		_interrupt(formation, &"blocked", events)
		return
	var walk_from := formation.coord
	if not steps.is_empty():
		var from := formation.coord
		formation.coord = walk["end"]
		(
			events
			. append(
				{
					"type": &"formation_moved",
					"formation_id": formation.id,
					"from": from,
					"to": formation.coord,
					"path": steps,
					"cost": walk["cost"],
				}
			)
		)
	if not steps.is_empty():
		events.append_array(EscalationRules.on_steps(state, formation, steps, walk_from))
	if stop == OperationalRoutes.STOP_ARRIVED:
		formation.order = null
		(
			events
			. append(
				{
					"type": &"formation_order_completed",
					"formation_id": formation.id,
					"destination": destination,
				}
			)
		)
	elif stop == OperationalRoutes.STOP_CONTACT:
		(
			events
			. append(
				{
					"type": &"formation_halted",
					"formation_id": formation.id,
					"at": formation.coord,
					"reason": &"contact",
				}
			)
		)


static func _switch_side(state: OperationalState) -> void:
	state.current_player = 1 - state.current_player
	state.strikes_left = state.strikes_per_turn
	state.decisions_left = state.ladder.decisions_per_turn
	if state.current_player == state.first_player:
		state.turn += 1
