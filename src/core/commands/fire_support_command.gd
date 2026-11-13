class_name FireSupportCommand
extends Command
## A fire-support mission (TASK-099a, GDD "Battle conditions"): an off-map shooter (artillery /
## air) fires one volley at an enemy company the side sees. The volley is one normal per-element
## roll like AttackCommand's – `fire_support_shots` rolls of a `fire_support_die` die against the
## target's defence incl. terrain, position bonus and Dig in – drawn from GameState.rng. No
## counter-fire and no command point. A side has `GameState.fire_support_left` missions per battle
## and may call at most one per turn.

var player: int
var target_id: int


func _init(p_player: int, p_target_id: int) -> void:
	player = p_player
	target_id = p_target_id


## A roll of the volley's die at or below this value hits `target`:
## min(max(1, fire_support_attack - defence), fire_support_die).
static func hit_on(state: GameState, target: Unit, rules: BattleConditionsRules = null) -> int:
	if rules == null:
		rules = BattleConditionsRules.shipped()
	var defence := (
		target.definition.defense
		+ state.position_bonus_per_player[target.owner_id]
		+ state.grid.defense_bonus(target.coord)
		+ OrderRules.defence_bonus(target)
	)
	return mini(maxi(1, rules.fire_support_attack - defence), rules.fire_support_die)


## Whether a living unit of `player` has line of sight to `coord`.
static func seen_by(state: GameState, player: int, coord: Vector2i) -> bool:
	for unit in state.units_of(player):
		if unit.is_alive() and LineOfSight.visible(state.grid, unit.coord, coord):
			return true
	return false


func to_dict() -> Dictionary:
	return {"type": "fire_support", "player": player, "target_id": target_id}


func validate(state: GameState) -> String:
	if state.is_over():
		return "game_over"
	if player != state.current_player:
		return "not_your_turn"
	if state.fire_support_left[player] <= 0:
		return "no_fire_support"
	if state.fire_support_used_turn[player]:
		return "fire_support_used_this_turn"
	return _target_problem(state)


## Why `target_id` is no legal target for the side, "" when it is.
func _target_problem(state: GameState) -> String:
	var target := state.get_unit(target_id)
	var problem := ""
	if target == null:
		problem = "unknown_target"
	elif target.owner_id == player:
		problem = "friendly_target"
	elif not target.is_alive():
		problem = "target_dead"
	elif not FireSupportCommand.seen_by(state, player, target.coord):
		problem = "target_not_visible"
	return problem


func apply(state: GameState) -> Array[Dictionary]:
	var rules := BattleConditionsRules.shipped()
	var target := state.get_unit(target_id)
	state.fire_support_left[player] -= 1
	state.fire_support_used_turn[player] = true
	var needed := FireSupportCommand.hit_on(state, target, rules)
	var hits := 0
	for i in rules.fire_support_shots:
		if state.rng.randi_range(1, rules.fire_support_die) <= needed:
			hits += 1
	target.hp = maxi(0, target.hp - hits)
	var events: Array[Dictionary] = [
		{
			"type": &"fire_support_used",
			"player": player,
			"target_id": target_id,
			"hits": hits,
			"remaining": state.fire_support_left[player],
		},
	]
	var died := not target.is_alive()
	if died:
		events.append({"type": &"unit_died", "unit_id": target_id})
	events.append_array(BattleRules.after_strike(state, player, died))
	return events
