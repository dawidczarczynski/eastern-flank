class_name AttackCommand
extends Command
## Melee attack: the attacker deals max(1, attack - defense) damage to an enemy within range.
## Attacking is allowed once per turn and ends the attacker's movement.

var attacker_id: int
var target_id: int


func _init(p_attacker_id: int, p_target_id: int) -> void:
	attacker_id = p_attacker_id
	target_id = p_target_id


func validate(state: GameState) -> String:
	if state.winner != -1:
		return "game_over"
	var attacker := state.get_unit(attacker_id)
	var target := state.get_unit(target_id)
	if attacker == null or not attacker.is_alive() or target == null or not target.is_alive():
		return "unit_not_found"
	if attacker.owner_id != state.current_player:
		return "not_your_unit"
	return _combat_rule_violation(attacker, target)


## Rules of the attack itself, checked once both units exist and the attacker may act.
func _combat_rule_violation(attacker: Unit, target: Unit) -> String:
	if target.owner_id == attacker.owner_id:
		return "not_an_enemy"
	if attacker.has_attacked:
		return "already_attacked"
	if Hex.distance(attacker.coord, target.coord) > attacker.definition.attack_range:
		return "out_of_range"
	return ""


func apply(state: GameState) -> Array[Dictionary]:
	var attacker := state.get_unit(attacker_id)
	var target := state.get_unit(target_id)
	var damage := maxi(1, attacker.definition.attack - target.definition.defense)
	target.hp = maxi(0, target.hp - damage)
	attacker.has_attacked = true
	attacker.moves_left = 0
	var events: Array[Dictionary] = [
		{
			"type": &"unit_attacked",
			"attacker_id": attacker_id,
			"target_id": target_id,
			"damage": damage,
			"target_hp": target.hp,
		},
	]
	if not target.is_alive():
		events.append({"type": &"unit_died", "unit_id": target_id})
		if _players_with_units(state) == [attacker.owner_id]:
			state.winner = attacker.owner_id
			events.append({"type": &"game_over", "winner": state.winner})
	return events


func _players_with_units(state: GameState) -> Array[int]:
	var result: Array[int] = []
	for player in state.player_count:
		if not state.units_of(player).is_empty():
			result.append(player)
	return result
