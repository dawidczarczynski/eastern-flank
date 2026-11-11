class_name AttackCommand
extends Command
## Attack on an enemy within range. Per-element rolls (TASK-089a, GDD "Combat"): each strength
## point (HP) of the striker rolls a die with max_hp faces on GameState.rng and hits on a roll
## <= hit_on(); damage = the number of hits (0 is possible). Range (TASK-131a): a shot is legal
## at min_hexes <= distance <= max_hexes and, for direct fire, with LineOfSight (fire_problem);
## beyond the effective range the hit chance falls linearly to 50 % at the maximum range
## (hit_faces). A full-strength company within its effective range therefore deals
## compute_damage() on average.
## Attacking is allowed once per turn and ends the attacker's movement.
## A surviving target that can fire back at the attacker (fire_problem) counters once with the
## HP it has left (see apply()) – unless the strike already ended the battle. Each strike is
## followed by BattleRules.after_strike. forecast() gives the exact odds without touching the rng.

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


## Every grid coordinate the unit could hit from where it stands (fire_problem is ""), own tile
## excluded.
static func tiles_in_range(state: GameState, unit: Unit) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c in state.grid.coords():
		if c != unit.coord and fire_problem(state, unit.definition, unit.coord, c) == "":
			result.append(c)
	return result


## Why a unit of `definition` standing on `from` cannot fire at the hex `to`: "out_of_range"
## (distance > max_hexes), "too_close" (distance < min_hexes) or "no_line_of_sight" (direct
## fire, LineOfSight); "" when it can.
static func fire_problem(
	state: GameState, definition: UnitDefinition, from: Vector2i, to: Vector2i
) -> String:
	var d := Hex.distance(from, to)
	if d > definition.max_hexes():
		return "out_of_range"
	if d < definition.min_hexes():
		return "too_close"
	if not definition.is_indirect() and not LineOfSight.visible(state.grid, from, to):
		return "no_line_of_sight"
	return ""


## Faces of a d(max_hp) that hit: the rolls with roll * 2 * span <= base * (2 * span - over),
## span = max_hexes - effective_hexes, over = max(0, distance - effective_hexes) (full chance
## up to the effective range, half at the maximum). span 0 = no falloff: rolls <= base.
## Integer maths only, capped to 0 … max_hp.
@warning_ignore("integer_division")
static func hit_faces(base: int, max_hp: int, span: int, over: int) -> int:
	if span <= 0 or over <= 0:
		return clampi(base, 0, max_hp)
	return clampi(base * (2 * span - over) / (2 * span), 0, max_hp)


## Share of the full hit chance left at hex distance `distance` (1.0 up to the effective range,
## 0.5 at the maximum) – what hit_faces applies before rounding down.
static func range_factor(definition: UnitDefinition, distance: int) -> float:
	var span := definition.max_hexes() - definition.effective_hexes()
	var over := maxi(0, distance - definition.effective_hexes())
	if span <= 0 or over <= 0:
		return 1.0
	return float(2 * span - over) / (2 * span)


## Attack margin max(1, attack - (defense + defender's position bonus + terrain defense bonus of
## the defender's tile)): the average damage of a full-strength attacker. The
## attacker's own tile is ignored.
static func compute_damage(state: GameState, attacker: Unit, defender: Unit) -> int:
	var defense := (
		defender.definition.defense
		+ state.position_bonus_per_player[defender.owner_id]
		+ state.grid.defense_bonus(defender.coord)
	)
	return maxi(1, attacker.definition.attack - defense)


## A roll of the striker's d(max_hp) at or below this value hits the victim at their current
## distance: hit_faces(compute_damage(), …) – min(compute_damage(), max_hp) within the
## effective range.
static func hit_on(state: GameState, striker: Unit, victim: Unit) -> int:
	return hit_on_at(state, striker, victim, Hex.distance(striker.coord, victim.coord))


## hit_on as if the two units stood `distance` hexes apart.
static func hit_on_at(state: GameState, striker: Unit, victim: Unit, distance: int) -> int:
	var definition := striker.definition
	return hit_faces(
		AttackCommand.compute_damage(state, striker, victim),
		definition.max_hp,
		definition.max_hexes() - definition.effective_hexes(),
		maxi(0, distance - definition.effective_hexes())
	)


## Rolls one strike: exactly striker.hp calls of state.rng.randi_range(1, striker max_hp), all of
## them whatever the results; returns the number of hits (before clamping the victim's HP).
static func roll_hits(state: GameState, striker: Unit, victim: Unit) -> int:
	var die := striker.definition.max_hp
	var target := AttackCommand.hit_on(state, striker, victim)
	var hits := 0
	for i in striker.hp:
		if state.rng.randi_range(1, die) <= target:
			hits += 1
	return hits


## Exact odds of the attacker's strike on the defender and of the counter (CombatForecast).
## Pure: never touches the rng or the units.
static func forecast(state: GameState, attacker: Unit, defender: Unit) -> CombatForecast:
	return CombatForecast.compute(state, attacker, defender)


func to_dict() -> Dictionary:
	return {"type": "attack", "attacker_id": attacker_id, "target_id": target_id}


func validate(state: GameState) -> String:
	if state.is_over():
		return "game_over"
	var attacker := state.get_unit(attacker_id)
	var target := state.get_unit(target_id)
	if attacker == null or not attacker.is_alive() or target == null or not target.is_alive():
		return "unit_not_found"
	if attacker.owner_id != state.current_player:
		return "not_your_unit"
	if not state.can_activate(attacker):
		return "no_command_points"
	return _combat_rule_violation(state, attacker, target)


## Rules of the attack itself, checked once both units exist and the attacker may act.
func _combat_rule_violation(state: GameState, attacker: Unit, target: Unit) -> String:
	if target.owner_id == attacker.owner_id:
		return "not_an_enemy"
	if attacker.has_attacked:
		return "already_attacked"
	return fire_problem(state, attacker.definition, attacker.coord, target.coord)


func apply(state: GameState) -> Array[Dictionary]:
	var attacker := state.get_unit(attacker_id)
	var target := state.get_unit(target_id)
	attacker.has_attacked = true
	attacker.moves_left = 0
	var activation := state.activate(attacker)
	var events := _strike(state, attacker, target, false)
	# command_points_changed (first activation of a limited player) follows the first unit_attacked.
	for i in activation.size():
		events.insert(1 + i, activation[i])
	# A surviving target that can fire back (range, line of sight) hits back once, rolling the
	# HP it has left. It is not an action: the target's has_attacked / moves_left are untouched
	# and a counter never provokes another counter.
	if (
		target.is_alive()
		and not state.is_over()
		and fire_problem(state, target.definition, target.coord, attacker.coord) == ""
	):
		events.append_array(_strike(state, target, attacker, true))
	return events


## One strike: rolls (roll_hits), applies the damage and returns unit_attacked (+ unit_died,
## + game_over when BattleRules ends the battle).
func _strike(state: GameState, striker: Unit, victim: Unit, is_counter: bool) -> Array[Dictionary]:
	var shots := striker.hp
	var damage := AttackCommand.roll_hits(state, striker, victim)
	victim.hp = maxi(0, victim.hp - damage)
	var events: Array[Dictionary] = [
		{
			"type": &"unit_attacked",
			"attacker_id": striker.id,
			"target_id": victim.id,
			"shots": shots,
			"damage": damage,
			"target_hp": victim.hp,
			"counter": is_counter,
		},
	]
	var died := not victim.is_alive()
	if died:
		events.append({"type": &"unit_died", "unit_id": victim.id})
	events.append_array(BattleRules.after_strike(state, striker.owner_id, died))
	return events
