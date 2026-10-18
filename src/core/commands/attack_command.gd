class_name AttackCommand
extends Command
## Attack: the attacker deals compute_damage() damage to an enemy within range
## (max(1, attack - (defense + terrain defense bonus of the defender's tile))).
## Attacking is allowed once per turn and ends the attacker's movement.
## A surviving target within its own attack range counters once (see apply()).

var attacker_id: int
var target_id: int


func _init(p_attacker_id: int, p_target_id: int) -> void:
	attacker_id = p_attacker_id
	target_id = p_target_id


## Ids of living units the attacker can attack right now, ascending.
## Built on validate(), so every attack rule applies automatically.
static func valid_targets(state: GameState, attacker_id: int) -> Array[int]:
	var result: Array[int] = []
	for unit: Unit in state.units.values():
		if unit.is_alive() and AttackCommand.new(attacker_id, unit.id).validate(state) == "":
			result.append(unit.id)
	result.sort()
	return result


## Every grid coordinate the unit could hit from where it stands: 1 <= distance <= attack_range,
## own tile excluded. Future line-of-sight rules belong here.
static func tiles_in_range(state: GameState, unit: Unit) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c in state.grid.coords():
		var d := Hex.distance(unit.coord, c)
		if d >= 1 and d <= unit.definition.attack_range:
			result.append(c)
	return result


## Damage the attacker would deal to the defender now. The attacker's own tile is ignored.
static func compute_damage(state: GameState, attacker: Unit, defender: Unit) -> int:
	var defense := defender.definition.defense + state.grid.defense_bonus(defender.coord)
	return maxi(1, attacker.definition.attack - defense)


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
	attacker.has_attacked = true
	attacker.moves_left = 0
	var events := _strike(state, attacker, target, false)
	# A surviving target in range hits back once. It is not an action: the target's
	# has_attacked / moves_left are untouched and a counter never provokes another counter.
	if (
		target.is_alive()
		and Hex.distance(target.coord, attacker.coord) <= target.definition.attack_range
	):
		events.append_array(_strike(state, target, attacker, true))
	return events


## One hit: applies damage and returns unit_attacked (+ unit_died, game_over when it ends the game).
func _strike(state: GameState, striker: Unit, victim: Unit, is_counter: bool) -> Array[Dictionary]:
	var damage := AttackCommand.compute_damage(state, striker, victim)
	victim.hp = maxi(0, victim.hp - damage)
	var events: Array[Dictionary] = [
		{
			"type": &"unit_attacked",
			"attacker_id": striker.id,
			"target_id": victim.id,
			"damage": damage,
			"target_hp": victim.hp,
			"counter": is_counter,
		},
	]
	if not victim.is_alive():
		events.append({"type": &"unit_died", "unit_id": victim.id})
		if _players_with_units(state) == [striker.owner_id]:
			state.winner = striker.owner_id
			events.append({"type": &"game_over", "winner": state.winner})
	return events


func _players_with_units(state: GameState) -> Array[int]:
	var result: Array[int] = []
	for player in state.player_count:
		if not state.units_of(player).is_empty():
			result.append(player)
	return result
