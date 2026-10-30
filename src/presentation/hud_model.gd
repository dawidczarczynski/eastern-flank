class_name HudModel
extends RefCounted
## Pure HUD data derived from the game state (no scene access). Status strings are untranslated
## keys; the HUD translates them.

## Untranslated subtitle of the result banner for each GameState.end_reason, as
## [winner is the human, otherwise] (a draw counts as "otherwise").
const REASON_TEXTS := {
	&"eliminated": ["ENEMY ELIMINATED", "OUR FORCES ELIMINATED"],
	&"enemy_destroyed": ["ENEMY DESTROYED", "OUR FORCES DESTROYED"],
	&"objective_taken": ["OBJECTIVES TAKEN", "OBJECTIVES LOST"],
	&"turn_limit": ["TURN LIMIT REACHED", "TURN LIMIT REACHED"],
}


## `{turn_text, turn_limit_text, active_player, players: [{units, ready, status, active, name,
## short, color, ink}, ...]}` (by player id). `name` is an untranslated key; colours come from
## the faction.
static func top_bar(state: GameState, human_player: int) -> Dictionary:
	return top_bar_at(state, human_player, state.turn, state.current_player)


## Like top_bar() but with the turn and active player of an event being played back (the
## simulation may already be further ahead); unit counts still come from `state`.
static func top_bar_at(
	state: GameState, human_player: int, turn: int, current_player: int
) -> Dictionary:
	var players: Array[Dictionary] = []
	for player in state.player_count:
		var living := state.units_of(player)
		var ready := 0
		for unit in living:
			if not UnitStatus.is_done(state, unit):
				ready += 1
		var active := player == current_player
		var status := "WAITING"
		if active:
			status = "YOUR TURN" if player == human_player else "AI TURN"
		var entry := {
			"units": living.size(),
			"ready": ready,
			"status": status,
			"active": active,
			"name": UiPalette.faction_name(state, player),
			"short": UiPalette.faction_short(state, player),
			"color": UiPalette.faction_color(state, player),
			"ink": UiPalette.faction_ink(state, player),
		}
		players.append(entry)
	return {
		"turn_text": "%02d" % turn,
		"turn_limit_text": turn_limit_text(turn_limit_of(state)),
		"active_player": current_player,
		"command_points_text": command_points_text(state, current_player),
		"players": players,
	}


## "C2 2/3" (remaining / per turn) for `player`, "" when they are unlimited. A player other than
## the state's current one (a turn being played back that the state already moved past) shows
## their full allowance.
static func command_points_text(state: GameState, player: int) -> String:
	if not state.is_command_limited(player):
		return ""
	var per_turn := state.command_points_per_turn[player]
	var remaining := state.command_points if player == state.current_player else per_turn
	return "C2 %d/%d" % [remaining, per_turn]


## Whether a `turn_started` moving from (prev_turn, prev_player) to (turn, player) shows the
## banner.
static func banner_for(prev_turn: int, prev_player: int, turn: int, player: int) -> bool:
	return prev_turn != turn or prev_player != player


## "" while the game runs, otherwise "VICTORY" / "DEFEAT" from the human's point of view, or
## "DRAW" when the battle ended without a winner.
static func result_banner(state: GameState, human_player: int) -> String:
	if not state.is_over():
		return ""
	if state.winner == -1:
		return "DRAW"
	return "VICTORY" if state.winner == human_player else "DEFEAT"


## A turn with the battle's limit: "03", or "03 / 08" when there is one (the result caption).
static func turn_text(turn: int, turn_limit: int) -> String:
	if turn_limit > 0:
		return "%02d / %02d" % [turn, turn_limit]
	return "%02d" % turn


## The turn bar's suffix after the big turn number: "/08", or "" without a turn limit.
static func turn_limit_text(turn_limit: int) -> String:
	return "/%02d" % turn_limit if turn_limit > 0 else ""


## The battle's turn limit (0 = none).
static func turn_limit_of(state: GameState) -> int:
	return state.objectives.turn_limit


## "" while the game runs, otherwise why it ended (untranslated key, REASON_TEXTS) from the
## human's point of view; "" for an unknown reason.
static func result_reason(state: GameState, human_player: int) -> String:
	if not state.is_over() or not REASON_TEXTS.has(state.end_reason):
		return ""
	var texts: Array = REASON_TEXTS[state.end_reason]
	return texts[0] if state.winner == human_player else texts[1]
