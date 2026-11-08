class_name StaffMapFrontLine
extends Node3D
## The front line of the staff map (TASK-093c, look: docs/design/operational_map "Front line"):
## a screen-space ribbon along `FrontLine.edges` with small teeth pointing to the enemy of the
## viewer, and a faint tint of each side's zone (T). Smoothed (midpoints + Chaikin x3) by default,
## the exact hex edges while the grid is shown at Z2. Read-only (rule 3).
##
## Work happens only when something changed: `refresh` compares a signature of the formations,
## the viewer and the visibility, `set_view` the pixel scale, zoom level and variant – never per
## frame while the camera rests. Teeth are spaced in pixels, so a zoom rebuilds them (cheap: a
## few hundred triangles); the pitch is not compensated (the spacing is along the ground).

const WIDTH_PX := [2.4, 3.0, 3.0]
const CASING_EXTRA_PX := 2.4
const TOOTH_LENGTH_PX := 5.5
const TOOTH_BASE_PX := 7.0
const TOOTH_SPACING_PX := 15.0
const TINT_ALPHA := 0.05
const PRIORITY_TINT := 12
const PRIORITY_CASING := 17
const PRIORITY_LINE := 18

var _relief: StaffMapRelief
var _palette: StaffMapPalette
var _casing: MeshInstance3D
var _line: MeshInstance3D
var _teeth: MeshInstance3D
var _tint: MeshInstance3D
var _lines: Array = []  # exact polylines (hex units), cached from the last refresh
var _smooth_lines: Array = []
var _signature := ""
var _viewer := 0
var _scale_px := 0.0
var _level := 1
var _exact := false
var _tint_on := true
var _teeth_scale := -1.0
var _rebuilds := 0
var _tooth_total := 0


func _init(relief: StaffMapRelief, palette: StaffMapPalette) -> void:
	name = "FrontLine"
	_relief = relief
	_palette = palette
	_tint = _triangle_node("Tint", PRIORITY_TINT)
	_casing = _line_node("Casing", Color(0.05, 0.06, 0.05, 0.8), PRIORITY_CASING)
	_line = _line_node("Line", palette.ui_text, PRIORITY_LINE)
	_teeth = _triangle_node("Teeth", PRIORITY_LINE)
	(_teeth.material_override as StandardMaterial3D).albedo_color = palette.ui_text


## Recomputes the line from `state` for `viewer` when the formations, the viewer or `shown`
## changed since the last call; otherwise does nothing.
func refresh(state: OperationalState, viewer: int, shown := true) -> void:
	var signature := _signature_of(state, viewer, shown)
	if signature == _signature:
		return
	_signature = signature
	_viewer = viewer
	visible = shown
	if not shown:
		return
	_rebuilds += 1
	_lines = FrontLine.edges(state)
	_smooth_lines = []
	for line: PackedVector2Array in _lines:
		_smooth_lines.append(FrontLine.smooth(line))
	_tint.mesh = _tint_mesh(FrontLine.ownership(state))
	_apply_lines()
	_teeth_scale = -1.0
	_apply_teeth()


## Camera state: pixels per hex unit, zoom level 0 … 2 and whether the exact hex edges are wanted.
func set_view(scale_px: float, level: int, exact: bool) -> void:
	var width_changed := level != _level
	var variant_changed := exact != _exact
	_level = level
	_exact = exact
	_scale_px = scale_px
	_set_width()
	if variant_changed:
		_apply_lines()
		_teeth_scale = -1.0
	if variant_changed or width_changed or absf(scale_px - _teeth_scale) > _teeth_scale * 0.02:
		_apply_teeth()


func set_tint_visible(value: bool) -> void:
	_tint_on = value
	_tint.visible = value


func is_tint_visible() -> bool:
	return _tint_on


## Number of recomputations so far (tests: nothing recomputes without a change).
func rebuild_count() -> int:
	return _rebuilds


## Exact polylines of the last refresh (tests).
func lines() -> Array:
	return _lines


func is_exact() -> bool:
	return _exact


func tooth_count() -> int:
	return _tooth_total


