class_name BattleNameText
extends RefCounted
## Translated battle names (TASK-168): the situation phrase from `BattleName` and the nearest
## place of the theatre map ("Suwałki, 5 km east"), as two lines or one "phrase · place" line.
## Empty for a scenario battle (no operational name). Nothing is stored; all of it is computed.


## Translated phrase of a situation key; "" for &"".
static func phrase(key: StringName) -> String:
	return TranslationServer.translate("BATTLE_NAME_" + String(key)) if key != &"" else ""


## The place namer of a theatre map: (Vector2i) -> "Suwałki, 5 km east" or "".
static func namer_of(map: ImportedMap) -> Callable:
	return func(coord: Vector2i) -> String: return StaffMapPlaceName.describe(map, coord)


## Place line of `coord` through `namer`: "Suwałki, 5 km east", or "HEX 06·01" without a name.
static func place_line(namer: Callable, coord: Vector2i) -> String:
	var named := StaffMapPlaceName.named(namer, coord)
	if named != "":
		return named
	return TranslationServer.translate("HEX %s") % StaffMapContactNotice.hex_text(coord)


## [phrase, place] for a situation key; [] without one.
static func lines_for(key: StringName, namer: Callable, coord: Vector2i) -> Array[String]:
	var lines: Array[String] = []
	if key != &"":
		lines.append(phrase(key))
		lines.append(place_line(namer, coord))
	return lines


## "phrase · place" for a situation key; "" without one.
static func line_for(key: StringName, namer: Callable, coord: Vector2i) -> String:
	var lines := lines_for(key, namer, coord)
	return " · ".join(lines) if not lines.is_empty() else ""


## [phrase, place] of `setup` for `viewer` at the operational hex `coord` of `map`.
static func two_lines(
	setup: BattleSetup, viewer: int, map: ImportedMap, coord: Vector2i
) -> Array[String]:
	return lines_for(BattleName.situation(setup, viewer), namer_of(map), coord)


static func one_line(setup: BattleSetup, viewer: int, map: ImportedMap, coord: Vector2i) -> String:
	return line_for(BattleName.situation(setup, viewer), namer_of(map), coord)


## The situation key of an event's `situation` array (one key per player) for `viewer`.
static func key_of(event: Dictionary, viewer: int) -> StringName:
	var list: Variant = event.get("situation")
	if not list is Array or (list as Array).is_empty():
		return &""
	var keys: Array = list
	return StringName(str(keys[clampi(viewer, 0, keys.size() - 1)]))


## The first pending battle of a running operation, named for `viewer`: {lines, line}; used by the
## battle scene, which only has the cut setup. Empty lines when nothing is pending.
static func pending(state: OperationalState, viewer: int) -> Dictionary:
	if state == null or state.pending_battles.is_empty():
		return {"lines": [] as Array[String], "line": ""}
	var setup := state.pending_battles[0]
	var hexes := ContactBattle.hexes(state, setup)
	var coord := hexes[1] if hexes.size() == 2 else Vector2i.ZERO
	var map := ImportedMap.find(setup.map_id)
	return {
		"lines": two_lines(setup, viewer, map, coord), "line": one_line(setup, viewer, map, coord)
	}
