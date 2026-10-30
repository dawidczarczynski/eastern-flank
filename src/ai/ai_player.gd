class_name AiPlayer
extends RefCounted
## Simple AI: every unit moves as close as possible to the nearest enemy, attacks the enemy in
## range with the best expected result (_best_target: CombatForecast expected damage + KILL_BONUS x
## kill chance - expected counter; TASK-089a), then the AI ends the turn.
## Objectives (TASK-088): when the player has TAKE_HEXES / HOLD_HEXES conditions, their hexes are
## goals. A unit standing on one stays there (it still attacks); otherwise, when the nearest goal
## not occupied by an own unit is not farther than the nearest enemy, the unit moves as close to
## that goal as it can. Without such conditions the behaviour is the plain one above.
## With limited command points (TASK-091) the units act best action first (_units_in_order) and
## units that can no longer be activated are skipped; unlimited, the order is by unit id.
## Acts only through commands – the same rules as for the player.

const _INF := 1 << 30
## Weight of the kill chance in the target score (target_score): an AI heuristic, not balance.
const KILL_BONUS := 2.0
## Target scores closer than this count as equal (_best_target falls back to HP, then id).
const _SCORE_EPSILON := 1e-9
## Action scores used to spend limited command points (_action_score).
const _ATTACK_SCORE := 100
const _KILL_SCORE := 100
const _MOVE_SCORE := 10


func take_turn(sim: GameSimulation) -> void:
	var state := sim.state
	var goals := _objective_hexes(state, state.current_player)
	for unit in _units_in_order(state, goals):
		if state.is_over():
			return
		if not unit.is_alive() or not state.can_activate(unit):
			continue
		var best: Variant = _destination(state, unit, goals)
		if best == null:
			continue
		if best != unit.coord:
			sim.execute(MoveUnitCommand.new(unit.id, best))
		var target := _best_target(state, unit)
		if target != null:
			sim.execute(AttackCommand.new(unit.id, target.id))
	if state.is_over():
		return
	sim.execute(EndTurnCommand.new())


## The current player's units in the order they act: by id; when the player has limited command
## points (TASK-091) by descending action score so the points go to the best actions (ties: id).
func _units_in_order(state: GameState, goals: Array[Vector2i]) -> Array[Unit]:
	var units := state.units_of(state.current_player)
	if not state.is_command_limited(state.current_player):
		return units
	var scores := {}
	for unit in units:
		scores[unit.id] = _action_score(state, unit, goals)
	units.sort_custom(
		func(a: Unit, b: Unit) -> bool:
			if scores[a.id] != scores[b.id]:
				return scores[a.id] > scores[b.id]
			return a.id < b.id
	)
	return units


## How much `unit`'s action this turn is worth: an attack it can make (from where it would stand
## after moving) scores ATTACK_SCORE + the damage it deals + KILL_SCORE for a kill; a move
## MOVE_SCORE; nothing to do 0.
func _action_score(state: GameState, unit: Unit, goals: Array[Vector2i]) -> int:
	var dest: Variant = _destination(state, unit, goals)
	if dest == null:
		return 0
	var from: Vector2i = dest
	var best := 0
	for other: Unit in state.units.values():
		if other.owner_id == unit.owner_id or not other.is_alive():
			continue
		if Hex.distance(from, other.coord) > unit.definition.attack_range:
			continue
		var damage := mini(AttackCommand.compute_damage(state, unit, other), other.hp)
		var score := _ATTACK_SCORE + damage + (_KILL_SCORE if damage >= other.hp else 0)
		best = maxi(best, score)
	if best > 0:
		return best
	return _MOVE_SCORE if from != unit.coord else 0


## Where `unit` moves (its own tile = stay); null when it has nothing to do (no enemy, no goal).
func _destination(state: GameState, unit: Unit, goals: Array[Vector2i]) -> Variant:
	if goals.has(unit.coord):
		return unit.coord
	var enemy := _nearest_enemy(state, unit)
	var goal: Variant = _nearest_open_goal(state, unit, goals)
	if goal != null:
		if enemy == null or Hex.distance(unit.coord, goal) <= Hex.distance(unit.coord, enemy.coord):
			return _closest_to(state, unit, goal)
	if enemy == null:
		return null
	var reach := state.grid.reachable(unit.coord, unit.moves_left, state.occupied())
	return _best_destination(unit, enemy, reach)


