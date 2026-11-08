class_name StaffMapView
extends Node3D
## The map of the staff map scene (TASK-093a, restyled 2.5D in TASK-125): one displaced ground mesh
## – coloured from the map's graphic layers (water, land cover, hillshade; TASK-126,
## StaffMapTerrain) or, for a map without layers, the v0 per-hex land cover, baked hillshade and
## marsh hatch with its land-cover edges – rivers and roads as one
## screen-space line mesh per class, the optional grid and the hover outline. Everything is built
## once from StaffMapLayers / StaffMapRelief (nothing is rebuilt per frame; the hover outline only
## when the hex changes). It only reads the HexGrid and the palette. World: hex units, x east,
## y up, z south. Zoom levels Z0-Z2 fade layers in / out and change line widths over
## palette.fade_seconds.

## Screen pixels per hex unit at camera zoom 1 (the v0 zoom scale, kept for the camera maths).
const UNIT := 20.0
const GROUND_SHADER := preload("res://assets/shaders/staff_map_ground.gdshader")
## Country layer look (TASK-113): a warm dash-dot line and very faint large names.
const COUNTRY_LINE := Color(0.95, 0.66, 0.5, 0.9)
const COUNTRY_LINE_PX := 2.0
const COUNTRY_NAME := Color(0.86, 0.84, 0.74, 0.16)
## World size of one font pixel of a country name (hex units): 128 px -> ~2.6 hexes tall.
const COUNTRY_NAME_PIXEL := 0.02
const COUNTRY_PRIORITY := 14
const NO_HEX := Vector2i(-100000, -100000)
## Vertex spacing of the layered terrain mesh (hex units): fine enough to follow the relief,
## which is linear between hex centres.
const TERRAIN_STEP := 0.5

## The one-time warning for a map drawn in the v0 hex look has been given.
static var _fallback_warned := false

var _grid: HexGrid
var _palette: StaffMapPalette
var _relief: StaffMapRelief
var _ground_material: ShaderMaterial
var _terrain: StaffMapTerrain
var _grid_lines: MeshInstance3D
var _hover_outline: MeshInstance3D
var _hover_fill: MeshInstance3D
var _hovered := NO_HEX
var _countries: Node3D
## name -> {"node", "material", "widths": PackedFloat32Array, "extra": float, "alpha", "width",
## "from_alpha", "from_width", "to_alpha", "to_width"}
var _layers := {}
var _level := -1
var _fade := 1.0  # 0..1 progress of the current fade
var _gain := 1.0
var _gain_from := 1.0
var _gain_to := 1.0

## Fully covered rectangle: ground and lines are clipped to it so the left / right edge is straight.
var _edge_rect := Rect2()


func _init() -> void:
	name = "StaffMapView"


## Builds every layer for `grid`; `hex_spacing_m` = distance between hex centres in metres. With
## a `map` that carries graphic layers (TASK-126) the terrain is drawn from them (water, cover,
## relief in one textured surface, no per-hex fill or edge lines); otherwise the v0 hex look, with
## a one-time warning for a map without layers.
func build(
	grid: HexGrid, palette: StaffMapPalette, hex_spacing_m := 5000.0, map: ImportedMap = null
) -> void:
	_grid = grid
	_palette = palette
	var unit_m := hex_spacing_m / Hex.SQRT3
	_relief = StaffMapRelief.new(
		grid,
		unit_m,
		palette.relief_exaggeration,
		palette.hillshade_azimuth,
		palette.hillshade_altitude,
		palette.hillshade_z_factor
	)
	_edge_rect = StaffMapLayers.straight_rect(grid)
	_terrain = StaffMapTerrain.from_map(map, palette)
	if _terrain != null:
		_build_terrain_ground()
	else:
		if map != null and not _fallback_warned:
			_fallback_warned = true
			push_warning(
				(
					"StaffMapView: map '%s' has no usable graphic layers – drawing the v0 hex look"
					% map.id
				)
			)
		var classes := {}
		for c: Vector2i in StaffMapLayers.sea_tiles(grid, palette.sea_max_m):
			classes[c] = StaffMapPalette.SEA
		_build_ground(StaffMapLayers.fills(grid, classes))
		_build_edges(StaffMapLayers.borders(grid, classes))
	_build_strokes(hex_spacing_m / 1000.0)
	var grid_mesh := StaffMapLines.segments_mesh(
		_drape(StaffMapLayers.clip_segments(StaffMapLayers.grid_lines(grid), _edge_rect))
	)
	var grid_colour := Color(
		palette.grid, linear_alpha(palette.grid, palette.grid.a, palette.map_land)
	)
	_grid_lines = _add_line_node("Grid", grid_mesh, grid_colour, palette.grid_px, 11)
	_grid_lines.visible = false
	_hover_fill = MeshInstance3D.new()
	_hover_fill.name = "HoverFill"
	var fill_material := StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.no_depth_test = true
	fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill_material.albedo_color = Color(
		palette.ui_amber, linear_alpha(palette.ui_amber, palette.hover_fill_alpha, palette.map_land)
	)
	fill_material.render_priority = 12
	_hover_fill.material_override = fill_material
	_hover_fill.visible = false
	add_child(_hover_fill)
	_hover_outline = _add_line_node(
		"HoverOutline", ArrayMesh.new(), palette.ui_amber, palette.hover_outline_px, 13
	)
	_hover_outline.visible = false
	set_zoom_level(1, true)


