class_name MapView
extends Node3D
## Map view: builds one continuous terrain mesh (heights from TerrainSurface, vertex colours
## from TerrainColors), a translucent water plane and faint hex grid lines from a HexGrid,
## draws the reach wash, attack-target rings, hover ring and path dots (TASK-017).
## Port of the design's terrain (docs/design/game_screen.scene.js, "terrain mesh").

## The terrain mesh covers the map bounds plus this margin (world units) on every side.
const EXTENT := 6.0
## Terrain mesh vertices per world unit. The design uses 6 and the task suggests 5, but
## TerrainField.height costs ~75 µs per call in GDScript, so 5 took ~3.5 s for the 12×10
## map. TASK-027 measured the default map: 3 -> ~0.95 s, 4 -> ~1.6 s, 5 -> ~2.5 s, 6 -> ~3.7 s
## (excluding ~0.3 s once for the detail textures); 4 is the compromise, the normal map
## supplies the fine detail.
const RESOLUTION := 4.0
## The water plane is this much larger than the terrain mesh.
const WATER_MARGIN := 80.0
const WATER_COLOR := Color("#264f5c", 0.84)
## Water surface ripples: UV repeats over the plane, normal strength and texture parameters.
const WATER_UV_REPEAT := 36.0
const WATER_NORMAL_SCALE := 0.3
const WATER_NORMAL_PERIODS: Array[int] = [4, 8, 16, 32]
const WATER_NORMAL_SEED := 303
const WATER_NORMAL_STRENGTH := 5.0
## Ground detail texture (shared by all land): world units per texture repeat (the design
## repeats it ~44x over its terrain width), size, noise periods, seed, normal strength/scale.
const DETAIL_TILE := 1.45
const DETAIL_SIZE := 256
const DETAIL_PERIODS: Array[int] = [8, 16, 32, 64]
const DETAIL_SEED := 201
const DETAIL_NORMAL_STRENGTH := 7.0
const DETAIL_NORMAL_SCALE := 0.9
const GRID_LINE_COLOR := Color("#0d120c", 0.2)
## Grid lines float this far above the ground; each hex edge is split into segments so the
## lines follow the slopes.
const GRID_LINE_OFFSET := 0.025
const GRID_LINE_SEGMENTS := 5
## Overlay design values (TASK-017): patch scale, ring radii, alpha and lift above the ground.
## Overlay shapes: Vector2(scale, 0) is a hex patch, Vector2(r0, r1) a hex ring.
const REACH_FILL_SHAPE := Vector2(0.9, 0.0)
const REACH_FILL_ALPHA := 0.2
const REACH_FILL_LIFT := 0.03
const REACH_RING_SHAPE := Vector2(0.86, 0.92)
const REACH_RING_ALPHA := 0.55
const REACH_RING_LIFT := 0.035
const ATTACK_COLOR := Color("#e07c5e")
const ATTACK_FILL_SHAPE := Vector2(0.9, 0.0)
const ATTACK_FILL_ALPHA := 0.25
const ATTACK_FILL_LIFT := 0.035
const ATTACK_RING_SHAPE := Vector2(0.86, 0.98)
const ATTACK_RING_ALPHA := 0.9
const ATTACK_RING_LIFT := 0.04
const HOVER_FILL_SHAPE := Vector2(0.92, 0.0)
const HOVER_FILL_LIFT := 0.035
const HOVER_RING_SHAPE := Vector2(0.9, 0.98)
const HOVER_RING_LIFT := 0.04
## Attack range (TASK-011): boundary outline + a very faint tint, in a warm threat colour that
## differs from the faction reach wash and the red-orange attack-target markers.
const RANGE_COLOR := Color("#f2b134")
const RANGE_FILL_SHAPE := Vector2(0.98, 0.0)
const RANGE_FILL_ALPHA := 0.07
const RANGE_FILL_LIFT := 0.025
const RANGE_LINE_WIDTH := 0.07
const RANGE_LINE_ALPHA := 0.95
const RANGE_LINE_LIFT := 0.045
const RANGE_LINE_SEGMENTS := 3
const PATCH_SUBDIVISIONS := 4
const RING_SEGMENTS := 5
const DOT_RADIUS := 0.05
const DOT_LIFT := 0.1
const LAST_DOT_SCALE := 1.8
## Scatter (TASK-018): view-local seed (never the simulation RNG) and mesh values.
const SCATTER_SEED := 20240518
const CONIFER_COLOR_A := Color("#2c4626")
const CONIFER_COLOR_B := Color("#40603a")
const DECIDUOUS_COLOR_A := Color("#41602c")
const DECIDUOUS_COLOR_B := Color("#72853a")
const BUSH_COLOR_A := Color("#3f5a28")
const BUSH_COLOR_B := Color("#6f7a38")
const TRUNK_COLOR := Color("#4a3b2a")
const ROCK_COLOR_A := Color("#7d776a")
const ROCK_COLOR_B := Color("#9a958a")
## Rocks have no k in the plan: their colour mix is a pseudo-random function of scale.
const ROCK_SHADE_FREQ := 7.31

