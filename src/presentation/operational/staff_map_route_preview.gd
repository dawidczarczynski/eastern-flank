class_name StaffMapRoutePreview
extends RefCounted
## Route preview of the staff map (TASK-092c): for the selected own formation and the hex under
## the cursor it plans the route (StaffMapRoute, OperationalRoutes) and shows the ribbon, dots,
## per-turn stops, target and cursor label. Read-only: it never executes a command (rule 3).
## Hover is debounced: a new hex is planned at most every DEBOUNCE_MSEC, the last one always.

const DEBOUNCE_MSEC := 60
const OFF := Vector2i(-100000, -100000)

var _ribbon: StaffMapRouteRibbon
var _marks: StaffMapRouteMarks
var _relief: StaffMapRelief
var _palette: StaffMapPalette
var _movement: OperationalMovement
var _state: OperationalState
var _formation_id: StringName = &""
var _hex := OFF
var _dirty := false
var _last_msec := -DEBOUNCE_MSEC
var _shown := {}  # the last preview() result (for tests and the panel)
var _plans := 0


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


## The previewed formation (&"" or not found: no preview). `state` is the live OperationalState.
func set_formation(state: OperationalState, formation_id: StringName) -> void:
	_state = state
	_formation_id = formation_id
	var formation := _formation()
	if formation != null:
		var colour := StaffMapFormations.side_colour(_palette, formation.owner_id)
		_marks.colour = colour.lightened(0.5)
	_request()


## The hex under the cursor (OFF / no tile: hides the preview).
func set_hex(hex: Vector2i) -> void:
	if hex == _hex:
		return
	_hex = hex
	_request()


## The state changed under the preview (turn ended, formation moved): plan again.
func invalidate() -> void:
	_request()


## Applies a pending change once the debounce time has passed; call every frame (cheap).
func tick(now_msec: int) -> void:
	if _dirty and now_msec - _last_msec >= DEBOUNCE_MSEC:
		rebuild(now_msec)


## Plans and draws at once.
func rebuild(now_msec := Time.get_ticks_msec()) -> void:
	_dirty = false
	_last_msec = now_msec
	_shown = {}
	var formation := _formation()
	if formation == null or _hex == OFF or _state == null or not _state.grid.has_tile(_hex):
		_hide()
		return
	var preview := StaffMapRoute.preview_in_posture(
		_state, formation, _hex, formation.posture, _movement
	)
	_plans += 1
	if preview.is_empty():
		_hide()
		return
	_shown = preview
	if preview["route"].is_empty():
		_ribbon.clear()
		_marks.show_unreachable(_anchor(_hex), tr_reason(preview["reason"]))
		return
	_show_route(formation, preview)


## Last previewed route data ({} when nothing is shown).
func shown() -> Dictionary:
	return _shown


func plans_made() -> int:
	return _plans


func is_pending() -> bool:
	return _dirty


## Cursor label of a preview: "<cost> PTS · <turns> · <stop reason>".
static func label_text(preview: Dictionary) -> String:
	var turns: int = preview["turns"]
	var stop: StringName = preview["stop"]
	var stop_key := "ROUTE_CONTACT" if stop == OperationalRoutes.STOP_CONTACT else "ROUTE_ARRIVED"
	if stop == OperationalRoutes.STOP_OUT_OF_POINTS:
		stop_key = "ROUTE_STALLED"
	var turns_text := _tr_static("%d TURNS") % turns
	return (
		"%s · %s · %s" % [_tr_static("%d PTS") % preview["cost"], turns_text, _tr_static(stop_key)]
	)


static func tr_reason(reason: String) -> String:
	return _tr_static(reason)


static func _tr_static(key: String) -> String:
	return TranslationServer.translate(key)


func _show_route(formation: Formation, preview: Dictionary) -> void:
	var style := StaffMapRoute.style(formation.posture, false)
	var geometry := geometry_of(_relief, formation, preview, style)
	_ribbon.show_lines(geometry["lines"], _marks.colour)
	_marks.show_route(
		geometry["dots"],
		geometry["stops"],
		geometry["target"],
		label_text(preview),
		geometry["before"],
		style
	)


## The drawable geometry of a previewed or issued route of `formation` on `relief`: {lines
## (Array of PackedVector3Array: the smoothed line, cut into dashes for a dashed style), dots,
## stops (Array of {at, before, after, text}), target, before (the point before the target)}.
static func geometry_of(
	relief: StaffMapRelief, formation: Formation, preview: Dictionary, style: Dictionary
) -> Dictionary:
	var route: Array[Vector2i] = preview["route"]
	var smooth := StaffMapRoute.smoothed_line(formation.coord, route)
	var pieces: Array = [smooth]
	if style["dashed"]:
		pieces = StaffMapRoute.dashes(smooth, StaffMapRoute.DASH_ON, StaffMapRoute.DASH_OFF)
	var lines: Array = []
	for piece: PackedVector2Array in pieces:
		var line := PackedVector3Array()
		for p in piece:
			line.append(relief.surface_point(p))
		lines.append(line)
	var dots := PackedVector3Array()
	for hex in route:
		dots.append(_anchor_at(relief, hex))
	var hexes: Array[Vector2i] = [formation.coord]
	hexes.append_array(route)
	var stops: Array[Dictionary] = []
	var stop_hexes: Array[Vector2i] = preview["stops"]
	for i in stop_hexes.size():
		if i == stop_hexes.size() - 1 and stop_hexes[i] == route[route.size() - 1]:
			continue  # the target marker stands there
		var k := hexes.find(stop_hexes[i])
		if k < 0:
			continue
		(
			stops
			. append(
				{
					"at": _anchor_at(relief, hexes[k]),
					"before": _anchor_at(relief, hexes[maxi(k - 1, 0)]),
					"after": _anchor_at(relief, hexes[mini(k + 1, hexes.size() - 1)]),
					"text": "+%d" % (i + 1),
				}
			)
		)
	return {
		"lines": lines,
		"dots": dots,
		"stops": stops,
		"target": _anchor_at(relief, route[route.size() - 1]),
		"before": _anchor_at(relief, hexes[maxi(hexes.size() - 2, 0)]),
	}


func _hide() -> void:
	_ribbon.clear()
	_marks.clear()


func _request() -> void:
	_dirty = true


func _formation() -> Formation:
	if _state == null or _formation_id == &"":
		return null
	return _state.get_formation(_formation_id)


func _anchor(hex: Vector2i) -> Vector3:
	return _anchor_at(_relief, hex)


static func _anchor_at(relief: StaffMapRelief, hex: Vector2i) -> Vector3:
	return relief.surface_point(StaffMapRoute.centre(hex))
