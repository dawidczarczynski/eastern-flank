class_name AiPlayer
extends RefCounted
## Simple AI: every unit moves to a firing position (_firing_destination), attacks the enemy it
## can hit with the best expected result (_best_target: CombatForecast expected damage +
## KILL_BONUS x kill chance - expected counter; TASK-089a), then the AI ends the turn.
## Firing positions (TASK-131a, weapon ranges and line of sight): of the reachable hexes (and the
## current one) from which the unit can hit an enemy, it prefers one outside every enemy's reach
## (AttackCommand.fire_problem from where the enemy stands), then the best target score from
## there, then the largest distance to the nearest enemy (it stays at the longest range that
## keeps the full hit chance), then its current hex, then the lowest (y, x). When no reachable
## hex can hit anything, it heads for the nearest hex (hex distance, ties lowest (y, x)) that can.
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
## Firing positions compare target scores rounded to this step (_firing_value).
const _SCORE_PRECISION := 1e-6
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
		if AttackCommand.fire_problem(state, unit.definition, from, other.coord) != "":
			continue
		var faces := AttackCommand.hit_on_at(state, unit, other, Hex.distance(from, other.coord))
		if faces <= 0:
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
	return _firing_destination(state, unit)


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


## Where `unit` moves to fire (see the class comment): the best reachable firing hex, or – when
## none can hit an enemy – the reachable hex closest to the nearest hex that can.
func _firing_destination(state: GameState, unit: Unit) -> Vector2i:
	var enemies := _enemies(state, unit)
	var reach := state.grid.reachable(unit.coord, unit.moves_left, state.occupied())
	var candidates: Array[Vector2i] = [unit.coord]
	for c: Vector2i in reach.keys():
		candidates.append(c)
	var forecasts := {}
	var best: Variant = null
	var best_key: Array = []
	for c in candidates:
		var value: Variant = _firing_value(state, unit, c, enemies, forecasts)
		if value == null:
			continue
		var key := [
			1 if _is_safe(state, c, enemies) else 0,
			value,
			_nearest_distance(c, enemies),
			1 if c == unit.coord else 0,
			-c.y,
			-c.x,
		]
		if best == null or _key_greater(key, best_key):
			best = c
			best_key = key
	if best != null:
		return best
	var goal: Variant = _nearest_firing_hex(state, unit, enemies)
	if goal == null:
		return unit.coord
	return _closest_to(state, unit, goal)


## Living enemies of `unit`'s owner, by id.
func _enemies(state: GameState, unit: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for other: Unit in state.units.values():
		if other.owner_id != unit.owner_id and other.is_alive():
			result.append(other)
	result.sort_custom(func(a: Unit, b: Unit) -> bool: return a.id < b.id)
	return result


## The best target_score `unit` would get firing from `from` (at enemies it can hit with a
## non-zero chance); null when it can hit none. `forecasts` caches the score per enemy, distance
## and counter possibility (all the forecast depends on during one decision).
func _firing_value(
	state: GameState, unit: Unit, from: Vector2i, enemies: Array[Unit], forecasts: Dictionary
) -> Variant:
	var best: Variant = null
	for enemy in enemies:
		if AttackCommand.fire_problem(state, unit.definition, from, enemy.coord) != "":
			continue
		var d := Hex.distance(from, enemy.coord)
		if AttackCommand.hit_on_at(state, unit, enemy, d) <= 0:
			continue
		var counter := AttackCommand.fire_problem(state, enemy.definition, enemy.coord, from) == ""
		var cache_key := Vector3i(enemy.id, d, 1 if counter else 0)
		if not forecasts.has(cache_key):
			forecasts[cache_key] = _snap(
				target_score(CombatForecast.compute_at(state, unit, enemy, from))
			)
		var score: float = forecasts[cache_key]
		if best == null or score > best:
			best = score
	return best


## A score rounded to _SCORE_PRECISION steps so that equal forecasts compare equal.
static func _snap(score: float) -> float:
	return roundf(score / _SCORE_PRECISION) * _SCORE_PRECISION


## True when no enemy can fire at `c` from where it stands (range, line of sight).
func _is_safe(state: GameState, c: Vector2i, enemies: Array[Unit]) -> bool:
	for enemy in enemies:
		if AttackCommand.fire_problem(state, enemy.definition, enemy.coord, c) == "":
			return false
	return true


func _nearest_distance(c: Vector2i, enemies: Array[Unit]) -> int:
	var best := _INF
	for enemy in enemies:
		best = mini(best, Hex.distance(c, enemy.coord))
	return best


## Whether sort key `a` beats `b` (element-wise, first difference decides; equal = false).
static func _key_greater(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] > b[i]
	return false


## The nearest passable, free hex (hex distance from `unit`, ties lowest (y, x)) from which the
## unit could hit an enemy; null when there is none on the map.
func _nearest_firing_hex(state: GameState, unit: Unit, enemies: Array[Unit]) -> Variant:
	var occupied := state.occupied()
	var keyed: Array = []
	for c in state.grid.coords():
		if not occupied.has(c) and state.grid.move_cost(c) != Terrain.IMPASSABLE:
			keyed.append([Hex.distance(unit.coord, c), c.y, c.x, c])
	keyed.sort()
	for entry: Array in keyed:
		var c: Vector2i = entry[3]
		for enemy in enemies:
			if (
				AttackCommand.fire_problem(state, unit.definition, c, enemy.coord) == ""
				and AttackCommand.hit_on_at(state, unit, enemy, Hex.distance(c, enemy.coord)) > 0
			):
				return c
	return null


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
## Targets it cannot hurt (no die face hits, e.g. a squad at its maximum range against a tank)
## are skipped. Null when nothing is in range.
func _best_target(state: GameState, unit: Unit) -> Unit:
	var best: Unit = null
	var best_score := 0.0
	# valid_targets is ascending, so keeping the first of equals keeps the lowest id.
	for id: int in AttackCommand.valid_targets(state, unit.id):
		var other := state.get_unit(id)
		var forecast := AttackCommand.forecast(state, unit, other)
		if forecast.hit_on <= 0:
			continue
		var score := target_score(forecast)
		# Scores within _SCORE_EPSILON tie: forecasts summed over different HP differ in the last bits.
		var tie := absf(score - best_score) <= _SCORE_EPSILON
		if best == null or (score > best_score and not tie) or (tie and other.hp < best.hp):
			best = other
			best_score = score
	return best


## Expected value of an attack: damage dealt + KILL_BONUS x kill chance - damage taken back.
static func target_score(forecast: CombatForecast) -> float:
	return forecast.expected_damage + KILL_BONUS * forecast.kill_chance - forecast.counter_expected