## Generated once per run: ground albedo and normal textures and the water normal texture.
static var _ground_albedo: ImageTexture
static var _ground_normal: ImageTexture
static var _water_normal: ImageTexture

@export var hex_size: float = 1.0

var _grid: HexGrid
var _surface: TerrainSurface
## Terrain mesh height grid, kept so the grid lines can sit exactly on the mesh.
var _mesh_origin := Vector2.ZERO
var _mesh_step := Vector2.ONE
var _mesh_cells := Vector2i.ZERO
var _mesh_heights := PackedFloat32Array()
var _tiles_root := Node3D.new()
var _reach_fill := MeshInstance3D.new()
var _reach_ring := MeshInstance3D.new()
var _attack_fill := MeshInstance3D.new()
var _attack_ring := MeshInstance3D.new()
var _range_fill := MeshInstance3D.new()
var _range_line := MeshInstance3D.new()
var _hover_fill := MeshInstance3D.new()
var _hover_ring := MeshInstance3D.new()
var _hover_ring_material: StandardMaterial3D
var _hover_coord: Variant = null
## Draped overlay vertices (lift 0) per shape and tile: shape -> {Vector2i -> PackedVector3Array}.
## The terrain never changes, so each tile is draped once instead of on every rebuild.
var _shape_cache: Dictionary = {}
var _dots := MultiMeshInstance3D.new()


func _ready() -> void:
	add_child(_tiles_root)
	for overlay in [
		_reach_fill,
		_reach_ring,
		_attack_fill,
		_attack_ring,
		_range_fill,
		_range_line,
		_hover_fill,
		_hover_ring
	]:
		var instance: MeshInstance3D = overlay
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visible = false
		add_child(instance)
	_hover_ring_material = _overlay_material(Color(1, 1, 1, 0.6))
	_hover_ring.material_override = _hover_ring_material
	_hover_fill.material_override = _overlay_material(Color(1, 1, 1, 0.1))
	_setup_dots()


## The hover ring pulses; geometry is only rebuilt in set_hover().
func _process(_delta: float) -> void:
	if _hover_ring.visible:
		_hover_ring_material.albedo_color.a = OverlayGeometry.hover_alpha(Time.get_ticks_msec())


func build(grid: HexGrid) -> void:
	_grid = grid
	_surface = TerrainSurface.new(grid)
	_shape_cache.clear()
	_clear_children(_tiles_root)
	var centers: Array[Vector3] = []
	for c in grid.coords():
		centers.append(Hex.to_world(c, hex_size))
	var rect := CameraMath.map_bounds(centers, hex_size).grow(EXTENT)
	_tiles_root.add_child(_build_terrain(rect))
	_build_scatter(ScatterPlanner.plan(grid, _surface, SCATTER_SEED))
	_tiles_root.add_child(_build_water(rect))
	_tiles_root.add_child(_build_grid_lines())


## The surface the terrain mesh is built from; use it for picking and placing things.
func surface() -> TerrainSurface:
	return _surface


