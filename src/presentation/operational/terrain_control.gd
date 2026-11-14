class_name TerrainControl
extends RefCounted
## View model of the staff map's terrain control layer (TASK-152, docs/design/operational_map/
## terrain_control.html variant A): which hexes are held by a side other than their country's
## original one, and the words for the hex card. Pure and deterministic, derived from
## `HexControl` data alone – a display, never a rule.


## Hex -> holder (0 / 1) for every hex that `HexControl.holder` gives to a side other than its
## initial one (`hex_initial`, -1 for none). Retaken ground disappears.
static func occupied(state: OperationalState) -> Dictionary:
	var result := {}
	for hex: Vector2i in state.hex_holders:
		var holder := HexControl.holder(state, hex)
		if holder >= 0 and holder != int(state.hex_initial.get(hex, -1)):
			result[hex] = holder
	return result


## Cheap change detector of the occupied set (it only depends on the holders, `hex_initial` is
## static): equal while nobody took anything.
static func signature(state: OperationalState) -> int:
	return state.hex_holders.hash()


## The words of the hex card's control column for `hex` seen from `viewer`, "" when the hex is
## not occupied: "Russia – occupied" for ground of the viewer's country taken by the enemy,
## "NATO – captured from Russia" for ground the holder took from the other side.
static func card_text(state: OperationalState, hex: Vector2i, viewer: int) -> String:
	var taken := occupied(state)
	if not taken.has(hex):
		return ""
	return words(state, hex, taken[hex], viewer)


## Same as `card_text` for a known holder.
static func words(state: OperationalState, hex: Vector2i, holder: int, viewer: int) -> String:
	var previous := int(state.hex_initial.get(hex, -1))
	var holder_name := side_name(state, holder)
	if previous < 0 or previous == viewer:
		return "%s – occupied" % holder_name
	return "%s – captured from %s" % [holder_name, side_name(state, previous)]


## Display name of the side of player `index`.
static func side_name(state: OperationalState, index: int) -> String:
	if index < 0 or index >= state.player_sides.size():
		return "–"
	var id := String(state.player_sides[index])
	return "NATO" if id == "nato" else id.capitalize()
