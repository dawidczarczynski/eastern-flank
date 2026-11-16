class_name StaffMapOrders
extends RefCounted
## The issued orders on the staff map (TASK-092d, look: docs/design/operational_map "Orders"):
## one route per ordered formation of the viewed side, posture = line style, 82 % opacity without
## dots. Redrawn from the OperationalState alone (`refresh`), so a scene rebuilt mid-game shows
## the same arrows. The other side's orders stay hidden (fog is TASK-100). Read-only (rule 3).

const HEAD_RADIUS := 14.0  # screen px within which a click grabs a head
const GHOST_FACTOR := 0.35  # the ghost line's opacity, of the issued one

var _ribbon: StaffMapRouteRibbon
var _marks: StaffMapRouteMarks
var _relief: StaffMapRelief
var _palette: StaffMapPalette
var _movement: OperationalMovement
var _shown: Array[StringName] = []  # formation ids with a drawn route, in draw order
var _fresh_ribbon: StaffMapRouteRibbon  # the order just issued settles here (TASK-153)
var _fresh_id: StringName = &""
var _ghost_id: StringName = &""  # the order being re-aimed: a dim line without marks (TASK-157)
var _heads: Dictionary = {}  # formation id -> the 3D point of its order's head


func _init(
	ribbon: StaffMapRouteRibbon,
	marks: StaffMapRouteMarks,
	relief: StaffMapRelief,
	palette: StaffMapPalette
) -> void:
	_ribbon = ribbon
	_marks = marks
	_relief = relief
	_palette = palette
	_movement = OperationalMovement.shipped()
	marks.amber = palette.ui_amber
	marks.alert = palette.ui_alert
	marks.text_colour = palette.ui_text
	marks.ink = Color(0.05, 0.06, 0.05)


## "ORDERS LEFT 3 / 4": the orders `player` may still issue this turn of the C2 limit (the whole
## limit while it is the other side's move). Translated, upper case.
static func orders_left_text(state: OperationalState, player: int) -> String:
	var total := state.orders_per_turn(player)
	var left := state.orders_left() if player == state.current_player else total
	return (TranslationServer.translate("ORDERS LEFT %d / %d") % [left, total]).to_upper()


## Ordered formations of `player` (the number n of "ORDERS n / m").
static func ordered_count(state: OperationalState, player: int) -> int:
	var n := 0
	for formation in state.formations:
		if formation.owner_id == player and formation.order != null:
			n += 1
	return n


## The ribbon of the order issued last: it is drawn at full opacity and settles to the issued one.
func set_fresh_ribbon(ribbon: StaffMapRouteRibbon) -> void:
	_fresh_ribbon = ribbon


## The next `refresh` draws the order of `formation_id` on the fresh ribbon (&"" = none).
func mark_fresh(formation_id: StringName) -> void:
	_fresh_id = formation_id


func has_fresh() -> bool:
	return _fresh_id != &""


## Settle progress 0 … 1: the fresh line goes from full opacity to the issued one; at 1 it joins the
## other orders again.
func settle(progress: float) -> void:
	if _fresh_ribbon == null or _fresh_id == &"":
		return
	_fresh_ribbon.set_opacity(lerpf(1.0, StaffMapRoute.ISSUED_ALPHA, clampf(progress, 0.0, 1.0)))


## The order of `formation_id` is being re-aimed: the next `refresh` draws it as a dim ghost
## (&"" = none). Returns true when that changed what is drawn.
func set_ghost(formation_id: StringName) -> bool:
	if formation_id == _ghost_id:
		return false
	_ghost_id = formation_id
	return true


## The id of the head nearest to `point` within HEAD_RADIUS screen px ({id: Vector2}); on an exact
## tie the smaller id; &"" when none is in reach. Pure.
static func head_at(point: Vector2, heads: Dictionary) -> StringName:
	var best := &""
	var best_d := HEAD_RADIUS + 0.001
	for id: StringName in heads:
		var d := point.distance_to(heads[id])
		if d < best_d or (is_equal_approx(d, best_d) and best != &"" and String(id) < String(best)):
			best = id
			best_d = d
	return best


