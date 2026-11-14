class_name FireSupportModel
extends RefCounted
## Pure view model of the fire-support button (TASK-099b): the counter, why the button is off and
## the enemy companies a mission may target. Rules stay in FireSupportCommand; this only asks it.


## Missions `player` has left, as the counter text ("2").
static func counter_text(state: GameState, player: int) -> String:
	return str(state.fire_support_left[player])


## The counter is shown for a side that had missions at the start (`start` =
## Conditions.fire_support); scenario battles with none hide it.
static func shown(start: int) -> bool:
	return start > 0


## Untranslated reason the button is off for `player`, "" when a mission can be called.
static func problem(state: GameState, player: int) -> String:
	if state.is_over() or player != state.current_player:
		return "NOT YOUR TURN"
	if state.fire_support_left[player] <= 0:
		return "NO FIRE SUPPORT LEFT"
	if state.fire_support_used_turn[player]:
		return "FIRE SUPPORT ALREADY USED THIS TURN"
	return ""


## Ids of the enemy companies `player` sees (the legal targets of FireSupportCommand).
static func targets(state: GameState, player: int) -> Array[int]:
	var ids: Array[int] = []
	for unit: Unit in state.units.values():
		if (
			unit.owner_id != player
			and unit.is_alive()
			and FireSupportCommand.seen_by(state, player, unit.coord)
		):
			ids.append(unit.id)
	return ids


## The command a click on `coord` sends in the target mode: a mission on the enemy company there,
## null when the tile holds no enemy company (the command itself still checks visibility).
static func click_command(state: GameState, player: int, coord: Vector2i) -> FireSupportCommand:
	var target := state.unit_at(coord)
	if target == null or target.owner_id == player or not target.is_alive():
		return null
	return FireSupportCommand.new(player, target.id)


## " · FIRE SUPPORT 1" part of the battle report: missions used = `start` - left; "" when none.
static func report_text(state: GameState, player: int, start: int) -> String:
	var used := start - state.fire_support_left[player]
	return "" if used <= 0 else "%s %d" % [TranslationServer.translate("FIRE SUPPORT USED"), used]
