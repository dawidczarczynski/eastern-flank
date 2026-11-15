class_name StaffMapRoutePreview
extends RefCounted
## Route preview of the staff map (TASK-092c): for the selected own formation and the hex under
## the cursor it plans the route (StaffMapRoute, OperationalRoutes) and shows the ribbon, dots,
## per-turn stops, target and cursor label. Read-only: it never executes a command (rule 3).
## Hover is debounced: a new hex is planned at most every DEBOUNCE_MSEC, the last one always.

const DEBOUNCE_MSEC := 60
const ALT_LINE_PX := 1.3
const ALT_OPACITY := 0.6
const OFF := Vector2i(-100000, -100000)

var _ribbon: StaffMapRouteRibbon
var _marks: StaffMapRouteMarks
var _relief: StaffMapRelief
var _palette: StaffMapPalette
var _movement: OperationalMovement
var _state: OperationalState
var _formation_id: StringName = &""
var _hex := OFF
var _posture_override: StringName = &""
var _shown_posture: StringName = &""
var _dirty := false
var _last_msec := -DEBOUNCE_MSEC
var _shown := {}  # the last preview() result (for tests and the panel)
var _plans := 0
var _flowing := false
var _alt_ribbon: StaffMapRouteRibbon  # the thin line of the other posture (TASK-153 stage 2)
var _alt_plans := 0
var _extras := {}  # the last shown {ghost, conflict, alternative}


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
	marks.muted = palette.ui_muted
	marks.panel = palette.map_void
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


## Previews the route in `posture` instead of the default one of a left click (the order ring's
## hovered slot); &"" = the default: attack on an enemy-held hex, else march.
func set_posture(posture: StringName) -> void:
	if posture == _posture_override:
		return
	_posture_override = posture
	_request()


## The ribbon of the alternative-posture line (thin and faint, under the main line).
func set_alt_ribbon(ribbon: StaffMapRouteRibbon) -> void:
	_alt_ribbon = ribbon
	ribbon.set_thin(ALT_LINE_PX)


## The ghost / conflict / alternative of the last shown preview ({} entries when absent).
func extras() -> Dictionary:
	return _extras


func alt_plans_made() -> int:
	return _alt_plans


## The dashes flow while the player is aiming (TASK-153); idle previews stand still.
func set_flowing(flowing: bool) -> void:
	_flowing = flowing
	if _ribbon.visible:
		_ribbon.set_flowing(flowing)


## Screen pixels per map unit (the flowing dashes keep their pitch on screen).
func set_line_scale(px_per_unit: float) -> void:
	_ribbon.set_scale_px(px_per_unit)
	if _alt_ribbon != null:
		_alt_ribbon.set_scale_px(px_per_unit)


## The posture of the last shown preview.
func shown_posture() -> StringName:
	return _shown_posture


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
	_shown_posture = (
		_posture_override
		if _posture_override != &""
		else StaffMapOrderRingModel.default_posture(_state, formation, _hex)
	)
	var preview := StaffMapRoute.preview_in_posture(
		_state, formation, _hex, _shown_posture, _movement
	)
	_plans += 1
	if preview.is_empty():
		_hide()
		return
	_shown = preview
	if preview["route"].is_empty():
		_ribbon.clear()
		_extras = {}
		if _alt_ribbon != null:
			_alt_ribbon.clear()
		var reason: String = preview["reason"]
		var closed := (
			StaffMapBorders.closed_info(_state, formation, _hex)
			if reason == StaffMapRoute.REASON_CLOSED
			else {}
		)
		if closed.is_empty():
			_marks.show_unreachable(_anchor(_hex), tr_reason(reason))
		else:
			_show_closed(formation, closed)
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


