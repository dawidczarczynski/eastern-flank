class_name StaffMapPostureSwitcherModel
extends RefCounted
## Pure model of the posture strip under the selected own counter (TASK-158, docs/design/
## operational_map/posture_badge_switcher.html variant A): the three segments, which one is
## active, on which side of the tile the strip sits, whether it reacts, what a click means and the
## caption / tooltip texts (move percent and name come from OperationalPosture data). No nodes.

const SEGMENT_SIZE := Vector2(52, 34)
const STRIP_GAP := 38.0  # tile centre to the strip's near edge (4 px under the brackets)
const CAPTION_GAP := 6.0
const CAPTION_HEIGHT := 14.0

const SET := &"set"  # SetPostureCommand
const ARM := &"arm"  # arm the posture for the next target click
const DISARM := &"disarm"  # the armed posture was clicked again
const NONE := &"none"


## The segments left to right: {posture, key (1-based), move_percent, active}.
static func segments(active: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in OperationalPosture.NAMES.size():
		var posture := OperationalPosture.NAMES[i]
		(
			result
			. append(
				{
					"posture": posture,
					"key": i + 1,
					"move_percent": move_percent(posture),
					"active": posture == active,
				}
			)
		)
	return result


## Share of the move points a posture spends per turn (OperationalPosture data); 0 when unknown.
static func move_percent(posture: StringName) -> int:
	var data := OperationalPosture.find(posture)
	return data.move_percent if data != null else 0


## The posture shown as active: the armed one while a formation without an order has one picked,
## otherwise the formation's own.
static func active_posture(formation_posture: StringName, armed: StringName) -> StringName:
	return armed if armed != &"" else formation_posture


## Translated upper-case name of a posture ("MARCH").
static func posture_name(posture: StringName) -> String:
	return TranslationServer.translate("POSTURE_" + String(posture).to_upper()).to_upper()


## "MARCH · 100 %".
static func caption(posture: StringName) -> String:
	return "%s · %d %%" % [posture_name(posture), move_percent(posture)]


## Tooltip of a segment: {title "ATTACK · 75 %", effect (one line), key ("Key 2")}.
static func tooltip(posture: StringName) -> Dictionary:
	var number := OperationalPosture.NAMES.find(posture) + 1
	return {
		"title": caption(posture),
		"effect": TranslationServer.translate("POSTURE_HINT_" + String(posture).to_upper()),
		"key": TranslationServer.translate("Key %d") % number,
	}


## True when the strip reacts: an own formation on its side's turn, no modal, slide or strike mode.
static func enabled(
	own: bool, viewers_turn: bool, modal: bool, sliding: bool, strike_mode: bool
) -> bool:
	return own and viewers_turn and not (modal or sliding or strike_mode)


## True when the strip goes above the tile: the standing order's line leaves downwards (its
## destination is lower on the screen than the tile) or there is no room below.
static func flip_above(
	tile_y: float, has_order: bool, destination_y: float, viewport_height: float
) -> bool:
	if has_order and destination_y > tile_y:
		return true
	var needed := STRIP_GAP + SEGMENT_SIZE.y + CAPTION_GAP + CAPTION_HEIGHT
	return tile_y + needed > viewport_height


## The strip rectangle relative to the tile centre.
static func strip_rect(flipped: bool) -> Rect2:
	var size := Vector2(SEGMENT_SIZE.x * OperationalPosture.NAMES.size(), SEGMENT_SIZE.y)
	var y := -STRIP_GAP - size.y if flipped else STRIP_GAP
	return Rect2(Vector2(-size.x / 2.0, y), size)


## Index of the segment under `point` (relative to the tile centre), -1 outside the strip.
static func segment_at(point: Vector2, flipped: bool) -> int:
	var rect := strip_rect(flipped)
	if not rect.has_point(point):
		return -1
	return clampi(int((point.x - rect.position.x) / SEGMENT_SIZE.x), 0, 2)


## What a click on `clicked` means. A formation with an order keeps it (SET; the same posture is
## NONE). Without one the posture is armed for the next target click; the armed one clicked again
## is dropped (DISARM, as the same key does).
static func click_action(
	has_order: bool, formation_posture: StringName, armed: StringName, clicked: StringName
) -> StringName:
	if has_order:
		return NONE if clicked == formation_posture else SET
	if armed == clicked:
		return DISARM
	return ARM
