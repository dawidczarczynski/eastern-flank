class_name ObjectiveMarkers
extends Node3D
## Placeholder markers of the battle's objective hexes (TASK-088): a ring draped along the hex
## edge, a small pennant on a pole near the hex's north corner and an "OBJECTIVE" HUD tag above
## the pole (visible through forest canopy), all in the owner's faction colour (neutral when
## nobody holds it). One ring mesh + two primitive meshes and one material per hex, so the cost
## is a handful of draw calls. The battle controller recolours a hex when an
## `objective_captured` event is played back.

const RING_SHAPE := Vector2(0.9, 0.98)  ## inner / outer radius in hex sizes
const RING_SEGMENTS := 5
const RING_LIFT := 0.04
const RING_ALPHA := 0.85
## Pole position: towards the hex's north corner (OverlayGeometry corner 5 = -Z), in hex sizes.
const POLE_OFFSET := Vector2(0.0, -0.66)
const POLE_HEIGHT := 0.42
const POLE_RADIUS := 0.012
const POLE_COLOR := Color("#2b2d27")
const FLAG_SIZE := Vector3(0.2, 0.12, 0.012)
const TAG_LIFT := 0.08  ## the tag's bottom edge above the pole top, in hex sizes
const TAG_BACKGROUND := Color(14 / 255.0, 16 / 255.0, 13 / 255.0, 0.82)  # as UnitLabel
const TAG_TAB_SIZE := Vector2(4, 13)

var _hex_size := 1.0
## Vector2i -> {ring: ShaderMaterial, flag: StandardMaterial3D, tag: PanelContainer or null,
## tab: ColorRect or null, anchor: Vector3 (world point the tag hangs from)}
var _markers: Dictionary = {}
var _pole_mesh: CylinderMesh
var _pole_material: StandardMaterial3D
var _flag_mesh: BoxMesh


## Builds one marker per objective hex of `state`, coloured by its current owner. `ground`
## returns the drawn terrain height at (x, z) (MapView.mesh_height_at).
## `hud_root` (optional) receives the tags.
func build(state: GameState, hex_size: float, ground: Callable, hud_root: Control = null) -> void:
	_hex_size = hex_size
	for child in get_children():
		child.queue_free()
	for marker: Dictionary in _markers.values():
		if marker["tag"] != null:
			(marker["tag"] as Control).queue_free()
	_markers.clear()
	# The tags follow the camera; the screenshot tool disables the scene's processing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pole_mesh = CylinderMesh.new()
	_pole_mesh.top_radius = POLE_RADIUS * hex_size
	_pole_mesh.bottom_radius = POLE_RADIUS * hex_size
	_pole_mesh.height = POLE_HEIGHT * hex_size
	_pole_mesh.radial_segments = 6
	_pole_mesh.rings = 1
	_pole_material = StandardMaterial3D.new()
	_pole_material.albedo_color = POLE_COLOR
	_pole_material.roughness = 0.8
	_flag_mesh = BoxMesh.new()
	_flag_mesh.size = FLAG_SIZE * hex_size
	for coord: Vector2i in state.objective_owners:
		var color := UiPalette.faction_color(state, state.objective_owners[coord])
		_build_marker(coord, color, ground)
		if hud_root != null:
			_build_tag(coord, color, hud_root)


## An `objective_captured` event is being played back: the hex takes its new owner's colour.
func on_captured(state: GameState, event: Dictionary) -> void:
	set_color(event["coord"], UiPalette.faction_color(state, event["player"]))


## Recolours the marker of `coord` (no-op for a hex without a marker).
func set_color(coord: Vector2i, color: Color) -> void:
	var marker: Dictionary = _markers.get(coord, {})
	if marker.is_empty():
		return
	GroundOverlay.set_color(marker["ring"], Color(color, RING_ALPHA))
	(marker["flag"] as StandardMaterial3D).albedo_color = color
	if marker["tab"] != null:
		(marker["tab"] as ColorRect).color = color


