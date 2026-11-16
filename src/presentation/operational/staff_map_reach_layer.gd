class_name StaffMapReachLayer
extends Node3D
## The T+1 reach contour of the staff map (TASK-155, order_lines_analysis.md decision 5): while an
## own formation is armed, a thin line around the hexes it can end one march turn on
## (`OperationalRoutes.reach` with the march budget – whatever posture is picked, the contour is
## always the march one). Outer boundary only (`FrontLine.outline`), smoothed like the front line,
## 1.5 px under any zoom, below the counters and the order lines, ignores the mouse, read-only
## (rule 3).
##
## Work happens only when something changed: `refresh` compares a signature of the armed
## formation and the formations on the map – never per frame while the camera rests and the
## simulation stands.

const WIDTH_PX := 1.5
const ALPHA := 0.7
const PRIORITY_LINE := 15
const POSTURE := &"march"

var _relief: StaffMapRelief
var _line: MeshInstance3D
var _signature := ""
var _reach: Dictionary = {}
var _rebuilds := 0


func _init(relief: StaffMapRelief, palette: StaffMapPalette) -> void:
	name = "ReachContour"
	_relief = relief
	_line = MeshInstance3D.new()
	_line.name = "Line"
	var colour := StaffMapFormations.side_colour(palette, 0)
	colour.a = ALPHA
	_line.material_override = StaffMapLines.material(
		colour, WIDTH_PX, PRIORITY_LINE, palette.glow_orders if palette.glow_enabled else 1.0
	)
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.extra_cull_margin = 16384.0
	add_child(_line)
	visible = false


## Shows the contour of `formation` (null or `shown` false hides it) and recomputes it only when
## the armed formation or the formations on the map changed since the last call.
func refresh(state: OperationalState, formation: Formation, shown: bool) -> void:
	var armed := formation != null and shown
	visible = armed
	if not armed:
		return
	var signature := _signature_of(state, formation)
	if signature == _signature:
		return
	_signature = signature
	_rebuilds += 1
	var posture := OperationalPosture.find(POSTURE)
	if posture == null:
		_reach = {}
	else:
		_reach = OperationalRoutes.reach(
			state, formation, OperationalOrders.budget(formation, posture)
		)
	var draped: Array = []
	for loop: PackedVector2Array in FrontLine.outline(_reach):
		var points := PackedVector3Array()
		for p in FrontLine.smooth(loop):
			points.append(_relief.surface_point(p))
		draped.append(points)
	_line.mesh = StaffMapLines.polylines_mesh(draped)


## Number of recomputations so far (tests: nothing recomputes without a change).
func rebuild_count() -> int:
	return _rebuilds


## Hex -> move points of the last contour (tests).
func reach() -> Dictionary:
	return _reach


static func _signature_of(state: OperationalState, formation: Formation) -> String:
	var parts := PackedStringArray(
		[str(formation.id), str(formation.readiness), str(state.turn), str(state.current_player)]
	)
	for f in state.formations:
		parts.append("%d:%d,%d" % [f.owner_id, f.coord.x, f.coord.y])
	return "|".join(parts)
