class_name MapView
extends Node3D
## Map view: builds one continuous terrain mesh (heights from TerrainSurface, vertex colours
## from TerrainColors), a translucent water plane and faint hex grid lines from a HexGrid,
## highlights movement range and draws the movement path preview (see show_path()).
## Port of the design's terrain (docs/design/game_screen.scene.js, "terrain mesh").

## The terrain mesh covers the map bounds plus this margin (world units) on every side.
const EXTENT := 6.0
## Terrain mesh vertices per world unit. The design uses 6 and the task suggests 5, but
## TerrainField.height costs ~75 µs per call in GDScript, so 5 took ~3.5 s for the 12×10
## map; 3 keeps the build well under the 1.5 s budget (see TASK-016b notes).
const RESOLUTION := 3.0
## The water plane is this much larger than the terrain mesh.
const WATER_MARGIN := 80.0
const WATER_COLOR := Color("#2c5866", 0.84)
const GRID_LINE_COLOR := Color("#0d120c", 0.2)
## Grid lines float this far above the ground; each hex edge is split into segments so the
## lines follow the slopes.
const GRID_LINE_OFFSET := 0.025
const GRID_LINE_SEGMENTS := 5
## Height of the movement highlight above the tile top.
const HIGHLIGHT_OFFSET := 0.02
## Path markers sit slightly above the movement highlight to avoid z-fighting.
const PATH_MARKER_OFFSET := 0.05
## Attack-target markers sit above the path markers.
const ATTACK_MARKER_OFFSET := 0.07
const PATH_LABEL_HEIGHT := 0.6

@export var hex_size: float = 1.0

var _grid: HexGrid
var _surface: TerrainSurface
## Terrain mesh height grid, kept so the grid lines can sit exactly on the mesh.
var _mesh_origin := Vector2.ZERO
var _mesh_step := Vector2.ONE
var _mesh_cells := Vector2i.ZERO
var _mesh_heights := PackedFloat32Array()
var _tiles_root := Node3D.new()
var _highlight_root := Node3D.new()
var _highlight_mesh: CylinderMesh
var _attack_root := Node3D.new()
var _attack_mesh: CylinderMesh
var _path_root := Node3D.new()
var _path_mesh: CylinderMesh
var _path_label: Label3D


func _ready() -> void:
	add_child(_tiles_root)
	add_child(_highlight_root)
	add_child(_path_root)
	add_child(_attack_root)
	var highlight_material := _make_material(Color(1.0, 0.85, 0.2, 0.45), true)
	_highlight_mesh = _make_hex_mesh(hex_size * 0.8, 0.03, highlight_material)
	var path_material := _make_material(Color(1.0, 0.97, 0.8, 0.75), true)
	_path_mesh = _make_hex_mesh(hex_size * 0.35, 0.03, path_material)
	# Red translucent disc, larger than the yellow movement highlight.
	var attack_material := _make_material(Color(0.9, 0.12, 0.1, 0.6), true)
	_attack_mesh = _make_hex_mesh(hex_size * 0.9, 0.03, attack_material)
	_path_label = _make_path_label()
	add_child(_path_label)


func build(grid: HexGrid) -> void:
	_grid = grid
	_surface = TerrainSurface.new(grid)
	_clear_children(_tiles_root)
	var centers: Array[Vector3] = []
	for c in grid.coords():
		centers.append(Hex.to_world(c, hex_size))
	var rect := CameraMath.map_bounds(centers, hex_size).grow(EXTENT)
	_tiles_root.add_child(_build_terrain(rect))
	_tiles_root.add_child(_build_water(rect))
	_tiles_root.add_child(_build_grid_lines())


## The surface the terrain mesh is built from; use it for picking and placing things.
func surface() -> TerrainSurface:
	return _surface


func tile_top_position(c: Vector2i) -> Vector3:
	var p := Hex.to_world(c, hex_size)
	p.y = _surface.ground_height(p.x, p.z)
	return p


