class_name RangeText
extends RefCounted
## Weapon ranges as player text (TASK-131b): metres below 1 km, one-decimal km up to 10 km,
## whole km above. Pure and static; the texts are translation keys' English source (numbers
## only), the view translates the words around them.

## A weapon reaching at least this many hexes covers a whole tactical map (largest maps ~30 hexes
## across), so it is shown as "whole map" instead of a huge number of hexes.
const WHOLE_MAP_HEXES := 40


## "500 m", "2.0 km", "35 km".
static func metres(m: int) -> String:
	if m < 1000:
		return "%d m" % m
	if m < 10000:
		return "%.1f km" % (m / 1000.0)
	return "%d km" % roundi(m / 1000.0)


## True when the weapon reaches across any battle map.
static func is_whole_map(definition: UnitDefinition) -> bool:
	return definition.max_hexes() >= WHOLE_MAP_HEXES


## Short form of the card stat: "2.0 km (8 hex)", "35 km (whole map)" (effective range for a
## direct weapon, the maximum for a whole-map one).
static func short_text(definition: UnitDefinition) -> String:
	if is_whole_map(definition):
		return "%s (%s)" % [metres(definition.max_range_m), "whole map"]
	return "%s (%d hex)" % [metres(definition.effective_range_m), definition.effective_hexes()]


## Full line: "2.0 km (8 hex), max 3.0 km"; "35 km (whole map), min 750 m" for artillery with a
## minimum range.
static func line(definition: UnitDefinition) -> String:
	var text := short_text(definition)
	if not is_whole_map(definition) and definition.max_range_m != definition.effective_range_m:
		text += ", max %s" % metres(definition.max_range_m)
	if definition.min_range_m > 0:
		text += ", min %s" % metres(definition.min_range_m)
	return text


## "6 hex (1.5 km)": a distance between two hexes.
static func distance(hexes: int) -> String:
	return "%d hex (%s)" % [hexes, metres(hexes * UnitDefinition.HEX_METRES)]


## "-25 %" for a hit-chance factor below 1, "" at full effect.
static func falloff(factor: float) -> String:
	if factor >= 1.0:
		return ""
	return "-%d %%" % roundi((1.0 - factor) * 100.0)