## Centre-line width of the line at `level` (screen px).
static func width_at(level: int) -> float:
	return WIDTH_PX[clampi(level, 0, 2)]


func _signature_of(state: OperationalState, viewer: int, shown: bool) -> String:
	var parts := PackedStringArray([str(viewer), str(shown), str(state.front_range)])
	for f in state.formations:
		parts.append("%d:%d,%d" % [f.owner_id, f.coord.x, f.coord.y])
	return "|".join(parts)


func _set_width() -> void:
	var width := width_at(_level)
	(_line.material_override as ShaderMaterial).set_shader_parameter(&"width_px", width)
	(_casing.material_override as ShaderMaterial).set_shader_parameter(
		&"width_px", width + CASING_EXTRA_PX
	)


func _apply_lines() -> void:
	var source := _lines if _exact else _smooth_lines
	var draped: Array = []
	for line: PackedVector2Array in source:
		draped.append(_drape(line))
	var mesh := StaffMapLines.polylines_mesh(draped)
	_line.mesh = mesh
	_casing.mesh = mesh
	_set_width()


func _apply_teeth() -> void:
	_teeth_scale = _scale_px
	_tooth_total = 0
	if _scale_px <= 0.0:
		_teeth.mesh = null
		return
	var vertices := PackedVector3Array()
	var source := _lines if _exact else _smooth_lines
	for line: PackedVector2Array in source:
		for tooth in teeth_of(
			line,
			_viewer,
			TOOTH_SPACING_PX / _scale_px,
			TOOTH_LENGTH_PX / _scale_px,
			TOOTH_BASE_PX / _scale_px
		):
			_tooth_total += 1
			for corner: Vector2 in tooth:
				vertices.append(_relief.surface_point(corner))
	_teeth.mesh = _triangles(vertices, PackedColorArray())


## Teeth along `line` (hex units): triangles [base a, base b, tip] every `spacing`, `length` long
## and `base` wide, pointing to the opponent of `viewer` (player 0's zone is on the right of the
## line, FrontLine.edges).
static func teeth_of(
	line: PackedVector2Array, viewer: int, spacing: float, length: float, base: float
) -> Array:
	var teeth: Array = []
	var carried := spacing * 0.5
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var segment := a.distance_to(b)
		if segment < 0.00001:
			continue
		var direction := (b - a) / segment
		var normal := FrontLine.right_normal(a, b)
		var towards := -normal if viewer == 0 else normal
		var at := carried
		while at <= segment:
			var centre := a + direction * at
			var tip := centre + towards * length
			teeth.append(
				[centre - direction * base * 0.5, centre + direction * base * 0.5, tip] as Array
			)
			at += spacing
		carried = at - segment
	return teeth


func _tint_mesh(owners: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	var coords: Array = owners.keys()
	coords.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	for coord: Vector2i in coords:
		var colour := StaffMapFormations.side_colour(_palette, owners[coord] as int)
		colour.a = TINT_ALPHA
		var centre := Hex.to_world(coord, 1.0)
		var middle := Vector2(centre.x, centre.z)
		for k in 6:
			var a := Vector2(centre.x, centre.z) + _corner_offset(k)
			var b := Vector2(centre.x, centre.z) + _corner_offset(k + 1)
			for point: Vector2 in [middle, a, b]:
				vertices.append(_relief.surface_point(point))
				colours.append(colour)
	return _triangles(vertices, colours)


static func _corner_offset(k: int) -> Vector2:
	var angle := PI / 6.0 + k * PI / 3.0
	return Vector2(cos(angle), sin(angle))


func _drape(line: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in line:
		out.append(_relief.surface_point(p))
	return out


static func _triangles(vertices: PackedVector3Array, colours: PackedColorArray) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if not colours.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colours
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _flat_material(colour: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = colour
	m.render_priority = priority
	return m


func _line_node(node_name: String, colour: Color, priority: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.material_override = StaffMapLines.material(colour, WIDTH_PX[1], priority)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 16384.0
	add_child(node)
	return node


func _triangle_node(node_name: String, priority: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.material_override = _flat_material(Color.WHITE, priority)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 16384.0
	add_child(node)
	return node
