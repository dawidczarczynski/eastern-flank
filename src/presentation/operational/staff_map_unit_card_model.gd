class_name StaffMapUnitCardModel
extends RefCounted
## Pure model of the unit variant of the bottom-bar strip (TASK-151, docs/design/operational_map/
## README.md "Unit info"). Own formations show everything; a hostile one only what intel allows:
## its strength reads "EST." (no gauge) and posture and order read "?" (fog itself is TASK-100).
## Also shortens long names (English and Polish word tables) so they fit the strip title.

const UNKNOWN := "?"
const ESTIMATED_KEY := "UNIT_CARD_EST"
## Longest name (characters, upper case) that fits the strip title: 2 lines of ~15 characters at
## StaffMapUnitStrip.NAME_SIZE in the 114 px title column.
const NAME_MAX_CHARS := 28
## Words shortened when a name is too long, per language, in this order (longest gain first), one
## at a time. The Polish table lists the inflected forms the unit names use.
const ABBREVIATIONS_EN: Array[Array] = [
	["MECHANISED", "MECH"],
	["MOTORISED", "MOT"],
	["RECONNAISSANCE", "RECON"],
	["BATTALION", "BN"],
	["BRIGADE", "BDE"],
	["REGIMENT", "REGT"],
	["DIVISION", "DIV"],
	["INFANTRY", "INF"],
	["ARTILLERY", "ARTY"],
	["COMPANY", "CO"],
	["ARMOURED", "ARM"],
]
const ABBREVIATIONS_PL: Array[Array] = [
	["ZMECHANIZOWANY", "ZMECH"],
	["ZMECHANIZOWANA", "ZMECH"],
	["ZMECHANIZOWANE", "ZMECH"],
	["ZMOTORYZOWANY", "ZMOT"],
	["ZMOTORYZOWANEJ", "ZMOT"],
	["ROZPOZNAWCZY", "ROZP"],
	["BATALION", "BAON"],
	["BRYGADA", "BRYG"],
	["DYWIZJON", "DYWN"],
	["DYWIZJA", "DYW"],
	["KOMPANIA", "KOMP"],
	["PIECHOTY", "PIECH"],
	["ARTYLERII", "ART"],
	["PANCERNY", "PANC"],
	["PANCERNA", "PANC"],
	["RAKIETOWYCH", "RAKIET"],
	["WYRZUTNI", "WYRZ"],
]
const _LOWER_PL := "ąćęłńóśźż"
const _UPPER_PL := "ĄĆĘŁŃÓŚŹŻ"


## {id, own, owner_id, name, side_text, known, lit, strength, max_strength, strength_text,
## posture_text, order_text} of `formation` as `viewer` sees it. `place_text` is a
## (Vector2i) -> String callable naming a hex ("" = use the hex number); may be invalid.
static func build(formation: Formation, viewer_player: int, place_text := Callable()) -> Dictionary:
	var own := formation.owner_id == viewer_player
	var current := formation.strength()
	var maximum := formation.max_strength()
	var model := {
		"id": formation.id,
		"own": own,
		"owner_id": formation.owner_id,
		"name": abbreviate(upper(_t(formation.display_name)), NAME_MAX_CHARS),
		"side_text": _t("OWN") if own else _t("HOSTILE"),
		"known": own,
		"lit": StaffMapFormations.lit_segments(current, maximum) if own else 0,
		"strength": current if own else -1,
		"max_strength": maximum if own else -1,
		"strength_text": "%d / %d" % [current, maximum] if own else _t(ESTIMATED_KEY),
		"posture_text": UNKNOWN,
		"order_text": UNKNOWN,
	}
	if own:
		model["posture_text"] = upper(_t("POSTURE_" + String(formation.posture).to_upper()))
		model["order_text"] = order_text(formation, place_text)
	return model


## `name` (upper case) with words from the table of `locale` ("" = the game language) replaced
## one by one, only until it fits `max_chars`: "1ST MECHANISED BATTALION" -> "1ST MECH
## BATTALION" -> "1ST MECH BN". Words not in the table stay.
static func abbreviate(name: String, max_chars: int, locale := "") -> String:
	var table := ABBREVIATIONS_PL if _language(locale) == "pl" else ABBREVIATIONS_EN
	var result := name
	for pair in table:
		if result.length() <= max_chars:
			break
		var words := result.split(" ")
		for i in words.size():
			if words[i] == pair[0]:
				words[i] = pair[1]
		result = " ".join(words)
	return result


## Upper case that also covers the Polish diacritics, whatever the engine's case tables do.
static func upper(text: String) -> String:
	var result := text.to_upper()
	for i in _LOWER_PL.length():
		result = result.replace(_LOWER_PL[i], _UPPER_PL[i])
	return result


## "– NO ORDER –" or "→ <destination>" of an own formation.
static func order_text(formation: Formation, place_text := Callable()) -> String:
	if formation.order == null:
		return _t("UNIT_CARD_NO_ORDER")
	var coord: Vector2i = formation.order.destination
	var named := StaffMapPlaceName.named(place_text, coord) if place_text.is_valid() else ""
	if named == "":
		var offset := MapGenerator.axial_to_offset(coord)
		named = "%02d·%02d" % [offset.x + 1, offset.y + 1]
	return "→ " + upper(named)


static func _language(locale: String) -> String:
	var code := locale if locale != "" else TranslationServer.get_locale()
	return code.substr(0, 2).to_lower()


static func _t(key: String) -> String:
	return TranslationServer.translate(key)