## The cursor label of the aimed route: "<cost> PTS · <turns> · <stop>" and, while the side to
## move aims, "ORDERS LEFT n / m"; with no orders left the reason instead (the click is refused).
static func cursor_label(
	state: OperationalState, formation: Formation, preview: Dictionary
) -> String:
	if formation.owner_id != state.current_player:
		return label_text(preview)
	if state.orders_left() <= 0:
		return StaffMapOrderRingModel.reason_text(StaffMapOrderGesture.REASON_NO_ORDERS).to_upper()
	return (
		"%s · %s"
		% [label_text(preview), StaffMapOrders.orders_left_text(state, formation.owner_id)]
	)


## The gesture's verdict of a full `preview` (StaffMapRoute.preview_in_posture, {} = the
## formation's own hex): {valid, reason, incident} with `incident` = the route has border
## warnings (the prompt must confirm). View-only reading of the planner, no rule.
static func verdict_of(
	state: OperationalState, formation: Formation, preview: Dictionary
) -> Dictionary:
	if preview.is_empty():
		return {"valid": false, "reason": StaffMapRoute.REASON_NO_ROUTE, "incident": false}
	var route: Array[Vector2i] = preview["route"]
	if route.is_empty():
		return {"valid": false, "reason": preview["reason"], "incident": false}
	return {
		"valid": true,
		"reason": "",
		"incident": not StaffMapBorders.warnings(state, formation, route).is_empty(),
	}


## The cheap verdict of hovering `hex` (no route search: only the reachability rules).
static func quick_verdict(
	state: OperationalState, formation: Formation, hex: Vector2i, posture_id: StringName
) -> Dictionary:
	var posture := OperationalPosture.find(posture_id)
	var avoids := posture == null or posture.avoids_contact
	var reason := StaffMapRoute.unreachable_reason(state, formation, hex, avoids)
	return {"valid": reason == "", "reason": reason, "incident": false}


static func tr_reason(reason: String) -> String:
	return _tr_static(reason)


static func _tr_static(key: String) -> String:
	return TranslationServer.translate(key)


func _show_route(formation: Formation, preview: Dictionary) -> void:
	var verdict := verdict_of(_state, formation, preview)
	_extras = {}
	var extras := {}
	var ghost := StaffMapOrderExtras.ghost(preview, verdict)
	if not ghost.is_empty():
		_extras["ghost"] = ghost
		extras["ghost"] = {"at": _anchor(ghost["hex"]), "text": ghost["text"]}
	var conflict := StaffMapOrderExtras.conflict(_state, formation, _hex)
	if not conflict.is_empty():
		_extras["conflict"] = conflict
		extras["conflict"] = {"at": _anchor(_hex), "text": conflict["text"]}
	_show_alternative(formation, preview)
	var attack := StaffMapRoute.is_attack(_state, formation, _hex, _shown_posture)
	var style := StaffMapRoute.style(_shown_posture, false, attack)
	var geometry := geometry_of(_relief, formation, preview)
	_ribbon.show_lines(geometry["lines"], _marks.colour, 1.0, StaffMapRouteRibbon.kind_of(style))
	_ribbon.set_flowing(_flowing)
	_marks.show_route(
		geometry["dots"],
		geometry["stops"],
		geometry["target"],
		cursor_label(_state, formation, preview),
		geometry["before"],
		style,
		warning_marks(_state, _relief, formation, preview["route"]),
		extras
	)


## The thin line of the other posture (march vs advance) when its route differs; its plan runs
## here, so it is debounced with the main one (DEBOUNCE_MSEC).
func _show_alternative(formation: Formation, preview: Dictionary) -> void:
	if _alt_ribbon == null:
		return
	_alt_plans += 1
	var alt := StaffMapOrderExtras.alternative(
		_state, formation, _hex, _shown_posture, preview, _movement
	)
	if alt.is_empty():
		_alt_ribbon.clear()
		return
	_extras["alternative"] = alt
	var attack := StaffMapRoute.is_attack(_state, formation, _hex, alt["posture"])
	var style := StaffMapRoute.style(alt["posture"], false, attack)
	var geometry := geometry_of(_relief, formation, alt["preview"])
	_alt_ribbon.show_lines(
		geometry["lines"], _marks.colour, ALT_OPACITY, StaffMapRouteRibbon.kind_of(style)
	)