## Height of the drawn terrain mesh at (x, z) – what overlays and markers drape onto.
func mesh_height_at(x: float, z: float) -> float:
	return _mesh_ground_height(x, z)


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
	var uvs := PackedVector2Array()
	uvs.resize(count)
	# Godot packs tangents as (x, y, z, w) with binormal = cross(normal, tangent) * w.
	var tangents := PackedFloat32Array()
	tangents.resize(count * 4)
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
			# U runs along +x, so the tangent is the slope direction (1, dh/dx, 0), made
			# perpendicular to the normal. With w = +1 the binormal is -z, i.e. up the
			# normal map image (towards v = 0), the OpenGL convention DetailTexture writes.
			var t := Vector3(1.0, dx, 0.0)
			t = (t - n * n.dot(t)).normalized()
			var ti := (j * row + i) * 4
			tangents[ti] = t.x
			tangents[ti + 1] = t.y
			tangents[ti + 2] = t.z
			tangents[ti + 3] = 1.0
			uvs[j * row + i] = (
				Vector2(vertices[j * row + i].x, vertices[j * row + i].z) / DETAIL_TILE
			)
			var v := vertices[j * row + i]
			var k := TerrainColors.noise_k(v.x, v.z)
			var jittered := TerrainColors.jitter(v.x, v.z)
			var jc := Hex.from_world(Vector3(jittered.x, 0.0, jittered.y), hex_size)
			var jittered_type := int(_grid.get_terrain(jc)) if _grid.has_tile(jc) else -1
			var on_map := _grid.has_tile(Hex.from_world(v, hex_size))
			var mac := TerrainColors.macro_k(v.x, v.z)
			colors[j * row + i] = TerrainColors.color_at(v.y, n.y, k, jittered_type, on_map, mac)

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
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	material.roughness = 0.95
	material.metallic = 0.0
	_ensure_ground_textures()
	material.albedo_texture = _ground_albedo
	material.normal_enabled = true
	material.normal_texture = _ground_normal
	material.normal_scale = DETAIL_NORMAL_SCALE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = "Terrain"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return instance


## Trees, bushes and rocks as MultiMeshInstance3Ds (two variants per crown type) – no node per
## tree. Instance colours multiply the baked vertex colours of the foliage meshes.
func _build_scatter(plan: Dictionary) -> void:
	var trees: Array = plan["trees"]
	var crown_material := _scatter_material(Color.WHITE, 0.92, true)
	for variant in 2:
		var cones: Array = []
		var blobs: Array = []
		for tree: Dictionary in trees:
			if (tree["k"] < 0.5) != (variant == 0):
				continue
			(cones if tree["conifer"] else blobs).append(tree)
		_add_scatter(
			"ConiferCrowns%d" % variant,
			FoliageMeshes.conifer(variant),
			crown_material,
			_tree_transforms(cones),
			_tree_colors(cones, CONIFER_COLOR_A, CONIFER_COLOR_B)
		)
		_add_scatter(
			"DeciduousCrowns%d" % variant,
			FoliageMeshes.deciduous(variant),
			crown_material,
			_tree_transforms(blobs),
			_tree_colors(blobs, DECIDUOUS_COLOR_A, DECIDUOUS_COLOR_B)
		)
	var bushes: Array = plan["bushes"]
	_add_scatter(
		"Bushes",
		FoliageMeshes.bush(),
		crown_material,
		_tree_transforms(bushes),
		_tree_colors(bushes, BUSH_COLOR_A, BUSH_COLOR_B)
	)
	_add_scatter(
		"Trunks",
		FoliageMeshes.trunk(),
		_scatter_material(TRUNK_COLOR, 1.0, false),
		_tree_transforms(trees),
		PackedColorArray()
	)
	var rock_transforms: Array[Transform3D] = []
	var rock_colors := PackedColorArray()
	for r: Dictionary in plan["rocks"]:
		var s: float = r["scale"]
		var basis := (
			Basis.from_euler(r["rotation"], EULER_ORDER_XYZ)
			* Basis.from_scale(Vector3(s, 0.7 * s, s))
		)
		rock_transforms.append(Transform3D(basis, r["position"]))
		rock_colors.append(ROCK_COLOR_A.lerp(ROCK_COLOR_B, fposmod(s * ROCK_SHADE_FREQ, 1.0)))
	# The rock mesh has no vertex colours (white); the instance colour tints it.
	var rock_material := _scatter_material(Color.WHITE, 0.95, true)
	_add_scatter("Rocks", FoliageMeshes.rock(), rock_material, rock_transforms, rock_colors)


## Tree and bush transforms: the meshes are built with their base at y = 0 and sit on the planted
## position.
static func _tree_transforms(trees: Array) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for tree: Dictionary in trees:
		var s: float = tree["scale"]
		var basis := (
			Basis(Vector3.UP, tree["yaw"]) * Basis.from_scale(Vector3(s, tree["height_scale"], s))
		)
		result.append(Transform3D(basis, tree["position"]))
	return result