## The renderer blends in linear light, which makes a faint overlay much stronger than the same
## alpha in the reference (sRGB, CSS). The alpha that gives over `ground` the sRGB-space mix of
## `alpha` (by luminance).
static func linear_alpha(colour: Color, alpha: float, ground: Color) -> float:
	var wanted := ground.lerp(colour, alpha).srgb_to_linear().get_luminance()
	var below := ground.srgb_to_linear().get_luminance()
	var above := colour.srgb_to_linear().get_luminance()
	if absf(above - below) < 0.0001:
		return alpha
	return clampf((wanted - below) / (above - below), 0.0, 1.0)


## Country borders (dash-dot along hex edges) and one faint name per country (TASK-113), baked
## once like the other layers; the toggle only flips `visible`. No-op for a map without countries.
func build_countries(map: ImportedMap) -> void:
	if _countries != null:
		_countries.queue_free()
		_countries = null
	if map.country_rows.is_empty():
		return
	_countries = Node3D.new()
	_countries.name = "Countries"
	add_child(_countries)
	var pieces: Array = []
	for line in map.border_lines:  # the real border ways, world units (hex size 1)
		for piece in StaffMapLayers.clip_polyline(line, _edge_rect):
			for dash in StaffMapCountries.dashes(piece):
				pieces.append(_drape_line(dash))
	var border := MeshInstance3D.new()
	border.name = "CountryBorders"
	border.mesh = StaffMapLines.polylines_mesh(pieces)
	border.material_override = StaffMapLines.material(
		COUNTRY_LINE, COUNTRY_LINE_PX, COUNTRY_PRIORITY
	)
	border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	border.extra_cull_margin = 16384.0
	_countries.add_child(border)
	var anchors := StaffMapCountries.name_anchors(map, 1.0)
	for iso: String in anchors:
		_countries.add_child(_country_name(iso, anchors[iso]))


func set_countries_visible(value: bool) -> void:
	if _countries != null:
		_countries.visible = value


func countries_visible() -> bool:
	return _countries != null and _countries.visible


## Re-translates the country names (language switch).
func refresh_country_names() -> void:
	if _countries == null:
		return
	for child in _countries.get_children():
		var label := child as Label3D
		if label != null:
			label.text = tr(StaffMapCountries.NAMES.get(label.name, label.name)).to_upper()


func _country_name(iso: String, at: Vector2) -> Label3D:
	var label := Label3D.new()
	label.name = iso
	label.text = tr(StaffMapCountries.NAMES.get(iso, iso)).to_upper()
	label.font = HudTheme.display(700, 1)
	label.font_size = 128
	label.pixel_size = COUNTRY_NAME_PIXEL
	label.modulate = COUNTRY_NAME
	label.outline_size = 0
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.render_priority = COUNTRY_PRIORITY - 1
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # lies on the map, north up
	label.position = _relief.surface_point(at) + Vector3(0.0, 0.05, 0.0)
	return label


## True when the terrain is drawn from the map's graphic layers (TASK-126), false for the v0 hex
## look.
func uses_graphic_layers() -> bool:
	return _terrain != null


func terrain() -> StaffMapTerrain:
	return _terrain


func relief() -> StaffMapRelief:
	return _relief


## Rectangle the camera may show, in world pixels (hex units * UNIT, x east / y south).
func world_bounds() -> Rect2:
	var rect := StaffMapLayers.bounds(_grid)
	return Rect2(rect.position * UNIT, rect.size * UNIT)


func has_tile(c: Vector2i) -> bool:
	return _grid.has_tile(c)


func set_grid_visible(value: bool) -> void:
	_grid_lines.visible = value


func grid_visible() -> bool:
	return _grid_lines.visible


