class_name AutoResolveRules
extends Resource
## Numbers of the battle auto-resolve (TASK-120, GDD "Battle hand-off and auto-resolve"), kept in
## data/battle/auto_resolve.tres; read by AutoResolve. **[ASSUMPTION]** until calibrated.

const PATH := "res://data/battle/auto_resolve.tres"

static var _default: AutoResolveRules

## Rounds fought when the setup has no turn limit.
@export var default_rounds: int = 8
## Percent of a side's starting strength it may lose before it breaks (1 … 100).
@export var break_share: int = 50


## The shipped data/battle/auto_resolve.tres, loaded once.
static func shipped() -> AutoResolveRules:
	if _default == null:
		_default = load(PATH) as AutoResolveRules
	return _default


## "" when the data is valid, otherwise the first problem found.
func problem() -> String:
	if default_rounds < 1:
		return "default_rounds must be at least 1"
	if break_share < 1 or break_share > 100:
		return "break_share must be within 1 … 100"
	return ""
