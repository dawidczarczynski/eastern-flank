class_name BattleRules
extends RefCounted
## Victory rules of a battle (TASK-088, ADR 0016) in one place: the commands call these pure
## helpers at fixed points and append the returned events. Every helper returns [] while the
## battle goes on; a battle end sets GameState.winner / end_reason (GameState.finish) and returns
## a `game_over` event {"winner", "reason"}.
##   MoveUnitCommand → capture() after unit_moved (objective ownership).
##   AttackCommand   → after_strike() after each strike, the counter included.
##   EndTurnCommand  → at_turn_end() after turn_ended, before the turn passes.

const REASON_ELIMINATED := &"eliminated"
const REASON_ENEMY_DESTROYED := &"enemy_destroyed"
const REASON_OBJECTIVE_TAKEN := &"objective_taken"
const REASON_TURN_LIMIT := &"turn_limit"


## `unit` ended a move: an objective hex it stands on that another side owns becomes its owner's
## (`objective_captured` {coord, player, previous_owner}).
static func capture(state: GameState, unit: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not state.objective_owners.has(unit.coord):
		return events
	var previous: int = state.objective_owners[unit.coord]
	if previous == unit.owner_id:
		return events
	state.objective_owners[unit.coord] = unit.owner_id
	(
		events
		. append(
			{
				"type": &"objective_captured",
				"coord": unit.coord,
				"player": unit.owner_id,
				"previous_owner": previous,
			}
		)
	)
	return events


## After a strike by a unit of `striker_owner` (`victim_died`: the victim was killed). Players are
## checked striker's side first, then in id order; per player ELIMINATE (only after a death),
## then DESTROY_SHARE.
static func after_strike(
	state: GameState, striker_owner: int, victim_died: bool
) -> Array[Dictionary]:
	var order: Array[int] = [striker_owner]
	for player in state.player_count:
		if player != striker_owner:
			order.append(player)
	for player in order:
		if victim_died and _eliminated_all_others(state, player):
			return [_finish(state, player, REASON_ELIMINATED)]
		if _destroyed_share(state, player):
			return [_finish(state, player, REASON_ENEMY_DESTROYED)]
	return []


## The current player ends their turn: TAKE_HEXES for that player, then – when the last player
## ends turn `turn_limit` – the turn limit (HOLD_HEXES decides; one qualifying player wins,
## otherwise a draw).
static func at_turn_end(state: GameState) -> Array[Dictionary]:
	var player := state.current_player
	for condition in state.objectives.conditions_for(player, VictoryCondition.Kind.TAKE_HEXES):
		if _occupies_all(state, player, condition.hexes):
			return [_finish(state, player, REASON_OBJECTIVE_TAKEN)]
	var limit := state.objectives.turn_limit
	if limit <= 0 or player != state.player_count - 1 or state.turn < limit:
		return []
	var holders: Array[int] = []
	for candidate in state.player_count:
		for condition in state.objectives.conditions_for(
			candidate, VictoryCondition.Kind.HOLD_HEXES
		):
			if _owns_all(state, candidate, condition.hexes):
				holders.append(candidate)
				break
	var winner := holders[0] if holders.size() == 1 else -1
	return [_finish(state, winner, REASON_TURN_LIMIT)]


## Starting total HP and living HP of every player but `player_id`: Vector2i(start, left).
static func enemy_hp(state: GameState, player_id: int) -> Vector2i:
	var start := 0
	var left := 0
	for other in state.player_count:
		if other == player_id:
			continue
		start += state.starting_hp[other] if other < state.starting_hp.size() else 0
		for unit in state.units_of(other):
			left += unit.hp
	return Vector2i(start, left)


static func _finish(state: GameState, winner: int, reason: StringName) -> Dictionary:
	state.finish(winner, reason)
	return {"type": &"game_over", "winner": winner, "reason": reason}


static func _eliminated_all_others(state: GameState, player_id: int) -> bool:
	if state.objectives.conditions_for(player_id, VictoryCondition.Kind.ELIMINATE).is_empty():
		return false
	for other in state.player_count:
		if other != player_id and not state.units_of(other).is_empty():
			return false
	return not state.units_of(player_id).is_empty()


static func _destroyed_share(state: GameState, player_id: int) -> bool:
	var conditions := state.objectives.conditions_for(
		player_id, VictoryCondition.Kind.DESTROY_SHARE
	)
	if conditions.is_empty():
		return false
	var hp := enemy_hp(state, player_id)
	if hp.x <= 0:
		return false
	for condition in conditions:
		# Integer comparison: lost / start >= share / 100.
		if (hp.x - hp.y) * 100 >= condition.share_percent * hp.x:
			return true
	return false


static func _occupies_all(state: GameState, player_id: int, hexes: Array[Vector2i]) -> bool:
	for c in hexes:
		var unit := state.unit_at(c)
		if unit == null or unit.owner_id != player_id:
			return false
	return true


static func _owns_all(state: GameState, player_id: int, hexes: Array[Vector2i]) -> bool:
	for c in hexes:
		if state.objective_owners.get(c, -1) != player_id:
			return false
	return true
