class_name BattleConditionsRules
extends Resource
## Effects of installations (TASK-099a, GDD "Battle conditions"): the integrity of a side's
## airfields sets its fire support in the next battle; the integrity of its command posts (C2) sets
## the orders it may issue per operational turn (OperationalState.orders_per_turn) – a battle has
## no command-point limit from the operation. Numbers in data/battle/conditions.tres
## [ASSUMPTION], read by the operation (ContactRules), FireSupportCommand and AutoResolve.

const PATH := "res://data/battle/conditions.tres"

static var _default: BattleConditionsRules

## Orders per operational turn of a side with intact command posts (or none at all).
@export var orders_base: int = 4
## Lowest orders per turn as a percent of the base (never below 1).
@export var orders_floor: int = 25
## Fire-support missions of a side with intact airfields (or none at all).
@export var fire_support_base: int = 2
## Lowest fire-support missions as a percent of the base.
@export var fire_support_floor: int = 0
## Attack value of the off-map shooter of a fire-support mission.
@export var fire_support_attack: int = 4
## Shots (rolls) of one mission.
@export var fire_support_shots: int = 6
## Faces of the die of one shot (a roll at or below the hit value hits).
@export var fire_support_die: int = 10


## The shipped data/battle/conditions.tres, loaded once.
static func shipped() -> BattleConditionsRules:
	if _default == null:
		_default = load(PATH) as BattleConditionsRules
	return _default


## The conditions `player` fights its next battle in, from their own installations: fire support
## only (command points stay 0 = unlimited; ammunition, morale and the posture fields keep their
## defaults).
static func for_side(
	installations: Array[Installation], player: int, rules: BattleConditionsRules = null
) -> BattleSetup.Conditions:
	if rules == null:
		rules = shipped()
	var conditions := BattleSetup.Conditions.new()
	conditions.fire_support = scaled(
		rules.fire_support_base, rules.fire_support_floor, installations, player, &"airfield"
	)
	return conditions


## Orders `player` may issue per operational turn: the base scaled by the mean integrity of their
## command posts (`scaled`), at least 1; the full base without a command post.
static func orders_per_turn(
	installations: Array[Installation], player: int, rules: BattleConditionsRules = null
) -> int:
	if rules == null:
		rules = shipped()
	return maxi(1, scaled(rules.orders_base, rules.orders_floor, installations, player, &"c2"))


## base x mean integrity of the side's installations of `class_id` / 100, rounded half up, never
## below `floor_percent` of the base; the full base when the side has none of that class.
static func scaled(
	base: int,
	floor_percent: int,
	installations: Array[Installation],
	player: int,
	class_id: StringName
) -> int:
	var count := 0
	var total := 0
	for installation in installations:
		if installation.owner == player and installation.class_id == class_id:
			count += 1
			total += clampi(installation.integrity, 0, Installation.MAX_INTEGRITY)
	if count == 0:
		return base
	var value := _round_div(base * total, 100 * count)
	return maxi(value, _round_div(base * floor_percent, 100))


## "" when the data is valid, otherwise the first problem found.
func problem() -> String:
	if orders_base < 1:
		return "orders_base must be at least 1"
	if orders_floor < 0 or orders_floor > 100:
		return "orders_floor must be within 0 … 100"
	if fire_support_base < 0:
		return "fire_support_base must not be negative"
	if fire_support_floor < 0 or fire_support_floor > 100:
		return "fire_support_floor must be within 0 … 100"
	if fire_support_attack < 1 or fire_support_shots < 1 or fire_support_die < 1:
		return "fire_support_attack, fire_support_shots and fire_support_die must be at least 1"
	return ""


## n / d rounded half up (n >= 0, d > 0).
@warning_ignore("integer_division")
static func _round_div(n: int, d: int) -> int:
	return (2 * n + d) / (2 * d)
