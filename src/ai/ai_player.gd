class_name AiPlayer
extends RefCounted
## Simple AI: every unit moves as close as possible to the nearest enemy, attacks the weakest
## enemy in range (if any), then the AI ends the turn.
## Objectives (TASK-088): when the player has TAKE_HEXES / HOLD_HEXES conditions, their hexes are
## goals. A unit standing on one stays there (it still attacks); otherwise, when the nearest goal
## not occupied by an own unit is not farther than the nearest enemy, the unit moves as close to
## that goal as it can. Without such conditions the behaviour is the plain one above.
## Acts only through commands – the same rules as for the player.

const _INF := 1 << 30


func take_turn(sim: GameSimulation) -> void:
	var state := sim.state
	var goals := _objective_hexes(state, state.current_player)
	for unit in state.units_of(state.current_player):
		if state.is_over():
			return
		if not unit.is_alive():
			continue
		var best: Variant = _destination(state, unit, goals)
		if best == null:
			continue
		if best != unit.coord:
			sim.execute(MoveUnitCommand.new(unit.id, best))
		var target := _weakest_enemy_in_range(state, unit)
		if target != null:
			sim.execute(AttackCommand.new(unit.id, target.id))
	if state.is_over():
		return
	sim.execute(EndTurnCommand.new())


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


## Living enemy within attack range with the lowest hp; ties broken by the lowest unit id.
func _weakest_enemy_in_range(state: GameState, unit: Unit) -> Unit:
	var best: Unit = null
	# valid_targets is ascending, so the strict < keeps the lowest id on hp ties.
	for id: int in AttackCommand.valid_targets(state, unit.id):
		var other := state.get_unit(id)
		if best == null or other.hp < best.hp:
			best = other
	return best
