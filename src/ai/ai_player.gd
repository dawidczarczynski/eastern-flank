class_name AiPlayer
extends RefCounted
## Simple AI: every unit moves as close as possible to the nearest enemy, attacks the weakest
## enemy in range (if any), then the AI ends the turn.
## Acts only through commands – the same rules as for the player.

const _INF := 1 << 30


func take_turn(sim: GameSimulation) -> void:
	var state := sim.state
	for unit in state.units_of(state.current_player):
		if state.winner != -1:
			return
		if not unit.is_alive():
			continue
		var enemy := _nearest_enemy(state, unit)
		if enemy == null:
			continue
		var reach := state.grid.reachable(unit.coord, unit.moves_left, state.occupied())
		var best := unit.coord
		var best_dist := Hex.distance(best, enemy.coord)
		for c: Vector2i in reach.keys():
			var d := Hex.distance(c, enemy.coord)
			if d < best_dist:
				best = c
				best_dist = d
		if best != unit.coord:
			sim.execute(MoveUnitCommand.new(unit.id, best))
		var target := _weakest_enemy_in_range(state, unit)
		if target != null:
			sim.execute(AttackCommand.new(unit.id, target.id))
	if state.winner != -1:
		return
	sim.execute(EndTurnCommand.new())


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
