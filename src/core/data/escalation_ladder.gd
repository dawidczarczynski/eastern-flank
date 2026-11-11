class_name EscalationLadder
extends Resource
## The escalation ladder shared by both sides (TASK-115, GDD "Escalation ladder"), kept in
## data/operational/escalation.tres; read by EscalationRules and the view.

const PATH := "res://data/operational/escalation.tres"

static var _default: EscalationLadder

## Index = level number.
@export var levels: Array[EscalationLevel] = []
## From this level an enemy sanctuary is open to ground entry and strikes.
@export var sanctuary_open_level: int = 2
## Reaching this level makes aligned countries belligerent and neutral ones aligned.
@export var allies_join_level: int = 3
## Quiet full rounds after which the level drops by one (not below the start level).
@export var calm_rounds: int = 3
## Steps a first sanctuary breach adds.
@export var sanctuary_breach_escalation: int = 1
## Steps a strike on an urban hex adds.
@export var urban_strike_escalation: int = 1
## Political decisions the current player may take per turn (TASK-117).
@export var decisions_per_turn: int = 1
## Steps the Escalate decision / declaring hostilities without a casus belli / invoking an
## alliance add.
@export var decision_escalation: int = 1
@export var declaration_escalation: int = 1
@export var alliance_escalation: int = 1
## Turns after Stand down during which the escalating decisions are rejected.
@export var stand_down_cooldown_turns: int = 2
## Demand neutrality is rejected above this level.
@export var demand_neutrality_max_level: int = 2
## Collapse (TASK-140, CollapseRules): a side is *routed* when its present strength is at most this
## % of its fielded strength ...
@export var collapse_strength_pct: int = 50
## ... or *shaken* when the average readiness of its surviving formations is at most this ...
@export var collapse_readiness_pct: int = 35
## ... while its present strength is at most this % of the fielded one.
@export var collapse_readiness_strength_pct: int = 70


## The shipped data/operational/escalation.tres, loaded once.
static func shipped() -> EscalationLadder:
	if _default == null:
		_default = load(PATH) as EscalationLadder
	return _default


## The highest level number: the nuclear attack, reached only by NuclearStrikeCommand (TASK-140).
func top() -> int:
	return levels.size() - 1


## The highest level incidents and ordinary decisions reach (TASK-140): one below `top()`.
func cap() -> int:
	return top() - 1


## Strike classes allowed at `level` (clamped into range).
func strike_classes_at(level: int) -> Array[StringName]:
	return levels[clampi(level, 0, top())].strike_classes


## "" when the data is valid, otherwise the first problem found.
func problem() -> String:
	if levels.size() < 3:
		return "the ladder needs at least 3 levels, has %d" % levels.size()
	var seen := {}
	for level in levels:
		if level == null:
			return "empty level"
		if seen.has(level.id):
			return "duplicate level id '%s'" % level.id
		seen[level.id] = true
	return _numbers_problem()


func _numbers_problem() -> String:
	if sanctuary_open_level < 0 or sanctuary_open_level > top() - 1:
		return "sanctuary_open_level %d outside 0 .. %d" % [sanctuary_open_level, top() - 1]
	if allies_join_level < 0 or allies_join_level > top() - 1:
		return "allies_join_level %d outside 0 .. %d" % [allies_join_level, top() - 1]
	if calm_rounds < 1:
		return "calm_rounds must be at least 1"
	if sanctuary_breach_escalation < 0:
		return "sanctuary_breach_escalation must not be negative"
	if urban_strike_escalation < 0:
		return "urban_strike_escalation must not be negative"
	return _decisions_problem()


func _decisions_problem() -> String:
	if decisions_per_turn < 1:
		return "decisions_per_turn must be at least 1"
	if (
		decision_escalation < 0
		or declaration_escalation < 0
		or alliance_escalation < 0
		or stand_down_cooldown_turns < 0
		or demand_neutrality_max_level < 0
	):
		return "decision escalation, cooldown and neutrality level must not be negative"
	for pct in [collapse_strength_pct, collapse_readiness_pct, collapse_readiness_strength_pct]:
		if pct < 1 or pct > 100:
			return "collapse percentages must be within 1 .. 100, got %d" % pct
	return ""
