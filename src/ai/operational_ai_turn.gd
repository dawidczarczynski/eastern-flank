class_name OperationalAiTurn
extends RefCounted
## One operational turn of the AI leader (TASK-102c): runs OperationalAi.plan for `player`,
## executes the commands one by one through OperationalSimulation.execute() and ends the move with
## an EndOperationalTurnCommand. Pure and synchronous; the staff map (human game) and MatchRunner
## (headless) both call it.


## Plays `player`'s turn. Result: {"commands": Array[OperationalCommand] (every command tried, the
## end-of-turn command last), "results": Array[bool] (accepted?), "ended": bool}. Nothing is
## executed (empty lists) when it is not `player`'s turn or the operation is over. At most
## `profile.max_commands` planned commands run, plus the end of the turn; a rejected command is
## skipped, never retried. The end of the turn is always tried (it is rejected only while a
## contact battle is pending, which also keeps the plan empty).
static func play(sim: OperationalSimulation, player: int, profile: AiProfile = null) -> Dictionary:
	var out := {
		"commands": [] as Array[OperationalCommand], "results": [] as Array[bool], "ended": false
	}
	var state := sim.state
	if player != state.current_player or not state.result.is_empty():
		return out
	if profile == null:
		profile = AiProfile.shipped()
	var commands: Array[OperationalCommand] = out["commands"]
	var results: Array[bool] = out["results"]
	var planned := OperationalAi.plan(state, player, profile)
	for i in mini(planned.size(), profile.max_commands):
		commands.append(planned[i])
		results.append(sim.execute(planned[i]))
		if not state.result.is_empty():
			return out
	var end := EndOperationalTurnCommand.new()
	commands.append(end)
	var ended := sim.execute(end)
	results.append(ended)
	out["ended"] = ended
	return out
