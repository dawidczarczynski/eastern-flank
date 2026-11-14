class_name StaffMapOrders
extends RefCounted
## The issued orders on the staff map (TASK-092d, look: docs/design/operational_map "Orders"):
## one route per ordered formation of the viewed side, posture = line style, 82 % opacity without
## dots. Redrawn from the OperationalState alone (`refresh`), so a scene rebuilt mid-game shows
## the same arrows. The other side's orders stay hidden (fog is TASK-100). Read-only (rule 3).

var _ribbon: StaffMapRouteRibbon
var _marks: StaffMapRouteMarks
var _relief: StaffMapRelief
var _palette: StaffMapPalette
var _movement: OperationalMovement
var _shown: Array[StringName] = []  # formation ids with a drawn route, in draw order


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


## Redraws the orders of `viewer`'s formations from `state`.
func refresh(state: OperationalState, viewer: int) -> void:
	_shown = []
	var lines: Array = []
	var entries: Array[Dictionary] = []
	var colour := StaffMapFormations.side_colour(_palette, viewer).lightened(0.3)
	var opacity := 1.0
	for formation in state.formations:
		if formation.owner_id != viewer or formation.order == null:
			continue
		var preview := StaffMapRoute.preview_in_posture(
			state, formation, formation.order.destination, formation.posture, _movement
		)
		if preview.is_empty() or preview["route"].is_empty():
			continue  # the route vanished (blocked since): nothing to draw
		var style := StaffMapRoute.style(formation.posture, true)
		var geometry := StaffMapRoutePreview.geometry_of(_relief, formation, preview, style)
		lines.append_array(geometry["lines"])
		opacity = style["alpha"]
		_shown.append(formation.id)
		(
			entries
			. append(
				{
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
	if entries.is_empty():
		_ribbon.clear()
		_marks.clear()
		return
	_ribbon.show_lines(lines, colour, opacity)
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
