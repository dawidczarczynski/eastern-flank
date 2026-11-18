class_name OrderRules
extends RefCounted
## Unit orders (TASK-081a, GDD "Unit orders"): which orders a unit has and whether one can be
## given now. Order numbers are data (data/orders/*.tres, OrderDefinition).

const DIG_IN := &"dig_in"
const SMOKE := &"smoke"
const BLIND_FIRE := &"blind_fire"
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
	elif order_id == SMOKE:
		reason = SmokeCommand.new(unit_id, Vector2i.ZERO).unit_problem(state)
	elif order_id == BLIND_FIRE:
		reason = BlindFireCommand.new(unit_id, Vector2i.ZERO).unit_problem(state)
	return {"enabled": reason == "", "reason": reason}


## Common checks of the targeted orders (Smoke, Blind fire) on the unit alone, in the order of
## the GDD: game_over, unit_not_found, not_your_unit, no_command_points, order_not_available,
## already_acted. "" when the unit may give `order_id` (target not checked).
static func slot_problem(state: GameState, unit_id: int, order_id: StringName) -> String:
	if state.is_over():
		return "game_over"
	var unit := state.get_unit(unit_id)
	if unit == null or not unit.is_alive():
		return "unit_not_found"
	if unit.owner_id != state.current_player:
		return "not_your_unit"
	if not state.can_activate(unit):
		return "no_command_points"
	if not orders_for(unit).has(order_id):
		return "order_not_available"
	if unit.has_attacked or unit.slot_order != &"":
		return "already_acted"
	return ""


## Why `distance` is outside the order's range for the unit's class: "too_close" / "out_of_range";
## "" when it fits.
static func range_problem(unit: Unit, order_id: StringName, distance: int) -> String:
	var r := definition(order_id).range_for(unit.definition.unit_class)
	if distance < r.x:
		return "too_close"
	if distance > r.y:
		return "out_of_range"
	return ""