## Outlines hex `c` (amber line + faint fill, draped on the relief); off the map hides it.
func highlight(c: Vector2i) -> void:
	var on := _grid.has_tile(c)
	_hover_outline.visible = on
	_hover_fill.visible = on
	if not on or c == _hovered:
		_hovered = c if on else NO_HEX
		return
	_hovered = c
	var ring := _drape_line(StaffMapLayers.outline(c))
	_hover_outline.mesh = StaffMapLines.polylines_mesh([ring])
	var centre := _relief.surface_point(_centre(c))
	var triangles := PackedVector3Array()
	for k in 6:
		triangles.append_array([centre, ring[k], ring[k + 1]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_hover_fill.mesh = mesh


func hovered() -> Vector2i:
	return _hovered


## Zoom level 0 / 1 / 2: layer opacity, line widths and the hillshade gain move to that level's
## values over palette.fade_seconds (`instant` jumps there).
func set_zoom_level(level: int, instant := false) -> void:
	if level == _level and not instant:
		return
	_level = level
	for layer: Dictionary in _layers.values():
		var widths: PackedFloat32Array = layer["widths"]
		var target: float = widths[level] if widths.size() > level else 0.0
		layer["from_alpha"] = layer["alpha"]
		layer["from_width"] = layer["width"]
		layer["to_alpha"] = 1.0 if target > 0.0 else 0.0
		layer["to_width"] = (target + float(layer["extra"])) if target > 0.0 else layer["width"]
	_gain_from = _gain
	_gain_to = _palette.hillshade_contrast * (_palette.hillshade_far_gain if level == 0 else 1.0)
	_fade = 0.0
	_advance(1.0 if instant else 0.0)


func zoom_level() -> int:
	return _level


## Screen scale (pixels per hex unit) and pitch: keeps the marsh hatch tile constant on screen.
func set_view_scale(scale: float, pitch: float) -> void:
	var tile := _palette.marsh_hatch_tile
	var world := Vector2(tile.x / scale, tile.y / (scale * cos(deg_to_rad(pitch))))
	_ground_material.set_shader_parameter(&"hatch_tile_world", world)


## Test / tool aid: a layer's node ("RoadT1", "RiverMajor", "EdgeForest", …).
func layer(layer_name: String) -> MeshInstance3D:
	return _layers[layer_name]["node"] if _layers.has(layer_name) else null


func layer_opacity(layer_name: String) -> float:
	return _layers[layer_name]["alpha"]


func layer_width(layer_name: String) -> float:
	return _layers[layer_name]["width"]


func hillshade_gain() -> float:
	return _gain


func _process(delta: float) -> void:
	if _fade < 1.0:
		_advance(delta / maxf(_palette.fade_seconds, 0.001))


func _advance(step: float) -> void:
	_fade = minf(_fade + step, 1.0)
	var t := smoothstep(0.0, 1.0, _fade)
	for layer: Dictionary in _layers.values():
		layer["alpha"] = lerpf(layer["from_alpha"], layer["to_alpha"], t)
		layer["width"] = lerpf(layer["from_width"], layer["to_width"], t)
		var material: ShaderMaterial = layer["material"]
		material.set_shader_parameter(&"opacity", layer["alpha"])
		material.set_shader_parameter(&"width_px", layer["width"])
		(layer["node"] as MeshInstance3D).visible = float(layer["alpha"]) > 0.001
	_gain = lerpf(_gain_from, _gain_to, t)
	_ground_material.set_shader_parameter(&"shade_gain", _gain)


func _build_ground(fills: Dictionary) -> void:
	var vertices := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var keys := fills.keys()
	keys.sort()
	for fill_class: int in keys:
		var colour := _palette.fill(fill_class)
		var marsh := 1.0 if fill_class == Terrain.Type.MARSH else 0.0
		var polygons := StaffMapLayers.clip_polygons(fills[fill_class], _edge_rect)
		for p in StaffMapLayers.triangulate(polygons):
			vertices.append(_relief.surface_point(p))
			colours.append(colour)
			uvs.append(Vector2(_relief.shade_at(p), marsh))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = GROUND_SHADER
	_ground_material.set_shader_parameter(&"marsh_color", _palette.map_marsh)
	_ground_material.set_shader_parameter(&"shade_strength", _palette.hillshade_strength)
	_ground_material.set_shader_parameter(&"hatch_tile_px", _palette.marsh_hatch_tile)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	ground.material_override = _ground_material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


## The layered terrain (TASK-126): a regular grid over the straight map rectangle draped on the
## relief, coloured entirely by the terrain shader from the graphic layers.
func _build_terrain_ground() -> void:
	var columns := maxi(ceili(_edge_rect.size.x / TERRAIN_STEP), 1)
	var rows := maxi(ceili(_edge_rect.size.y / TERRAIN_STEP), 1)
	var vertices := PackedVector3Array()
	vertices.resize((columns + 1) * (rows + 1))
	var k := 0
	for j in rows + 1:
		var y := _edge_rect.position.y + _edge_rect.size.y * j / rows
		for i in columns + 1:
			var x := _edge_rect.position.x + _edge_rect.size.x * i / columns
			vertices[k] = _relief.surface_point(Vector2(x, y))
			k += 1
	var indices := PackedInt32Array()
	indices.resize(columns * rows * 6)
	k = 0
	for j in rows:
		for i in columns:
			var a := j * (columns + 1) + i
			var b := a + columns + 1
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = b
			indices[k + 3] = b
			indices[k + 4] = a + 1
			indices[k + 5] = b + 1
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ground_material = _terrain.material
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	ground.material_override = _ground_material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


func _build_edges(borders: Dictionary) -> void:
	# Forest and town edges first, the shore line over them.
	var order := [
		["EdgeForest", [Terrain.Type.FOREST], 1],
		["EdgeUrban", [Terrain.Type.URBAN], 2],
		["Shore", [Terrain.Type.WATER, StaffMapPalette.SEA], 3],
	]
	for entry: Array in order:
		var segments := PackedVector2Array()
		for fill_class: int in entry[1]:
			if borders.has(fill_class):
				segments.append_array(borders[fill_class])
		var colour := _palette.edge((entry[1] as Array)[0])
		var mesh := StaffMapLines.segments_mesh(
			_drape(StaffMapLayers.clip_segments(segments, _edge_rect))
		)
		_add_layer(entry[0], mesh, colour, _palette.edge_widths, 0.0, entry[2])


func _build_strokes(km_per_step: float) -> void:
	var rivers := {"RiverMinor": [], "RiverNamed": [], "RiverMajor": []}
	for stroke in StaffMapLayers.strokes(_grid, true, _palette.smoothing):
		var km: float = stroke["steps"] * km_per_step
		var key := (
			"RiverMajor"
			if km >= _palette.river_major_min_km
			else ("RiverNamed" if km >= _palette.river_named_min_km else "RiverMinor")
		)
		for piece in StaffMapLayers.clip_polyline(stroke["points"], _edge_rect):
			rivers[key].append(_drape_line(piece))
	var roads := {"RoadT3": [], "RoadT2": [], "RoadT1": []}
	for stroke in StaffMapLayers.strokes(_grid, false, _palette.smoothing):
		var km: float = stroke["steps"] * km_per_step
		var key := (
			"RoadT1"
			if km >= _palette.road_t1_min_km
			else ("RoadT2" if km >= _palette.road_t2_min_km else "RoadT3")
		)
		for piece in StaffMapLayers.clip_polyline(stroke["points"], _edge_rect):
			roads[key].append(_drape_line(piece))
	var p := _palette
	_add_layer(
		"RiverMinor", _lines_mesh(rivers["RiverMinor"]), p.river_minor, p.river_minor_widths, 0.0, 4
	)
	_add_layer(
		"RiverNamed", _lines_mesh(rivers["RiverNamed"]), p.river_named, p.river_named_widths, 0.0, 5
	)
	_add_layer(
		"RiverMajor", _lines_mesh(rivers["RiverMajor"]), p.river_major, p.river_major_widths, 0.0, 6
	)
	_add_layer("RoadT3", _lines_mesh(roads["RoadT3"]), p.road_t3, p.road_t3_widths, 0.0, 7)
	_add_layer("RoadT2", _lines_mesh(roads["RoadT2"]), p.road_t2, p.road_t2_widths, 0.0, 8)
	var t1 := _lines_mesh(roads["RoadT1"])
	_add_layer("RoadT1Casing", t1, p.road_t1_casing, p.road_t1_widths, p.road_t1_casing_px, 9)
	_add_layer("RoadT1", t1, p.road_t1, p.road_t1_widths, 0.0, 10)


func _lines_mesh(lines: Array) -> ArrayMesh:
	return StaffMapLines.polylines_mesh(lines)


func _add_layer(
	layer_name: String,
	mesh: ArrayMesh,
	colour: Color,
	widths: PackedFloat32Array,
	extra: float,
	priority: int
) -> void:
	var node := _add_line_node(layer_name, mesh, colour, 1.0, priority)
	var start := widths[1] + extra if widths.size() > 1 and widths[1] > 0.0 else 1.0
	_layers[layer_name] = {
		"node": node,
		"material": node.material_override,
		"widths": widths,
		"extra": extra,
		"alpha": 0.0,
		"width": start,
		"from_alpha": 0.0,
		"from_width": start,
		"to_alpha": 0.0,
		"to_width": start,
	}


func _add_line_node(
	node_name: String, mesh: ArrayMesh, colour: Color, width: float, priority: int
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = StaffMapLines.material(colour, width, priority)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader moves the vertices in screen space: never cull the mesh by its bounds.
	node.extra_cull_margin = 16384.0
	add_child(node)
	return node


## Map points (pairs) -> points on the relief.
func _drape(points: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		out.append(_relief.surface_point(p))
	return out


func _drape_line(points: PackedVector2Array) -> PackedVector3Array:
	return _drape(points)


func _centre(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c, 1.0)
	return Vector2(w.x, w.z)
