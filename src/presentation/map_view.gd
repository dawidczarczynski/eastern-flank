class_name MapView
extends Node3D
## Map view: builds tile geometry from a HexGrid and highlights movement range.
## Primitives for now (hexagonal prisms) – to be replaced with models from assets/models.

## Height of the plane used for picking tiles with the mouse.
const PICK_HEIGHT := 0.2
const TERRAIN_COLORS := {
	Terrain.Type.PLAINS: Color(0.56, 0.71, 0.36),
	Terrain.Type.FOREST: Color(0.24, 0.45, 0.22),
	Terrain.Type.HILLS: Color(0.6, 0.53, 0.38),
	Terrain.Type.WATER: Color(0.2, 0.42, 0.7),
}
const TERRAIN_HEIGHTS := {
	Terrain.Type.PLAINS: 0.2,
	Terrain.Type.FOREST: 0.25,
	Terrain.Type.HILLS: 0.45,
	Terrain.Type.WATER: 0.08,
}

@export var hex_size: float = 1.0

var _grid: HexGrid
var _tiles_root := Node3D.new()
var _highlight_root := Node3D.new()
var _highlight_mesh: CylinderMesh


func _ready() -> void:
	add_child(_tiles_root)
	add_child(_highlight_root)
	var highlight_material := _make_material(Color(1.0, 0.85, 0.2, 0.45), true)
	_highlight_mesh = _make_hex_mesh(hex_size * 0.8, 0.03, highlight_material)


func build(grid: HexGrid) -> void:
	_grid = grid
	for child in _tiles_root.get_children():
		child.queue_free()

	var meshes := {}
	for t: int in TERRAIN_COLORS:
		var material := _make_material(TERRAIN_COLORS[t])
		meshes[t] = _make_hex_mesh(hex_size * 0.96, TERRAIN_HEIGHTS[t], material)

	var tree_mesh := CylinderMesh.new()
	tree_mesh.top_radius = 0.0
	tree_mesh.bottom_radius = 0.22
	tree_mesh.height = 0.7
	tree_mesh.material = _make_material(Color(0.15, 0.32, 0.15))

	for c in grid.coords():
		var t := grid.get_terrain(c)
		var h: float = TERRAIN_HEIGHTS[t]
		var tile := MeshInstance3D.new()
		tile.mesh = meshes[t]
		tile.position = Hex.to_world(c, hex_size) + Vector3.UP * (h / 2.0)
		_tiles_root.add_child(tile)
		if t == Terrain.Type.FOREST:
			var tree := MeshInstance3D.new()
			tree.mesh = tree_mesh
			tree.position = tile_top_position(c) + Vector3(0.5, 0.35, -0.25)
			_tiles_root.add_child(tree)


func tile_top_position(c: Vector2i) -> Vector3:
	var h: float = TERRAIN_HEIGHTS.get(_grid.get_terrain(c), 0.0)
	return Hex.to_world(c, hex_size) + Vector3.UP * h


func center() -> Vector3:
	var sum := Vector3.ZERO
	var tiles := _grid.coords()
	for c in tiles:
		sum += Hex.to_world(c, hex_size)
	return sum / maxf(tiles.size(), 1.0)


func show_highlights(coords: Array[Vector2i]) -> void:
	clear_highlights()
	for c in coords:
		var marker := MeshInstance3D.new()
		marker.mesh = _highlight_mesh
		marker.position = tile_top_position(c) + Vector3.UP * 0.02
		_highlight_root.add_child(marker)


func clear_highlights() -> void:
	for child in _highlight_root.get_children():
		child.queue_free()


static func _make_hex_mesh(radius: float, height: float, material: Material) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 0
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.material = material
	return mesh


static func _make_material(color: Color, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