static func _tree_colors(trees: Array, a: Color, b: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	for tree: Dictionary in trees:
		colors.append(a.lerp(b, tree["k"]))
	return colors


static func _scatter_material(
	color: Color, roughness: float, use_vertex_color: bool
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	material.vertex_color_use_as_albedo = use_vertex_color
	return material


func _add_scatter(
	node_name: String,
	mesh: Mesh,
	material: Material,
	transforms: Array[Transform3D],
	colors: PackedColorArray
) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = not colors.is_empty()
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		if multi.use_colors:
			multi.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_tiles_root.add_child(instance)


## Generates the ground albedo and normal textures on first use.
static func _ensure_ground_textures() -> void:
	if _ground_albedo != null:
		return
	var heights := DetailTexture.height_map(DETAIL_SIZE, DETAIL_PERIODS, DETAIL_SEED)
	_ground_albedo = ImageTexture.create_from_image(
		DetailTexture.albedo_image(heights, DETAIL_SIZE)
	)
	_ground_normal = ImageTexture.create_from_image(
		DetailTexture.normal_image(heights, DETAIL_SIZE, DETAIL_NORMAL_STRENGTH)
	)


static func _water_normal_texture() -> ImageTexture:
	if _water_normal == null:
		var heights := DetailTexture.height_map(
			DETAIL_SIZE, WATER_NORMAL_PERIODS, WATER_NORMAL_SEED
		)
		_water_normal = ImageTexture.create_from_image(
			DetailTexture.normal_image(heights, DETAIL_SIZE, WATER_NORMAL_STRENGTH)
		)
	return _water_normal


func _build_water(rect: Rect2) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = rect.size + Vector2.ONE * WATER_MARGIN
	var material := StandardMaterial3D.new()
	material.albedo_color = WATER_COLOR
	material.roughness = 0.07
	material.metallic = 0.1
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.normal_enabled = true
	material.normal_texture = _water_normal_texture()
	material.normal_scale = WATER_NORMAL_SCALE
	material.uv1_scale = Vector3(WATER_UV_REPEAT, WATER_UV_REPEAT, 1.0)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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


func _clear_children(root: Node3D) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()


## Reach wash and outlines in the faction colour `color` (one mesh each, rebuilt here).
func show_reach(coords: Array[Vector2i], color: Color) -> void:
	_set_overlay(
		_reach_fill, coords, REACH_FILL_SHAPE, Color(color, REACH_FILL_ALPHA), REACH_FILL_LIFT
	)
	_set_overlay(
		_reach_ring, coords, REACH_RING_SHAPE, Color(color, REACH_RING_ALPHA), REACH_RING_LIFT
	)


## Marks tiles holding attackable enemies (ring + wash). Replaces only the previous markers.
func show_attack_targets(coords: Array[Vector2i]) -> void:
	_set_overlay(
		_attack_fill,
		coords,
		ATTACK_FILL_SHAPE,
		Color(ATTACK_COLOR, ATTACK_FILL_ALPHA),
		ATTACK_FILL_LIFT
	)
	_set_overlay(
		_attack_ring,
		coords,
		ATTACK_RING_SHAPE,
		Color(ATTACK_COLOR, ATTACK_RING_ALPHA),
		ATTACK_RING_LIFT
	)


## Marks the tiles a ranged unit can shoot at: a faint tint plus an outline along the outer
## boundary of the area (edges not shared with another range tile).
func show_attack_range(coords: Array[Vector2i]) -> void:
	_set_overlay(
		_range_fill, coords, RANGE_FILL_SHAPE, Color(RANGE_COLOR, RANGE_FILL_ALPHA), RANGE_FILL_LIFT
	)
	_range_line.visible = not coords.is_empty()
	if coords.is_empty():
		_range_line.mesh = null
		return
	var edges := OverlayGeometry.boundary_edges(coords, hex_size)
	var ribbons := OverlayGeometry.edge_ribbons(edges, RANGE_LINE_WIDTH, RANGE_LINE_SEGMENTS)
	_range_line.mesh = _triangles_mesh(_drape(ribbons, 0.0))
	_range_line.position.y = RANGE_LINE_LIFT
	_range_line.material_override = _overlay_material(Color(RANGE_COLOR, RANGE_LINE_ALPHA))


func clear_attack_range() -> void:
	show_attack_range([] as Array[Vector2i])


## Clears the reach wash, the attack-target markers and the attack range; the path preview has
## its own clear_path().
func clear_highlights() -> void:
	clear_attack_range()
	for instance in [_reach_fill, _reach_ring, _attack_fill, _attack_ring]:
		(instance as MeshInstance3D).visible = false
		(instance as MeshInstance3D).mesh = null


## Hover ring + fill on `coord` (Vector2i), or hidden for null. Geometry is rebuilt only
## when the tile changes.
func set_hover(coord: Variant) -> void:
	if typeof(coord) == typeof(_hover_coord) and coord == _hover_coord:
		return
	_hover_coord = coord
	var show := coord != null
	_hover_ring.visible = show
	_hover_fill.visible = show
	if not show:
		return
	_hover_ring.mesh = _triangles_mesh(_tile_shape(coord, HOVER_RING_SHAPE))
	_hover_ring.position.y = HOVER_RING_LIFT
	_hover_fill.mesh = _triangles_mesh(_tile_shape(coord, HOVER_FILL_SHAPE))
	_hover_fill.position.y = HOVER_FILL_LIFT


## One merged mesh of `shape` over all `coords`, lifted by moving the instance.
func _set_overlay(
	instance: MeshInstance3D, coords: Array[Vector2i], shape: Vector2, color: Color, lift: float
) -> void:
	instance.visible = not coords.is_empty()
	if coords.is_empty():
		instance.mesh = null
		return
	var vertices := PackedVector3Array()
	for c in coords:
		vertices.append_array(_tile_shape(c, shape))
	instance.mesh = _triangles_mesh(vertices)
	instance.position.y = lift
	instance.material_override = _overlay_material(color)


## Draped (lift 0) triangle list of `shape` on tile `c`, cached (see _shape_cache).
func _tile_shape(c: Vector2i, shape: Vector2) -> PackedVector3Array:
	var per_tile: Dictionary = _shape_cache.get_or_add(shape, {})
	if not per_tile.has(c):
		var center := Hex.to_world(c, hex_size)
		var c2 := Vector2(center.x, center.z)
		var flat := (
			OverlayGeometry.hex_patch(c2, shape.x, PATCH_SUBDIVISIONS)
			if shape.y == 0.0
			else OverlayGeometry.hex_ring(c2, shape.x, shape.y, RING_SEGMENTS)
		)
		per_tile[c] = _drape(flat, 0.0)
	return per_tile[c]


## Overlay points follow the drawn mesh (_mesh_ground_height), not TerrainSurface.ground_height:
## the mesh is a coarse linear interpolation of the surface, so hills can poke through
## overlays that follow the exact surface, and the mesh query is ~100x cheaper in GDScript
## (thousands of vertices per rebuild).
func _drape(points: PackedVector2Array, lift: float) -> PackedVector3Array:
	return OverlayGeometry.drape_with(points, _mesh_ground_height, lift)


static func _triangles_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _setup_dots() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = DOT_RADIUS
	sphere.height = DOT_RADIUS * 2.0
	sphere.radial_segments = 10
	sphere.rings = 8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = sphere
	multi.instance_count = OverlayGeometry.MAX_DOTS_POINTS
	multi.visible_instance_count = 0
	_dots.multimesh = multi
	_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dots)


## Draws white dots along a smooth curve from `from` (the unit's tile) through `path`
## (excludes `from`, as HexGrid.path_to returns it).
## The path comes from the caller (no path logic here).
func show_path(from: Vector2i, path: Array[Vector2i]) -> void:
	clear_path()
	if path.is_empty():
		return
	var centers := PackedVector2Array()
	for c in [from] + path:
		var p := Hex.to_world(c, hex_size)
		centers.append(Vector2(p.x, p.z))
	var tiles := centers.size()
	var count := mini(OverlayGeometry.MAX_DOTS_POINTS, (tiles - 1) * 5)
	var points := OverlayGeometry.curve_points(centers, count)
	var multi := _dots.multimesh
	var dots := OverlayGeometry.path_dot_count(tiles)
	var last := Vector3.ZERO
	for i in dots:
		var p := points[i + OverlayGeometry.SKIPPED_POINTS]
		last = Vector3(p.x, _mesh_ground_height(p.x, p.y) + DOT_LIFT, p.y)
		var s := LAST_DOT_SCALE if i == dots - 1 else 1.0
		multi.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), last))
	multi.visible_instance_count = dots


func clear_path() -> void:
	_dots.multimesh.visible_instance_count = 0
