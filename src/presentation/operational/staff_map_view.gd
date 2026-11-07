class_name StaffMapView
extends Node2D
## The paper map of the staff map scene (TASK-093a): flat fills, hillshade, hatch, roads, rivers
## and the optional grid, all built once from StaffMapLayers as cached meshes / Line2D nodes
## (nothing is redrawn per frame). It only reads the HexGrid and the palette. The node is scaled
## by UNIT, so its children work in hex units (centre to corner = 1).

## Screen pixels per hex unit at camera zoom 1.
const UNIT := 20.0

var _grid: HexGrid
var _palette: StaffMapPalette
var _grid_lines: MeshInstance2D
var _outline: Line2D


func _init() -> void:
	name = "StaffMapView"
	scale = Vector2(UNIT, UNIT)


## Builds every layer for `grid`.
func build(grid: HexGrid, palette: StaffMapPalette) -> void:
	_grid = grid
	_palette = palette
	var bounds := StaffMapLayers.bounds(grid)
	var paper := Polygon2D.new()
	paper.name = "Paper"
	paper.color = palette.paper
	paper.polygon = PackedVector2Array(
		[
			bounds.position,
			Vector2(bounds.end.x, bounds.position.y),
			bounds.end,
			Vector2(bounds.position.x, bounds.end.y)
		]
	)
	add_child(paper)
	var fills := StaffMapLayers.fills(grid)
	for terrain: int in Terrain.Type.values():
		if not fills.has(terrain):
			continue
		var colour := palette.fill(terrain as Terrain.Type)
		if colour.a > 0.0:
			var polygons: Array = fills[terrain]
			var triangles := StaffMapLayers.triangulate(polygons)
			_add_mesh("Fill%d" % terrain, Mesh.PRIMITIVE_TRIANGLES, triangles, colour)
	if fills.has(Terrain.Type.MARSH):
		var hatch := StaffMapLayers.hatch(fills[Terrain.Type.MARSH], palette.marsh_hatch_spacing)
		_add_mesh("MarshHatch", Mesh.PRIMITIVE_LINES, hatch, palette.marsh_hatch)
	_add_hillshade()
	# Rivers under roads; each kind is one mesh (thousands of Line2D nodes would be thousands of
	# draw calls).
	var rivers := StaffMapLayers.ribbons(
		StaffMapLayers.rivers(grid, palette.smoothing), palette.river_width
	)
	_add_mesh("Rivers", Mesh.PRIMITIVE_TRIANGLES, rivers, palette.river)
	var roads := StaffMapLayers.ribbons(
		StaffMapLayers.roads(grid, palette.smoothing), palette.road_width
	)
	_add_mesh("Roads", Mesh.PRIMITIVE_TRIANGLES, roads, palette.road)
	var grid_vertices := StaffMapLayers.grid_lines(grid)
	_grid_lines = _add_mesh("Grid", Mesh.PRIMITIVE_LINES, grid_vertices, palette.grid)
	_grid_lines.visible = false
	_outline = Line2D.new()
	_outline.name = "HoverOutline"
	_outline.width = 0.08
	_outline.default_color = palette.hover_outline
	_outline.visible = false
	add_child(_outline)


## Rectangle the camera may show, in world pixels (scene coordinates).
func world_bounds() -> Rect2:
	var rect := StaffMapLayers.bounds(_grid)
	return Rect2(rect.position * UNIT, rect.size * UNIT)


## The hex under a world position (pixels); check `has_tile` before using it.
func hex_at_world(point: Vector2) -> Vector2i:
	return StaffMapLayers.hex_at(point / UNIT)


func has_tile(c: Vector2i) -> bool:
	return _grid.has_tile(c)


func set_grid_visible(value: bool) -> void:
	_grid_lines.visible = value


func grid_visible() -> bool:
	return _grid_lines.visible


## Outlines hex `c`; a hex off the map hides the outline.
func highlight(c: Vector2i) -> void:
	_outline.visible = _grid.has_tile(c)
	if _outline.visible:
		_outline.points = StaffMapLayers.outline(c)


func _add_hillshade() -> void:
	var shade := StaffMapLayers.hillshade(_grid)
	var vertices: PackedVector2Array = shade["vertices"]
	var values: PackedFloat32Array = shade["values"]
	var colours := PackedColorArray()
	for v in values:
		var tint := _palette.shade_light if v > 0.0 else _palette.shade_dark
		colours.append(Color(tint, absf(v) * _palette.shade_strength))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance2D.new()
	instance.name = "Hillshade"
	instance.mesh = mesh
	add_child(instance)


func _add_mesh(
	node_name: String, primitive: Mesh.PrimitiveType, vertices: PackedVector2Array, colour: Color
) -> MeshInstance2D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	if vertices.size() > 0:
		mesh.add_surface_from_arrays(primitive, arrays)
	var instance := MeshInstance2D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.self_modulate = colour
	add_child(instance)
	return instance