## Screen positions of the heads of the drawn orders ({id: Vector2}).
func heads_on_screen() -> Dictionary:
	var out := {}
	for id: StringName in _heads:
		out[id] = _marks.project_point(_heads[id])
	return out


## Screen pixels per map unit for the dash pitch.
func set_line_scale(px_per_unit: float) -> void:
	_ribbon.set_scale_px(px_per_unit)
	if _fresh_ribbon != null:
		_fresh_ribbon.set_scale_px(px_per_unit)


## Redraws the orders of `viewer`'s formations from `state`.
func refresh(state: OperationalState, viewer: int) -> void:
	_shown = []
	_heads = {}
	var groups := {}
	var fresh_groups := {}
	var entries: Array[Dictionary] = []
	var colour := StaffMapFormations.side_colour(_palette, viewer).lightened(0.3)
	var opacity := 1.0
	var ghost_groups: Array[bool] = []
	for formation in state.formations:
		if formation.owner_id != viewer or formation.order == null:
			continue
		var preview := StaffMapRoute.preview_in_posture(
			state, formation, formation.order.destination, formation.posture, _movement
		)
		if preview.is_empty() or preview["route"].is_empty():
			continue  # the route vanished (blocked since): nothing to draw
		var attack := StaffMapRoute.is_attack(
			state, formation, formation.order.destination, formation.posture
		)
		var style := StaffMapRoute.style(formation.posture, true, attack)
		var geometry := StaffMapRoutePreview.geometry_of(_relief, formation, preview)
		var is_ghost := formation.id == _ghost_id and _fresh_ribbon != null
		var is_fresh := (formation.id == _fresh_id or is_ghost) and _fresh_ribbon != null
		var target_groups := fresh_groups if is_fresh else groups
		var kind := StaffMapRouteRibbon.kind_of(style)
		if not target_groups.has(kind):
			target_groups[kind] = []
		target_groups[kind].append_array(geometry["lines"])
		opacity = style["alpha"]
		_shown.append(formation.id)
		_heads[formation.id] = geometry["target"]
		if is_ghost:
			ghost_groups.append(true)
			continue  # the lines are in; a ghost has no marks
		(
			entries
			. append(
				{
					"start": geometry["start"],
					"dots": geometry["dots"],
					"stops": geometry["stops"],
					"target": geometry["target"],
					"before": geometry["before"],
					"warnings":
					StaffMapRoutePreview.warning_marks(state, _relief, formation, preview["route"]),
					"label": "",
					"colour": colour,
					"style": style,
				}
			)
		)
	if entries.is_empty() and fresh_groups.is_empty():
		_ribbon.clear()
		if _fresh_ribbon != null:
			_fresh_ribbon.clear()
		_marks.clear()
		return
	if groups.is_empty():
		_ribbon.clear()
	else:
		_ribbon.show_groups(groups, colour, opacity)
	if _fresh_ribbon != null:
		if fresh_groups.is_empty():
			_fresh_ribbon.clear()
		else:
			_fresh_ribbon.show_groups(fresh_groups, colour, 1.0)
			if not ghost_groups.is_empty():
				_fresh_ribbon.set_opacity(StaffMapRoute.ISSUED_ALPHA * GHOST_FACTOR)
	if entries.is_empty():
		_marks.clear()
	else:
		_marks.show_routes(entries)


## Formation ids whose order is drawn (tests).
func shown_ids() -> Array[StringName]:
	return _shown


## The camera moved: the screen-space marks project again.
func refresh_projection() -> void:
	_marks.refresh()


## Style flags of the route drawn for `formation_id` ({} when none is drawn).
func style_of(formation_id: StringName) -> Dictionary:
	var index := _shown.find(formation_id)
	return _marks.style_of(index) if index >= 0 else {}
