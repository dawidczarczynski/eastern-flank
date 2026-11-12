class_name AiProfile
extends Resource
## Tuning of the operational AI (TASK-102a, GDD "Operational AI"): every number OperationalAi
## reads. One level in v1 (data/ai/default.tres); further profiles are possible later.

const DEFAULT_TIERS := {&"air_defence": 0, &"airfield": 1, &"c2": 1, &"formation": 2}
const DEFAULT_PATH := "res://data/ai/default.tres"

static var _default: AiProfile

## Score of a destination: goal weight x this, minus distance x `distance_weight`, minus the
## enemy formations near the goal x `threat_weight` x (1 - aggression).
@export var goal_weight: float = 10.0
@export var distance_weight: float = 1.0
@export var threat_weight: float = 3.0
## 0 - 1: the bolder the AI, the farther from an enemy it already moves in the advance posture
## (within ceil(1 / aggression) hexes) and the less it fears threats.
@export_range(0.0, 1.0) var aggression: float = 0.5
## Salvos' worth of stock (of one weapon) the AI never spends: stock must exceed
## `strike_reserve` x the weapon's max salvo.
@export var strike_reserve: int = 1
## A strike with an expected value (hits x damage x target weight) below this is skipped.
@export var min_strike_value: float = 10.0
## Most commands one plan holds.
@export var max_commands: int = 40
## Rings around a goal hex searched for a reachable destination when the goal hex itself is not.
@export var destination_search_radius: int = 3
## A formation target counts as "about to make contact" with an enemy this close (hexes).
@export var contact_range: int = 2
## Strike target class (installation class or &"formation") -> tier; lower tiers first.
@export var target_tiers: Dictionary = DEFAULT_TIERS.duplicate()
## Strike target class -> weight in the expected value. Classes not listed are not targeted.
@export var target_weights: Dictionary = {
	&"air_defence": 3.0, &"airfield": 2.0, &"c2": 2.0, &"formation": 5.0
}


## The shipped data/ai/default.tres, loaded once.
static func shipped() -> AiProfile:
	if _default == null:
		_default = load(DEFAULT_PATH) as AiProfile
	return _default


## "" when the numbers are usable, otherwise the first problem.
func problem() -> String:
	if aggression < 0.0 or aggression > 1.0:
		return "aggression %s outside 0 .. 1" % aggression
	if strike_reserve < 0 or max_commands < 0 or destination_search_radius < 0 or contact_range < 0:
		return "strike_reserve, max_commands, destination_search_radius, contact_range must be >= 0"
	if goal_weight < 0.0 or distance_weight < 0.0 or threat_weight < 0.0 or min_strike_value < 0.0:
		return "weights and min_strike_value must be >= 0"
	return ""
