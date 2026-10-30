class_name VictoryCondition
extends Resource
## One way a battle can be won (BattleObjectives.conditions, TASK-088); BattleRules checks them.
##   ELIMINATE     – no other player has living units → immediate win (checked after a death).
##   TAKE_HEXES    – a living own unit on every hex in `hexes` at the end of an own turn →
##                   immediate win.
##   HOLD_HEXES    – owns every hex in `hexes` (GameState.objective_owners) when the turn limit
##                   ends the battle → win (draw when several or no players qualify).
##   DESTROY_SHARE – the enemies have lost >= `share_percent` % of their starting total HP →
##                   immediate win (checked after every strike, incl. counters).
## JSON form (`to_dict`): {"kind": "eliminate" | "take_hexes" | "hold_hexes" | "destroy_share",
## "player": int, "hexes": [[q, r], ...], "share_percent": int}; all keys required.

enum Kind { ELIMINATE, TAKE_HEXES, HOLD_HEXES, DESTROY_SHARE }

## JSON names of the kinds, indexed by Kind.
const KIND_NAMES: Array[String] = ["eliminate", "take_hexes", "hold_hexes", "destroy_share"]

@export var kind: Kind = Kind.ELIMINATE
## The player the condition is for; -1 = every player.
@export var player: int = -1
## TAKE_HEXES / HOLD_HEXES: the hexes (each must be one of BattleObjectives.hexes).
@export var hexes: Array[Vector2i] = []
## DESTROY_SHARE: 1 … 100.
@export var share_percent: int = 0


static func make(
	p_kind: Kind, p_player: int, p_hexes: Array[Vector2i] = [], p_share_percent: int = 0
) -> VictoryCondition:
	var condition := VictoryCondition.new()
	condition.kind = p_kind
	condition.player = p_player
	condition.hexes = p_hexes.duplicate()
	condition.share_percent = p_share_percent
	return condition


func applies_to(player_id: int) -> bool:
	return player == -1 or player == player_id


func uses_hexes() -> bool:
	return kind == Kind.TAKE_HEXES or kind == Kind.HOLD_HEXES


func to_dict() -> Dictionary:
	var hex_list: Array = []
	for c in hexes:
		hex_list.append([c.x, c.y])
	return {
		"kind": KIND_NAMES[kind],
		"player": player,
		"hexes": hex_list,
		"share_percent": share_percent,
	}


## null when a key is missing or has the wrong type, or the kind is unknown. Consistency with the
## objective hexes is checked by BattleObjectives.problem().
static func from_dict(d: Variant) -> VictoryCondition:
	if not d is Dictionary:
		return null
	var kind_value: Variant = d.get("kind")
	var player_value: Variant = CommandCodec.to_int_or_null(d.get("player"))
	var share_value: Variant = CommandCodec.to_int_or_null(d.get("share_percent"))
	var hex_list: Variant = d.get("hexes")
	if not kind_value is String or not KIND_NAMES.has(kind_value):
		return null
	if player_value == null or share_value == null or not hex_list is Array:
		return null
	var condition := VictoryCondition.new()
	condition.kind = KIND_NAMES.find(kind_value) as Kind
	condition.player = player_value
	condition.share_percent = share_value
	for entry: Variant in hex_list:
		var c: Variant = BattleSetup.vector_or_null(entry)
		if c == null:
			return null
		condition.hexes.append(c)
	return condition
