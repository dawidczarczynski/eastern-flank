class_name DebugResult
extends RefCounted
## Screenshot aid (tools/screenshot.gd, SCREENSHOT_SHOTS=result:<kind>): a throwaway, already
## ended copy of a scenario's starting state, so the result banner can be rendered without
## playing a battle. Never fed to the simulation the game runs.

## kind -> [winner (relative to player 0 = the human), GameState.end_reason]
const OUTCOMES := {
	"victory": [0, &"objective_taken"],
	"defeat": [1, &"eliminated"],
	"draw": [-1, &"turn_limit"],
}


## The starting state of `scenario_name` ended as `kind` (OUTCOMES) on its last turn (the turn
## limit, else turn 1); null with an error for an unknown kind.
static func ended_state(scenario_name: String, seed_value: int, kind: String) -> GameState:
	if not OUTCOMES.has(kind):
		push_error("DebugResult: unknown kind '%s' (%s)" % [kind, ", ".join(OUTCOMES.keys())])
		return null
	var state := Scenario.build(scenario_name, seed_value, FactionRegistry.DEFAULT_IDS)
	if state == null:
		return null
	state.turn = maxi(HudModel.turn_limit_of(state), 1)
	state.finish(OUTCOMES[kind][0], OUTCOMES[kind][1])
	return state
