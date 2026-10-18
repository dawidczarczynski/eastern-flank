class_name HudModel
extends RefCounted
## Pure HUD data derived from the game state (no scene access). Status strings are untranslated
## keys; the HUD translates them.


## `{turn_text, active_player, players: [{units, ready, status, active, name, short, color,
## ink}, ...]}` (by player id). `name` is an untranslated key; colours come from the faction.
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
		"active_player": current_player,
		"players": players,
	}


## Whether a `turn_started` moving from (prev_turn, prev_player) to (turn, player) shows the
## banner.
static func banner_for(prev_turn: int, prev_player: int, turn: int, player: int) -> bool:
	return prev_turn != turn or prev_player != player


## "" while the game runs, otherwise "VICTORY" / "DEFEAT" from the human's point of view.
static func result_banner(state: GameState, human_player: int) -> String:
	if state.winner == -1:
		return ""
	return "VICTORY" if state.winner == human_player else "DEFEAT"
