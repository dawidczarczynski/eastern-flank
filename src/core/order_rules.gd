class_name OrderRules
extends RefCounted
## Unit orders (TASK-081a, GDD "Unit orders"): which orders a unit has and whether one can be
## given now. Order numbers are data (data/orders/*.tres, OrderDefinition).

const DIG_IN := &"dig_in"
## All order ids of the radial menu, in menu order (Move is a plain command and not listed).
const ALL_IDS: Array[StringName] = [
	&"blind_fire", &"smoke", &"ambush", &"scoot", &"resupply", &"dig_in", &"camouflage"
]
const _DIR := "res://data/orders/"

static var _cache: Dictionary = {}


## The order's data, or null when the order is not built yet.
static func definition(order_id: StringName) -> OrderDefinition:
	if not _cache.has(order_id):
		var path := "%s%s.tres" % [_DIR, order_id]
		_cache[order_id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[order_id]


## Orders (built ones) whose allowed classes include the unit's class.
static func orders_for(unit: Unit) -> Array[StringName]:
	var result: Array[StringName] = []
	for order_id in ALL_IDS:
		var def := definition(order_id)
		if def != null and def.allowed_classes.has(unit.definition.unit_class):
			result.append(order_id)
	return result


## Defence a unit gets from its orders (Dig in while dug).
static func defence_bonus(unit: Unit) -> int:
	if unit.dug:
		var def := definition(DIG_IN)
		return def.defence_bonus if def != null else 0
	return 0


## {enabled, reason}: whether `order_id` can be given by the unit now; `reason` is the code of
## the command's validate() ("" when enabled). Orders not built yet: order_not_available.
static func availability(state: GameState, unit_id: int, order_id: StringName) -> Dictionary:
	var reason := "order_not_available"
	if order_id == DIG_IN:
		reason = DigInCommand.new(unit_id).validate(state)
	return {"enabled": reason == "", "reason": reason}
