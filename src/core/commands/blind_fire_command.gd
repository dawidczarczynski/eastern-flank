class_name BlindFireCommand
extends Command
## Order Blind fire (TASK-081b): a strike on the enemy standing in a hex without a line-of-sight
## requirement, attack -1 (data/orders/blind_fire.tres): margin = max(1, attack - defence - tile
## bonus - 1). Range per class from the order data (tank / infantry 1-2, MLRS 3-6). Uses the
## action slot and the movement; the counter follows the normal rules (AttackCommand.counter).

var unit_id: int
var target: Vector2i


func _init(p_unit_id: int, p_target: Vector2i) -> void:
	unit_id = p_unit_id
	target = p_target


func to_dict() -> Dictionary:
	return {"type": "order_blind_fire", "unit_id": unit_id, "target": [target.x, target.y]}


## Attack margin of a Blind fire strike of `attacker` on `defender` (pure, no rng): what
## TASK-082's targeting preview shows. Same as CombatForecast.blind_margin.
static func margin(state: GameState, attacker: Unit, defender: Unit) -> int:
	var modifier := OrderRules.definition(OrderRules.BLIND_FIRE).attack_modifier
	return AttackCommand.compute_damage(state, attacker, defender, modifier)


func validate(state: GameState) -> String:
	var problem := unit_problem(state)
	if problem != "":
		return problem
	if not state.grid.has_tile(target):
		return "invalid_target"
	var unit := state.get_unit(unit_id)
	problem = OrderRules.range_problem(
		unit, OrderRules.BLIND_FIRE, Hex.distance(unit.coord, target)
	)
	if problem != "":
		return problem
	var victim := state.unit_at(target)
	if victim == null or not victim.is_alive():
		return "no_unit_at_target"
	if victim.owner_id == unit.owner_id:
		return "not_an_enemy"
	return ""


## The common checks on the unit alone (target not looked at).
func unit_problem(state: GameState) -> String:
	return OrderRules.slot_problem(state, unit_id, OrderRules.BLIND_FIRE)


func apply(state: GameState) -> Array[Dictionary]:
	var unit := state.get_unit(unit_id)
	var victim := state.unit_at(target)
	unit.has_attacked = true
	unit.slot_order = OrderRules.BLIND_FIRE
	unit.moves_left = 0
	var activation := state.activate(unit)
	var issued: Array[Dictionary] = [
		{
			"type": &"unit_order_issued",
			"unit_id": unit_id,
			"order": OrderRules.BLIND_FIRE,
			"target": target,
		},
	]
	var events := AttackCommand.strike(state, unit, victim, false, true)
	# command_points_changed follows the first unit_attacked (as for an attack).
	for i in activation.size():
		events.insert(1 + i, activation[i])
	issued.append_array(events)
	issued.append_array(AttackCommand.counter(state, unit, victim))
	return issued
