class_name StaffMapCountryLayer
extends RefCounted
## Country borders (dash-dot along the real border ways) and one faint name per country on the
## staff map (TASK-113), baked once under a "Countries" node of the view; the toggle only flips
## `visible`. Split from StaffMapView.

const LINE := Color(0.95, 0.66, 0.5, 0.9)
const LINE_PX := 2.0
const NAME := Color(0.86, 0.84, 0.74, 0.16)
const NAME_PIXEL := 0.02
const PRIORITY := 14

var _node: Node3D
var _relief: StaffMapRelief


## Builds the layer under `parent`; `edge_rect` clips the borders. No-op for a map without
## countries.
func build(parent: Node3D, map: ImportedMap, edge_rect: Rect2, relief: StaffMapRelief) -> void:
	if _node != null:
		_node.queue_free()
		_node = null
	if map.country_rows.is_empty():
		return
	_relief = relief
	_node = Node3D.new()
	_node.name = "Countries"
	parent.add_child(_node)
	var pieces: Array = []
	for line in map.border_lines:  # the real border ways, world units (hex size 1)
		for piece in StaffMapLayers.clip_polyline(line, edge_rect):
			for dash in StaffMapCountries.dashes(piece):
				pieces.append(_drape(dash))
	var border := MeshInstance3D.new()
	border.name = "CountryBorders"
	border.mesh = StaffMapLines.polylines_mesh(pieces)
	border.material_override = StaffMapLines.material(LINE, LINE_PX, PRIORITY)
	border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	border.extra_cull_margin = 16384.0
	_node.add_child(border)
	var anchors := StaffMapCountries.name_anchors(map, 1.0)
	for iso: String in anchors:
		_node.add_child(_country_name(iso, anchors[iso]))


func set_visible_layer(value: bool) -> void:
	if _node != null:
		_node.visible = value


func is_visible_layer() -> bool:
	return _node != null and _node.visible


## Re-translates the country names (language switch).
func refresh_names() -> void:
	if _node == null:
		return
	for child in _node.get_children():
		var label := child as Label3D
		if label != null:
			label.text = tr(StaffMapCountries.NAMES.get(label.name, label.name)).to_upper()


func _drape(points: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		out.append(_relief.surface_point(p))
	return out


func _country_name(iso: String, at: Vector2) -> Label3D:
	var label := Label3D.new()
	label.name = iso
	label.text = tr(StaffMapCountries.NAMES.get(iso, iso)).to_upper()
	label.font = HudTheme.display(700, 1)
	label.font_size = 128
	label.pixel_size = NAME_PIXEL
	label.modulate = NAME
	label.outline_size = 0
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.render_priority = PRIORITY - 1
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # lies on the map, north up
	label.position = _relief.surface_point(at) + Vector3(0.0, 0.05, 0.0)
	return label
