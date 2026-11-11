class_name RangeOverlayMesh
extends RefCounted
## Geometry of the range overlay (TASK-131b), kept out of MapView: each builder returns
## [vertices: PackedVector3Array, colors: PackedColorArray] for one mesh whose tints are vertex
## colours (assets/shaders/ground_overlay.gdshader multiplies them into the material colour), so
## the whole overlay stays two meshes (fill + outline) however many bands it has.

const COLOR := Color("#f2b134")
const FILL_ALPHA := 0.07
## Range beyond the effective range (reduced hit chance): paler tint and outline.
const EXTENDED_FILL_ALPHA := 0.035
const LINE_ALPHA := 0.95
const EXTENDED_LINE_ALPHA := 0.5
## Hexes in range that direct fire cannot see: a dark wash instead of the amber tint.
const BLOCKED_COLOR := Color(0.03, 0.03, 0.02, 0.4)
const LINE_WIDTH := 0.07
const LINE_SEGMENTS := 3


## Tint of every effective / extended tile (`blocked` ones washed dark). `tile_shape` is a
## Callable (Vector2i) -> PackedVector3Array, the draped triangles of one tile.
static func fill(
	effective: Array[Vector2i],
	extended: Array[Vector2i],
	blocked: Array[Vector2i],
	tile_shape: Callable
) -> Array:
	var blocked_set := {}
	for c in blocked:
		blocked_set[c] = true
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var bands := [
		[effective, Color(COLOR, FILL_ALPHA)],
		[extended, Color(COLOR, EXTENDED_FILL_ALPHA)],
	]
	for band: Array in bands:
		for c: Vector2i in band[0]:
			var shape: PackedVector3Array = tile_shape.call(c)
			vertices.append_array(shape)
			_paint(colors, shape.size(), BLOCKED_COLOR if blocked_set.has(c) else band[1])
	return [vertices, colors]


## Outline ribbons: the pale one around effective + extended (omitted without an extended band)
## and the bright one around the effective range. `drape` is a Callable (PackedVector2Array,
## lift) -> PackedVector3Array; `hex_size` the hex corner distance.
static func outline(
	effective: Array[Vector2i], extended: Array[Vector2i], hex_size: float, drape: Callable
) -> Array:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	if not extended.is_empty():
		var all: Array[Vector2i] = effective + extended
		_ribbons(all, Color(COLOR, EXTENDED_LINE_ALPHA), hex_size, drape, vertices, colors)
	_ribbons(effective, Color(COLOR, LINE_ALPHA), hex_size, drape, vertices, colors)
	return [vertices, colors]


static func _ribbons(
	coords: Array[Vector2i],
	color: Color,
	hex_size: float,
	drape: Callable,
	vertices: PackedVector3Array,
	colors: PackedColorArray
) -> void:
	if coords.is_empty():
		return
	var edges := OverlayGeometry.boundary_edges(coords, hex_size)
	var ribbons: PackedVector3Array = drape.call(
		OverlayGeometry.edge_ribbons(edges, LINE_WIDTH, LINE_SEGMENTS), 0.0
	)
	vertices.append_array(ribbons)
	_paint(colors, ribbons.size(), color)


static func _paint(colors: PackedColorArray, count: int, color: Color) -> void:
	var painted := PackedColorArray()
	painted.resize(count)
	painted.fill(color)
	colors.append_array(painted)