## Current colour of the marker of `coord` (Color(0, 0, 0, 0) without a marker).
func color_of(coord: Vector2i) -> Color:
	var marker: Dictionary = _markers.get(coord, {})
	if marker.is_empty():
		return Color(0, 0, 0, 0)
	return (marker["flag"] as StandardMaterial3D).albedo_color


func _build_marker(coord: Vector2i, color: Color, ground: Callable) -> void:
	var root := Node3D.new()
	root.name = "Objective_%d_%d" % [coord.x, coord.y]
	add_child(root)
	var center := Hex.to_world(coord, _hex_size)
	var center_2d := Vector2(center.x, center.z)

	var ring_points := OverlayGeometry.hex_ring(
		center_2d, RING_SHAPE.x * _hex_size, RING_SHAPE.y * _hex_size, RING_SEGMENTS
	)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = OverlayGeometry.drape_with(ring_points, ground, RING_LIFT)
	var ring_mesh := ArrayMesh.new()
	ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ring_material := GroundOverlay.material(Color(color, RING_ALPHA))
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = ring_mesh
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)

	var base_2d := center_2d + POLE_OFFSET * _hex_size
	var base := Vector3(base_2d.x, float(ground.call(base_2d.x, base_2d.y)), base_2d.y)
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	pole.mesh = _pole_mesh
	pole.material_override = _pole_material
	pole.position = base + Vector3(0.0, _pole_mesh.height * 0.5, 0.0)
	root.add_child(pole)

	var flag_material := StandardMaterial3D.new()
	flag_material.albedo_color = color
	flag_material.roughness = 0.9
	var flag := MeshInstance3D.new()
	flag.name = "Flag"
	flag.mesh = _flag_mesh
	flag.material_override = flag_material
	var flag_size := _flag_mesh.size
	flag.position = (
		base
		+ Vector3(
			flag_size.x * 0.5 + POLE_RADIUS * _hex_size, _pole_mesh.height - flag_size.y * 0.5, 0.0
		)
	)
	root.add_child(flag)
	_markers[coord] = {
		"ring": ring_material,
		"flag": flag_material,
		"tag": null,
		"tab": null,
		"anchor": base + Vector3.UP * (_pole_mesh.height + TAG_LIFT * _hex_size),
	}


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	for marker: Dictionary in _markers.values():
		var tag: Control = marker["tag"]
		if tag == null:
			continue
		var anchor: Vector3 = marker["anchor"]
		if camera == null or camera.is_position_behind(anchor):
			tag.visible = false
			continue
		tag.visible = true
		var screen := camera.unproject_position(anchor)
		tag.position = (screen - Vector2(tag.size.x / 2.0, tag.size.y)).round()


## A small HUD tag (style of UnitLabel): owner-coloured tab + "OBJECTIVE".
func _build_tag(coord: Vector2i, color: Color, hud_root: Control) -> void:
	var tag := PanelContainer.new()
	tag.name = "ObjectiveTag_%d_%d" % [coord.x, coord.y]
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = TAG_BACKGROUND
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 1.0, 1.0, 0.14)
	style.content_margin_left = 2
	style.content_margin_top = 2
	style.content_margin_right = 5
	style.content_margin_bottom = 2
	tag.add_theme_stylebox_override(&"panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 5)
	tag.add_child(row)
	var tab := ColorRect.new()
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.custom_minimum_size = TAG_TAB_SIZE
	tab.color = color
	row.add_child(tab)
	var text := Label.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.text = "OBJECTIVE"  # a translation key, translated by the Label
	text.add_theme_font_override(&"font", HudTheme.mono(600, 1))
	text.add_theme_font_size_override(&"font_size", 10)
	text.add_theme_color_override(&"font_color", UiPalette.HUD_TEXT)
	row.add_child(text)
	hud_root.add_child(tag)
	hud_root.move_child(tag, 0)  # below the HUD panels, like the unit labels
	_markers[coord]["tag"] = tag
	_markers[coord]["tab"] = tab


func _exit_tree() -> void:
	for marker: Dictionary in _markers.values():
		var tag: Control = marker["tag"]
		if tag != null and is_instance_valid(tag):
			tag.queue_free()