## Hexes of the player's TAKE_HEXES and HOLD_HEXES conditions, in condition order, no duplicates.
func _objective_hexes(state: GameState, player: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for condition in state.objectives.conditions:
		if condition.uses_hexes() and condition.applies_to(player):
			for c in condition.hexes:
				if not result.has(c):
					result.append(c)
	return result


## Nearest goal without a unit of the unit's owner on it (ties: first in `goals`); null if none.
func _nearest_open_goal(state: GameState, unit: Unit, goals: Array[Vector2i]) -> Variant:
	var best: Variant = null
	var best_dist := _INF
	for c in goals:
		var occupant := state.unit_at(c)
		if occupant != null and occupant.owner_id == unit.owner_id:
			continue
		var d := Hex.distance(unit.coord, c)
		if d < best_dist:
			best = c
			best_dist = d
	return best


## Reachable tile (or the current one) nearest to `goal`; ties keep the current tile, then the
## iteration order of the reach.
func _closest_to(state: GameState, unit: Unit, goal: Vector2i) -> Vector2i:
	var reach := state.grid.reachable(unit.coord, unit.moves_left, state.occupied())
	var best := unit.coord
	var best_dist := Hex.distance(best, goal)
	for c: Vector2i in reach.keys():
		var d := Hex.distance(c, goal)
		if d < best_dist:
			best = c
			best_dist = d
	return best


## Reachable tile (or the current one) closest to the ideal distance from the enemy: the unit's
## attack range. Melee units (range 1) therefore close in as far as possible. Ties prefer
## d <= range, then the current tile, then the iteration order of `reach`.
func _best_destination(unit: Unit, enemy: Unit, reach: Dictionary) -> Vector2i:
	var attack_range := unit.definition.attack_range
	var best := unit.coord
	var best_dist := Hex.distance(best, enemy.coord)
	for c: Vector2i in reach.keys():
		var d := Hex.distance(c, enemy.coord)
		if _is_better(d, best_dist, attack_range):
			best = c
			best_dist = d
	return best


## Whether distance `d` beats `best_d` (strictly) for a unit with the given attack range.
func _is_better(d: int, best_d: int, attack_range: int) -> bool:
	var score := absi(d - attack_range)
	var best_score := absi(best_d - attack_range)
	if score != best_score:
		return score < best_score
	return d <= attack_range and best_d > attack_range


func _nearest_enemy(state: GameState, unit: Unit) -> Unit:
	var best: Unit = null
	var best_dist := _INF
	for other: Unit in state.units.values():
		if other.owner_id == unit.owner_id or not other.is_alive():
			continue
		var d := Hex.distance(unit.coord, other.coord)
		if d < best_dist:
			best = other
			best_dist = d
	return best


## Valid target with the highest target_score; ties: the lowest hp, then the lowest unit id.
## Null when nothing is in range.
func _best_target(state: GameState, unit: Unit) -> Unit:
	var best: Unit = null
	var best_score := 0.0
	# valid_targets is ascending, so keeping the first of equals keeps the lowest id.
	for id: int in AttackCommand.valid_targets(state, unit.id):
		var other := state.get_unit(id)
		var score := target_score(AttackCommand.forecast(state, unit, other))
		# Scores within _SCORE_EPSILON tie: forecasts summed over different HP differ in the last bits.
		var tie := absf(score - best_score) <= _SCORE_EPSILON
		if best == null or (score > best_score and not tie) or (tie and other.hp < best.hp):
			best = other
			best_score = score
	return best


## Expected value of an attack: damage dealt + KILL_BONUS x kill chance - damage taken back.
static func target_score(forecast: CombatForecast) -> float:
	return forecast.expected_damage + KILL_BONUS * forecast.kill_chance - forecast.counter_expected
