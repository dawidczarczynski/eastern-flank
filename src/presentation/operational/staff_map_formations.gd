class_name StaffMapFormations
extends RefCounted
## Pure view rules of the formation counters on the staff map (TASK-092b): own / enemy relative
## to the viewer, the 5-segment strength gauge, the short designation, the viewer side from the
## command line, the stack declutter and Tab cycling. No nodes – tested headless.
##
## Declutter rule: counters of the same owner whose projected screen centres are closer than
## STACK_PX form one stack (greedy in placement order: a counter joins the first earlier stack
## leader of its owner within the radius, otherwise it leads a new stack). A stack shows one
## counter – the selected member if any, else the leader – with a count badge; the others are
## hidden and not pickable. Own and enemy counters never stack (shape and colour of the shown
## counter must stay true). The reference's Z0 "brigade counters x n" aggregation is not adopted:
## one counter per formation on every zoom level, the stack takes care of zoomed-out clutter.

const OWN := &"own"
const ENEMY := &"enemy"
const SEGMENTS := 5
## Two counters of one owner closer than this (screen px) stack.
const STACK_PX := 24.0
## The side the human plays when the command line names none (TASK-094 moves it to the session).
const DEFAULT_SIDE := &"nato"
const SIDE_ARG := "--side="


## One view function decides friend or foe (TASK-114 turns it into stance(country, side)).
static func viewer_relation(owner_id: int, viewer_player: int) -> StringName:
	return OWN if owner_id == viewer_player else ENEMY


## Lit segments of the 5-segment gauge: strength / max rounded to the nearest fifth (halves up),
## at least one while anything is left: 40 / 30 / 20 / 10 of 40 -> 5 / 4 / 3 / 1.
static func lit_segments(strength: int, max_strength: int) -> int:
	if strength <= 0 or max_strength <= 0:
		return 0
	@warning_ignore("integer_division")
	var lit := (2 * SEGMENTS * strength + max_strength) / (2 * max_strength)
	return clampi(lit, 1, SEGMENTS)


## Low strength: below half.
static func is_low(strength: int, max_strength: int) -> bool:
	return strength * 2 < max_strength


## Gauge colour: strength.high from 75 %, strength.mid from 50 %, ui.alert below.
static func strength_colour(strength: int, max_strength: int, palette: StaffMapPalette) -> Color:
	if strength * 4 >= max_strength * 3:
		return palette.strength_high
	if strength * 2 >= max_strength:
		return palette.strength_mid
	return palette.ui_alert


## Short designation "<battalion number>/<parent number>", e.g. "1/15" for the 1st Mechanised
## Battalion of the 15th Mechanised Brigade; read from the untranslated names.
static func designation(display_name: String, parent: String) -> String:
	var own := _leading_number(display_name)
	var higher := _leading_number(parent)
	if own == "":
		return higher
	return own if higher == "" else "%s/%s" % [own, higher]


## The player the human views the map as: `--side=<side id>` among the user arguments, else
## DEFAULT_SIDE, else player 0.
static func viewer_from_args(args: PackedStringArray, player_sides: Array[StringName]) -> int:
	var wanted := DEFAULT_SIDE
	for arg in args:
		if arg.begins_with(SIDE_ARG):
			wanted = StringName(arg.substr(SIDE_ARG.length()).to_lower())
	var index := player_sides.find(wanted)
	if index < 0:
		if wanted != DEFAULT_SIDE:
			push_warning("Staff map: unknown side '%s', using the default" % wanted)
		index = maxi(player_sides.find(DEFAULT_SIDE), 0)
	return index


## Stack leader index for every point (see the declutter rule in the header).
static func stack_leaders(
	points: Array[Vector2], owners: Array[int], radius := STACK_PX
) -> PackedInt32Array:
	var leaders := PackedInt32Array()
	var heads: Array[int] = []
	for i in points.size():
		var leader := i
		for head in heads:
			if owners[head] == owners[i] and points[head].distance_to(points[i]) < radius:
				leader = head
				break
		if leader == i:
			heads.append(i)
		leaders.append(leader)
	return leaders


## The id after `current` in `ids` (wrapping); the first one when `current` is not in the list.
static func next_in_cycle(ids: Array[StringName], current: StringName) -> StringName:
	if ids.is_empty():
		return &""
	var index := ids.find(current)
	return ids[(index + 1) % ids.size()] if index >= 0 else ids[0]


static func _leading_number(text: String) -> String:
	var digits := ""
	for ch in text:
		if ch < "0" or ch > "9":
			break
		digits += ch
	return digits