## Incident warnings of the previewed route (empty when none): {kind, at, text, ends}.
func warnings() -> Array[Dictionary]:
	var formation := _formation()
	if formation == null or _shown.is_empty() or _shown["route"].is_empty():
		return []
	return StaffMapBorders.warnings(_state, formation, _shown["route"])


## The warning markers of a route as {at (point on the relief), text, ends} (TASK-116).
static func warning_marks(
	state: OperationalState, relief: StaffMapRelief, formation: Formation, route: Array[Vector2i]
) -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	var hexes: Array[Vector2i] = [formation.coord]
	hexes.append_array(route)
	for warning in StaffMapBorders.warnings(state, formation, route):
		var k := maxi(hexes.find(warning["at"]), 1)
		(
			marks
			. append(
				{
					"kind": warning["kind"],
					"at": _anchor_at(relief, warning["at"]),
					"before": _anchor_at(relief, hexes[k - 1]),
					"after": _anchor_at(relief, hexes[mini(k + 1, hexes.size() - 1)]),
					"text": warning["text"],
					"chip": warning["chip"],
					"tag": warning["tag"],
					"sentence": warning["sentence"],
				}
			)
		)
	return marks


## The drawable geometry of a previewed or issued route of `formation` on `relief`: {lines
## (Array of one PackedVector3Array: the smoothed line), dots,
## stops (Array of {at, before, after, text}), target, before (the point before the target)}.
static func geometry_of(
	relief: StaffMapRelief, formation: Formation, preview: Dictionary
) -> Dictionary:
	var route: Array[Vector2i] = preview["route"]
	var smooth := StaffMapRoute.smoothed_line(formation.coord, route)
	var line := PackedVector3Array()
	for p in smooth:
		line.append(relief.surface_point(p))
	var lines: Array = [line]  # the dashes are cut in the shader, in screen pixels
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
		"start": _anchor_at(relief, formation.coord),
		"dots": dots,
		"stops": stops,
		"target": _anchor_at(relief, route[route.size() - 1]),
		"before": _anchor_at(relief, hexes[maxi(hexes.size() - 2, 0)]),
	}


## Closed country: the dashed line up to the border (60 %), the cross in the hex outline and the
## plate (the hex line from the formation; the planner has no route into a closed hex).
func _show_closed(formation: Formation, info: Dictionary) -> void:
	var from := StaffMapRoute.centre(formation.coord)
	var to := StaffMapRoute.centre(_hex)
	var steps := maxi(Hex.distance(formation.coord, _hex), 1)
	var points := PackedVector2Array([from])
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var hex := Hex.from_world(Vector3(lerpf(from.x, to.x, t), 0.0, lerpf(from.y, to.y, t)), 1.0)
		if _state.country_at(hex) != _state.country_at(formation.coord):
			break
		points.append(StaffMapRoute.centre(hex))
	_ribbon.clear()
	if points.size() > 1:
		var lines: Array = []
		for piece: PackedVector2Array in StaffMapRoute.dashes(
			points, StaffMapRoute.DASH_ON, StaffMapRoute.DASH_OFF
		):
			var line := PackedVector3Array()
			for p in piece:
				line.append(_relief.surface_point(p))
			lines.append(line)
		_ribbon.show_lines(lines, _marks.colour, 0.6)
	var corners := PackedVector3Array()
	var centre := StaffMapRoute.centre(_hex)
	for k in 6:
		var angle := deg_to_rad(30.0 + 60.0 * k)
		corners.append(_relief.surface_point(centre + Vector2(cos(angle), sin(angle))))
	_marks.show_closed(_anchor(_hex), corners, info["title"], info["reason"])


func _hide() -> void:
	_extras = {}
	_ribbon.clear()
	if _alt_ribbon != null:
		_alt_ribbon.clear()
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