func _build_terrain(rect: Rect2) -> MeshInstance3D:
	var nx := maxi(1, roundi(rect.size.x * RESOLUTION))
	var nz := maxi(1, roundi(rect.size.y * RESOLUTION))
	var step := Vector2(rect.size.x / nx, rect.size.y / nz)
	var row := nx + 1
	var count := row * (nz + 1)
	var vertices := PackedVector3Array()
	vertices.resize(count)
	_mesh_heights.resize(count)
	for j in nz + 1:
		var z := rect.position.y + j * step.y
		for i in row:
			var x := rect.position.x + i * step.x
			var h := _surface.height_at(x, z)
			vertices[j * row + i] = Vector3(x, h, z)
			_mesh_heights[j * row + i] = h
	_mesh_origin = rect.position
	_mesh_step = step
	_mesh_cells = Vector2i(nx, nz)

	# Normals by central differences on the height grid (one-sided at the border).
	var normals := PackedVector3Array()
	normals.resize(count)
	var colors := PackedColorArray()
	colors.resize(count)
	for j in nz + 1:
		var j0 := maxi(j - 1, 0)
		var j1 := mini(j + 1, nz)
		for i in row:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, nx)
			var dx := (vertices[j * row + i1].y - vertices[j * row + i0].y) / ((i1 - i0) * step.x)
			var dz := (vertices[j1 * row + i].y - vertices[j0 * row + i].y) / ((j1 - j0) * step.y)
			var n := Vector3(-dx, 1.0, -dz).normalized()
			normals[j * row + i] = n
			var v := vertices[j * row + i]
			var k := TerrainColors.noise_k(v.x, v.z)
			var jittered := TerrainColors.jitter(v.x, v.z)
			var jc := Hex.from_world(Vector3(jittered.x, 0.0, jittered.y), hex_size)
			var jittered_type := int(_grid.get_terrain(jc)) if _grid.has_tile(jc) else -1
			var on_map := _grid.has_tile(Hex.from_world(v, hex_size))
			colors[j * row + i] = TerrainColors.color_at(v.y, n.y, k, jittered_type, on_map)

	var indices := PackedInt32Array()
	indices.resize(nx * nz * 6)
	var w := 0
	for j in nz:
		for i in nx:
			var a := j * row + i
			var b := a + 1
			var c := a + row
			var d := c + 1
			# Clockwise seen from above (+Y): Godot's front-face winding.
			indices[w] = a
			indices[w + 1] = b
			indices[w + 2] = c
			indices[w + 3] = b
			indices[w + 4] = d
			indices[w + 5] = c
			w += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	material.roughness = 0.95
	material.metallic = 0.0
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = "Terrain"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return instance


func _build_water(rect: Rect2) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = rect.size + Vector2.ONE * WATER_MARGIN
	var material := StandardMaterial3D.new()
	material.albedo_color = WATER_COLOR
	material.roughness = 0.12
	material.metallic = 0.25
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plane.material = material
	var instance := MeshInstance3D.new()
	instance.name = "Water"
	instance.mesh = plane
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var center := rect.get_center()
	instance.position = Vector3(center.x, TerrainSurface.WATER_SURFACE, center.y)
	return instance


## Height of the terrain mesh at (x, z), interpolated on the same triangles the mesh is
## drawn with (cell split along the b–c diagonal), clamped to the water surface.
## Matches the drawn mesh exactly (lines never sink into it) and is much cheaper than
## TerrainSurface.ground_height.
func _mesh_ground_height(x: float, z: float) -> float:
	var fx := clampf((x - _mesh_origin.x) / _mesh_step.x, 0.0, _mesh_cells.x)
	var fz := clampf((z - _mesh_origin.y) / _mesh_step.y, 0.0, _mesh_cells.y)
	var i := mini(floori(fx), _mesh_cells.x - 1)
	var j := mini(floori(fz), _mesh_cells.y - 1)
	var u := fx - i
	var v := fz - j
	var row := _mesh_cells.x + 1
	var ha := _mesh_heights[j * row + i]
	var hb := _mesh_heights[j * row + i + 1]
	var hc := _mesh_heights[(j + 1) * row + i]
	var h: float
	if u + v <= 1.0:
		h = ha + u * (hb - ha) + v * (hc - ha)
	else:
		var hd := _mesh_heights[(j + 1) * row + i + 1]
		h = hd + (1.0 - u) * (hc - hd) + (1.0 - v) * (hb - hd)
	return maxf(h, TerrainSurface.WATER_SURFACE)


