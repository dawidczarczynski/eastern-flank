class_name BattleOptions
extends RefCounted
## Debug options of the battle scene read from the user command line (after `--`), e.g.
## `tools/run.sh --scenario=objective_battle` (TASK-088). Pure parsing, no scene access.

const SCENARIO_PREFIX := "--scenario="
const DEFAULT_SCENARIO := "default_battle"


## The scenario named by `--scenario=<name>` (one of Scenario.NAMES); DEFAULT_SCENARIO when the
## option is missing, or – with a warning – when the name is unknown. The last option wins.
static func scenario_name(args: PackedStringArray) -> String:
	var result := DEFAULT_SCENARIO
	for arg in args:
		if not arg.begins_with(SCENARIO_PREFIX):
			continue
		var candidate := arg.substr(SCENARIO_PREFIX.length()).strip_edges()
		if candidate in Scenario.NAMES:
			result = candidate
		else:
			push_warning(
				(
					"Unknown scenario '%s' (%s); using %s"
					% [candidate, ", ".join(Scenario.NAMES), DEFAULT_SCENARIO]
				)
			)
			result = DEFAULT_SCENARIO
	return result
