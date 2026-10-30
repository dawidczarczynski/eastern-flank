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


## The full attack forecast (TASK-089b) while `attacker_id` is selected and `defender_id` is one
## of its valid targets, else []. Each line is {label, value} (label an untranslated key, value ""
## when the label says it all), numbers from AttackCommand.forecast():
## DAMAGE 4.0 (2–6) · DESTROY 63 % (omitted when impossible) · COUNTER 0.6 (0–2) / NO COUNTER.
## The target ring's ATTACK card shows the DAMAGE line as its big number and lists the rest.
static func attack_forecast(
	state: GameState, attacker_id: int, defender_id: int
) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var f := _forecast_of(state, attacker_id, defender_id)
	if f == null:
		return lines
	lines.append(
		_forecast_line("DAMAGE", _spread_text(f.expected_damage, f.damage_low, f.damage_high))
	)
	var destroy := destroy_chance_text(f.kill_chance)
	if destroy != "":
		lines.append(_forecast_line("DESTROY", destroy))
	if f.counter_possible:
		lines.append(
			_forecast_line(
				"COUNTER", _spread_text(f.counter_expected, f.counter_low, f.counter_high)
			)
		)
	else:
		lines.append(_forecast_line("NO COUNTER", ""))
	return lines


## The compact attack tag beside the cursor (TASK-089b) while `attacker_id` is selected and
## `defender_id` is one of its valid targets, else []. Lines {label, value} like attack_forecast:
## ATTACK ~4.0 (2–6) · DESTROY <1 % (omitted when impossible) · COUNTER ~0.6 / NO COUNTER.
static func attack_tag(state: GameState, attacker_id: int, defender_id: int) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var f := _forecast_of(state, attacker_id, defender_id)
	if f == null:
		return lines
	lines.append(
		_forecast_line("ATTACK", "~" + _spread_text(f.expected_damage, f.damage_low, f.damage_high))
	)
	var destroy := destroy_chance_text(f.kill_chance)
	if destroy != "":
		lines.append(_forecast_line("DESTROY", destroy))
	if f.counter_possible:
		lines.append(_forecast_line("COUNTER", "~%.1f" % f.counter_expected))
	else:
		lines.append(_forecast_line("NO COUNTER", ""))
	return lines


## "63 %", "<1 %" / ">99 %" near the edges, "100 %" when certain, "" when impossible.
static func destroy_chance_text(chance: float) -> String:
	if chance <= 0.0:
		return ""
	if chance >= 1.0:
		return "100 %"
	if chance < 0.01:
		return "<1 %"
	if chance > 0.99:
		return ">99 %"
	return "%d %%" % roundi(chance * 100.0)


## The forecast of `attacker_id` attacking `defender_id`, null unless it is a valid target.
static func _forecast_of(state: GameState, attacker_id: int, defender_id: int) -> CombatForecast:
	if attacker_id == -1 or not AttackCommand.valid_targets(state, attacker_id).has(defender_id):
		return null
	return AttackCommand.forecast(state, state.get_unit(attacker_id), state.get_unit(defender_id))


## "4.0 (2–6)": the average and its 10–90 % range.
static func _spread_text(expected: float, low: int, high: int) -> String:
	return "%.1f (%d–%d)" % [expected, low, high]


static func _forecast_line(label: String, value: String) -> Dictionary:
	return {"label": label, "value": value}


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