## All tile outlines as one line mesh; shared edges are drawn twice, like in the design.
func _build_grid_lines() -> MeshInstance3D:
	var corners: Array[Vector2] = []
	for s in 7:
		var angle := deg_to_rad(60.0 * s - 30.0)
		corners.append(Vector2(cos(angle), sin(angle)) * hex_size)
	var points := PackedVector3Array()
	for c in _grid.coords():
		var center := Hex.to_world(c, hex_size)
		for s in 6:
			for k in GRID_LINE_SEGMENTS:
				for t: float in [float(k) / GRID_LINE_SEGMENTS, float(k + 1) / GRID_LINE_SEGMENTS]:
					var p := corners[s].lerp(corners[s + 1], t)
					var x := center.x + p.x
					var z := center.z + p.y
					points.append(Vector3(x, _mesh_ground_height(x, z) + GRID_LINE_OFFSET, z))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = GRID_LINE_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = "GridLines"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func center() -> Vector3:
	var sum := Vector3.ZERO
	var tiles := _grid.coords()
	for c in tiles:
		sum += Hex.to_world(c, hex_size)
	return sum / maxf(tiles.size(), 1.0)


## Movement highlight (yellow). Replaces only the previous movement highlight.
func show_highlights(coords: Array[Vector2i]) -> void:
	_clear_children(_highlight_root)
	for c in coords:
		var marker := MeshInstance3D.new()
		marker.mesh = _highlight_mesh
		marker.position = tile_top_position(c) + Vector3.UP * HIGHLIGHT_OFFSET
		_highlight_root.add_child(marker)


## Marks tiles holding attackable enemies (red). Replaces only the previous attack markers.
func show_attack_targets(coords: Array[Vector2i]) -> void:
	_clear_children(_attack_root)
	for c in coords:
		var marker := MeshInstance3D.new()
		marker.mesh = _attack_mesh
		marker.position = tile_top_position(c) + Vector3.UP * ATTACK_MARKER_OFFSET
		_attack_root.add_child(marker)


## Clears the movement highlight and the attack-target markers; the path preview has its own
## clear_path().
func clear_highlights() -> void:
	_clear_children(_highlight_root)
	_clear_children(_attack_root)


func _clear_children(root: Node3D) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()


## Draws a small marker on every tile of the path and a label above the last tile.
## The path and the label text come from the caller (no path logic here).
func show_path(coords: Array[Vector2i], label_text: String) -> void:
	clear_path()
	if coords.is_empty():
		return
	for c in coords:
		var marker := MeshInstance3D.new()
		marker.mesh = _path_mesh
		marker.position = tile_top_position(c) + Vector3.UP * PATH_MARKER_OFFSET
		_path_root.add_child(marker)
	_path_label.text = label_text
	_path_label.position = tile_top_position(coords.back()) + Vector3.UP * PATH_LABEL_HEIGHT
	_path_label.show()


func clear_path() -> void:
	for child in _path_root.get_children():
		_path_root.remove_child(child)
		child.queue_free()
	_path_label.hide()


static func _make_path_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.005
	label.font_size = 56
	label.outline_size = 14
	label.modulate = Color(1.0, 0.97, 0.8)
	label.outline_modulate = Color(0.0, 0.0, 0.0)
	label.hide()
	return label


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
