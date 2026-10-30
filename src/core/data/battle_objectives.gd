class_name BattleObjectives
extends Resource
## How a battle is won and how long it lasts (GDD "Vision decisions", TASK-088): a turn limit,
## objective hexes with their initial owners and a list of VictoryCondition. Part of BattleSetup;
## Scenario.from_setup copies it into GameState (`objectives`, `objective_owners`) and
## BattleRules applies it.
## JSON form (`to_dict`): {"turn_limit": int, "hexes": [[q, r], ...], "initial_owners": [int],
## "conditions": [VictoryCondition]}; all keys required. `from_dict({})` = default_objectives()
## (setups written before TASK-088).

## 0 = none; otherwise the battle ends when the last player ends turn `turn_limit`.
@export var turn_limit: int = 0
## Objective hexes (no duplicates). A hex is owned by the last side that ended a move on it.
@export var hexes: Array[Vector2i] = []
## Initial owner of each hex in `hexes` (parallel array); -1 = neutral.
@export var initial_owners: Array[int] = []
@export var conditions: Array[VictoryCondition] = []


## Today's rule: eliminate every enemy unit, for both players; no turn limit, no objective hexes.
static func default_objectives() -> BattleObjectives:
	var objectives := BattleObjectives.new()
	objectives.conditions.append(VictoryCondition.make(VictoryCondition.Kind.ELIMINATE, -1))
	return objectives


## Conditions of `kind` that apply to `player_id`, in list order.
func conditions_for(player_id: int, kind: VictoryCondition.Kind) -> Array[VictoryCondition]:
	var result: Array[VictoryCondition] = []
	for condition in conditions:
		if condition.kind == kind and condition.applies_to(player_id):
			result.append(condition)
	return result


## "" when the objectives are consistent, otherwise what is wrong. With `player_count` >= 0 the
## owners and condition players are also checked against it (-1 … player_count - 1).
func problem(player_count: int = -1) -> String:
	var result := _hex_problem(player_count)
	for condition in conditions:
		if result == "":
			result = _condition_problem(condition, player_count)
	return result


func _hex_problem(player_count: int) -> String:
	if turn_limit < 0:
		return "negative turn limit"
	if initial_owners.size() != hexes.size():
		return "not one initial owner per objective hex"
	for i in hexes.size():
		if hexes.find(hexes[i]) != i:
			return "duplicate objective hex %s" % hexes[i]
	for owner in initial_owners:
		if not _valid_player(owner, player_count):
			return "initial owner %d out of range" % owner
	return ""


func _condition_problem(condition: VictoryCondition, player_count: int) -> String:
	if not _valid_player(condition.player, player_count):
		return "condition player %d out of range" % condition.player
	if condition.uses_hexes() and condition.hexes.is_empty():
		return "a take / hold condition without hexes"
	for c in condition.hexes:
		if condition.uses_hexes() and not hexes.has(c):
			return "condition hex %s is not an objective hex" % c
	var share := condition.share_percent
	if condition.kind == VictoryCondition.Kind.DESTROY_SHARE and (share < 1 or share > 100):
		return "share %d %% out of 1 … 100" % share
	return ""


## -1 (neutral / every player) or a player id; any id >= 0 when `player_count` < 0.
static func _valid_player(player_id: int, player_count: int) -> bool:
	return player_id >= -1 and (player_count < 0 or player_id < player_count)


func to_dict() -> Dictionary:
	var hex_list: Array = []
	for c in hexes:
		hex_list.append([c.x, c.y])
	var condition_list: Array[Dictionary] = []
	for condition in conditions:
		condition_list.append(condition.to_dict())
	return {
		"turn_limit": turn_limit,
		"hexes": hex_list,
		"initial_owners": initial_owners.duplicate(),
		"conditions": condition_list,
	}


## null when a key is missing or has the wrong type, or the objectives are inconsistent
## (`problem()`). `{}` gives default_objectives().
static func from_dict(d: Variant) -> BattleObjectives:
	if not d is Dictionary:
		return null
	if (d as Dictionary).is_empty():
		return default_objectives()
	var limit_value: Variant = CommandCodec.to_int_or_null(d.get("turn_limit"))
	var hex_list: Variant = d.get("hexes")
	var owner_list: Variant = d.get("initial_owners")
	var condition_list: Variant = d.get("conditions")
	if limit_value == null or not hex_list is Array or not owner_list is Array:
		return null
	if not condition_list is Array:
		return null
	var objectives := BattleObjectives.new()
	objectives.turn_limit = limit_value
	for entry: Variant in hex_list:
		var c: Variant = BattleSetup.vector_or_null(entry)
		if c == null:
			return null
		objectives.hexes.append(c)
	for entry: Variant in owner_list:
		var owner: Variant = CommandCodec.to_int_or_null(entry)
		if owner == null:
			return null
		objectives.initial_owners.append(owner)
	for entry: Variant in condition_list:
		var condition := VictoryCondition.from_dict(entry)
		if condition == null:
			return null
		objectives.conditions.append(condition)
	if objectives.problem() != "":
		return null
	return objectives
