class_name StaffMapOrderExtras
extends RefCounted
## The preview extras around the aimed order line (TASK-153 stage 2, look: docs/design/
## operational_map/order_lines.html D2 / D5 / D6): the destination ghost with "T+n", the
## alternative-posture line, the goal-conflict mark and the far-zoom stub. Pure functions over a
## hand-made state, nothing is drawn here and nothing changes (rule 3).

const SHORT_SCREEN_PX := 28.0  # an order shorter than this on screen is drawn as a stub
const STUB_PX := 20.0  # the stub's length
const STUB_MIN_PX := 8.0  # never shorter than this
const COUNTER_EDGE_PX := 20.0  # a stub starts at the counter's edge

const ALTERNATIVES := {&"march": &"advance", &"advance": &"march"}


## The destination ghost of an aimed order: {hex, text "T+n"} (n = the turn the formation
## arrives, from the forecast); {} for an invalid target or an empty `preview`.
static func ghost(preview: Dictionary, verdict: Dictionary) -> Dictionary:
	if not verdict.get("valid", false) or preview.is_empty() or preview["route"].is_empty():
		return {}
	var route: Array[Vector2i] = preview["route"]
	return {
		"hex": route[route.size() - 1],
		"text": "T+%d" % maxi(int(preview["turns"]), 1),
	}


## The other contact-relevant posture of `posture_id` (march <-> advance); &"" for defend.
static func alternative_posture(posture_id: StringName) -> StringName:
	return ALTERNATIVES.get(posture_id, &"")


## The alternative-posture plan to `hex`: {posture, preview} when its route or turn count differs
## from `main` (the preview in `posture_id`), {} when it is equal, impossible or there is none.
static func alternative(
	state: OperationalState,
	formation: Formation,
	hex: Vector2i,
	posture_id: StringName,
	main: Dictionary,
	movement: OperationalMovement = null
) -> Dictionary:
	var other := alternative_posture(posture_id)
	if other == &"" or main.is_empty() or main["route"].is_empty():
		return {}
	var preview := StaffMapRoute.preview_in_posture(state, formation, hex, other, movement)
	if preview.is_empty() or preview["route"].is_empty():
		return {}
	if preview["route"] == main["route"] and preview["turns"] == main["turns"]:
		return {}
	return {"posture": other, "preview": preview}


## Another own formation that already has an order to `hex`: {formation_id, text}; {} when none.
## View-only scan of `formation.order`, the rules stay as they are.
static func conflict(state: OperationalState, formation: Formation, hex: Vector2i) -> Dictionary:
	for other in state.formations:
		if other == formation or other.owner_id != formation.owner_id or other.order == null:
			continue
		if other.order.destination == hex:
			return {
				"formation_id": other.id,
				"text":
				(
					TranslationServer.translate(
						"%s IS ORDERED HERE – THE SECOND TO ARRIVE IS HALTED"
					)
					% other.display_name.to_upper()
				),
			}
	return {}


## The far-zoom stub of an order from screen point `from` to `to`: {from, to} of the line (it
## starts at the counter's edge, STUB_PX long) when the order is shorter than SHORT_SCREEN_PX,
## else {} (the ordinary line shows). Always at least STUB_MIN_PX long.
static func stub(from: Vector2, to: Vector2) -> Dictionary:
	var length := from.distance_to(to)
	if length >= SHORT_SCREEN_PX:
		return {}
	var along := (to - from).normalized() if length > 0.5 else Vector2.RIGHT
	var start := from + along * COUNTER_EDGE_PX
	return {"from": start, "to": start + along * maxf(STUB_PX, STUB_MIN_PX)}
