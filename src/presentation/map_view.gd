class_name MapView
extends Node3D
## Map view: builds one continuous terrain mesh (heights from TerrainSurface, per-vertex ground
## layer weights from TerrainSplat drawn by assets/shaders/terrain.gdshader with the
## TerrainTextures arrays), a translucent water plane and faint hex grid lines from a HexGrid,
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
## Scenery ring around the playable terrain mesh (TASK-052): width in world units, vertices at
## half the playable mesh density, the blend from the off-map margin look to the desaturated
## backdrop look over BACKDROP_FADE units from the seam, and that look (value and saturation
## factors, see OFF_MAP_VALUE for the margin).
const BACKDROP_WIDTH := 14.0
const BACKDROP_FADE := 1.5
const BACKDROP_VALUE := 0.85
const BACKDROP_SATURATION := 0.7
## Off-map margin of the playable mesh: value factor (it reads as "not playable").
const OFF_MAP_VALUE := 0.6
## Share of the planned scatter the backdrop keeps (cheaper, and it is far away).
const BACKDROP_SCATTER_DENSITY := 0.5
const BACKDROP_THIN_SEED := 311.0
## Distant forest: real backdrop scatter only within BACKDROP_SCATTER_REACH of the playable mesh;
## beyond it a cheap canopy shell (assets/shaders/canopy.gdshader) over the forest ground, faded
## in over BackdropCanopy.FADE_FROM..FADE_TO.
const BACKDROP_SCATTER_REACH := 4.0
## Border points (offsets in hex sizes) whose tile types the backdrop ground averages.
const BACKDROP_TYPE_SAMPLES: Array[Vector2] = [
	Vector2.ZERO, Vector2(1.5, 0.0), Vector2(-1.5, 0.0), Vector2(0.0, 1.5), Vector2(0.0, -1.5)
]
## The water plane is this much larger than the terrain mesh.
const WATER_MARGIN := 80.0
## Water shader (TASK-056): colours, depths, ripple speeds and normal scale are its defaults.
const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
## Water normal texture parameters.
const WATER_NORMAL_PERIODS: Array[int] = [4, 8, 16, 32]
const WATER_NORMAL_SEED := 303
const WATER_NORMAL_STRENGTH := 5.0
## Terrain mesh UVs: world (x, z) / DETAIL_TILE (the shader samples in world space; the UVs
## only define the tangent frame). DETAIL_SIZE is the procedural water normal map size.
const DETAIL_TILE := 1.45
const DETAIL_SIZE := 256
const GRID_LINE_COLOR := Color("#e9eddc")
## Grid lines float this far above the ground; each hex edge is split into segments so the
## lines follow the slopes.
const GRID_LINE_OFFSET := 0.025
const GRID_LINE_SEGMENTS := 5
## Overlay design values (TASK-017): patch scale, ring radii, alpha and lift above the ground.
## Overlay shapes: Vector2(scale, 0) is a hex patch, Vector2(r0, r1) a hex ring.
## Reach (TASK-049): outline along the outer boundary only, plus a dim over land outside it.
const REACH_LINE_WIDTH := 0.1
const REACH_LINE_ALPHA := 1.0
const REACH_LINE_LIFT := 0.045
const REACH_LINE_SEGMENTS := 3
const DIM_COLOR := Color("#0b0f0a", 0.6)
const DIM_SHAPE := Vector2(1.0, 0.0)
const DIM_LIFT := 0.035
const HOVER_FILL_ALPHA := 0.18
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
const _PLAN_KEYS: Array[String] = [
	"trees", "rocks", "bushes", "edge_shrubs", "young_trees", "ground_cover"
]
## Scatter (TASK-018): view-local seed (never the simulation RNG) and mesh values.
const SCATTER_SEED := 20240518
const BUSH_COLOR_A := Color("#3f5a28")
const BUSH_COLOR_B := Color("#6f7a38")
const ROCK_COLOR_A := Color("#7d776a")
const ROCK_COLOR_B := Color("#9a958a")
## Rocks have no k in the plan: their colour mix is a pseudo-random function of scale.
const ROCK_SHADE_FREQ := 7.31

## Visual layers (VisualInstance3D.layers bits): everything defaults to layer 1; the terrain and
## backdrop meshes are also on layer 2, which ground decals (GroundMarksView) project onto
## exclusively. Camera and light masks are the defaults (all layers), so nothing else changes.
const TERRAIN_VISUAL_LAYER := 2
const TERRAIN_LAYER_MASK := 1 << (TERRAIN_VISUAL_LAYER - 1)
const GRASS_VISUAL_LAYER := 3
const GRASS_LAYER_MASK := 1 << (GRASS_VISUAL_LAYER - 1)

## Generated once per run: the water normal texture.
static var _water_normal: ImageTexture

@export var hex_size: float = 1.0

## Graphics quality switches (GraphicsQuality.features), set by BattleController before use.
var quality: Dictionary = {}
var _grid: HexGrid
var _surface: TerrainSurface
## Terrain mesh height grid, kept so the grid lines can sit exactly on the mesh.
var _mesh_origin := Vector2.ZERO
var _mesh_step := Vector2.ONE
var _mesh_cells := Vector2i.ZERO
var _mesh_heights := PackedFloat32Array()
var _backdrop: BackdropMesh
## The ground ShaderMaterial shared by the terrain and the backdrop (one per build).
var _ground_material: ShaderMaterial
var _nearest_type_cache: Dictionary = {}
var _tiles_root := Node3D.new()
var _reach_line := MeshInstance3D.new()
var _dim := MeshInstance3D.new()
## Reach tiles of the current selection (the unit's own tile excluded) and its colour.
var _reach_set := {}
var _reach_color := Color.WHITE
var _grid_lines: MeshInstance3D
var _grid_material: StandardMaterial3D
var _grid_auto := true
var _camera_distance := CameraRig.DEFAULT_DISTANCE
var _attack_fill := MeshInstance3D.new()
var _attack_ring := MeshInstance3D.new()
var _range_fill := MeshInstance3D.new()
var _range_line := MeshInstance3D.new()
var _hover_fill := MeshInstance3D.new()
var _hover_ring := MeshInstance3D.new()
var _hover_ring_material: ShaderMaterial
var _hover_coord: Variant = null
## Draped overlay vertices (lift 0) per shape and tile: shape -> {Vector2i -> PackedVector3Array}.
## The terrain never changes, so each tile is draped once instead of on every rebuild.
var _shape_cache: Dictionary = {}
var _dots := MultiMeshInstance3D.new()
var _grass := GrassField.new()
var _trees := TreeField.new()
## Planned trees of the last build (map scatter, backdrop scatter), handed to the TreeField.
var _map_trees: Array = []
var _backdrop_trees: Array = []


func _ready() -> void:
	add_child(_tiles_root)
	_grass.name = "Grass"
	add_child(_grass)
	_trees.name = "Trees"
	add_child(_trees)
	for overlay in [
		_reach_line,
		_dim,
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
	_hover_fill.material_override = _overlay_material(Color(1, 1, 1, HOVER_FILL_ALPHA), false)
	_setup_dots()


## The hover ring pulses; geometry is only rebuilt in set_hover().
func _process(_delta: float) -> void:
	if _hover_ring.visible:
		var color := GroundOverlay.color_of(_hover_ring_material)
		color.a = OverlayGeometry.hover_alpha(Time.get_ticks_msec())
		GroundOverlay.set_color(_hover_ring_material, color)


func build(grid: HexGrid) -> void:
	_grid = grid
	_surface = TerrainSurface.new(grid)
	_shape_cache.clear()
	_clear_children(_tiles_root)
	var centers: Array[Vector3] = []
	for c in grid.coords():
		centers.append(Hex.to_world(c, hex_size))
	var rect := CameraMath.map_bounds(centers, hex_size).grow(EXTENT)
	_nearest_type_cache.clear()
	# Packs the ground textures on worker threads while the mesh is built.
	TerrainTextures.request(TerrainGround.texture_size(quality))
	_ground_material = null
	_tiles_root.add_child(_build_terrain(rect))
	_tiles_root.add_child(_build_backdrop(rect))
	_map_trees = []
	_backdrop_trees = []
	if quality.get("foliage", true):
		_build_scatter(ScatterPlanner.plan(grid, _surface, SCATTER_SEED), "")
		if quality.get("backdrop_scatter", true):
			_build_backdrop_scatter(rect)
			_tiles_root.add_child(_build_backdrop_canopy())
	_tiles_root.add_child(_build_water(rect))
	Wind.setup(quality.get("wind", true))
	# After Wind.setup: the foliage shader reads the wind globals.
	_trees.setup(_map_trees, _backdrop_trees, CameraMath.map_bounds(centers, hex_size))
	_grass.setup(
		grid,
		_surface,
		CameraMath.map_bounds(centers, hex_size),
		quality.get("grass_density", 1.0),
		_grass_color
	)
	_grid_lines = _build_grid_lines()
	_tiles_root.add_child(_grid_lines)
	_update_grid()


## Where the camera looks (XZ); grass chunks near it get built.
func set_camera_target(target: Vector2) -> void:
	_grass.set_target(target)


## The grass (TASK-057), for tests and statistics.
func grass() -> GrassField:
	return _grass


## The trees (TASK-060), for tests and statistics.
func trees() -> TreeField:
	return _trees


## The surface the terrain mesh is built from; use it for picking and placing things.
func surface() -> TerrainSurface:
	return _surface


## Height of the drawn terrain mesh at (x, z) – what overlays and markers drape onto.
func mesh_height_at(x: float, z: float) -> float:
	return _mesh_ground_height(x, z)


## Height of the ground the player sees at (x, z): the terrain mesh on the playable rectangle,
## the backdrop beyond it. The camera keeps its clearance above this.
func visible_ground_height(x: float, z: float) -> float:
	var inner := Rect2(_mesh_origin, Vector2(_mesh_cells) * _mesh_step)
	if inner.has_point(Vector2(x, z)):
		return _mesh_ground_height(x, z)
	return maxf(_backdrop.height_at(x, z), TerrainSurface.WATER_SURFACE)


## The tile under a pick ray, or null: rays that miss the map or hit the backdrop scenery pick
## nothing (the backdrop is not part of the TerrainSurface the ray is cast against).
func pick_coord(origin: Vector3, direction: Vector3) -> Variant:
	var hit: Variant = _surface.raycast(origin, direction)
	if hit == null:
		return null
	var coord := Hex.from_world(hit, hex_size)
	if not _grid.has_tile(coord):
		return null
	return coord


func tile_top_position(c: Vector2i) -> Vector3:
	var p := Hex.to_world(c, hex_size)
	p.y = _surface.ground_height(p.x, p.z)
	return p


func _build_terrain(rect: Rect2) -> MeshInstance3D:
	# Even cell counts: the half-resolution backdrop reuses every second border vertex.
	var nx := 2 * maxi(1, roundi(rect.size.x * RESOLUTION / 2.0))
	var nz := 2 * maxi(1, roundi(rect.size.y * RESOLUTION / 2.0))
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
	# Odd border vertices sit on the line between their even neighbours, so the coarser backdrop
	# edge meets the border without cracks (the border is outside the map, nobody notices).
	for i in range(1, nx, 2):
		for j: int in [0, nz]:
			_set_border_height(vertices, j * row + i, 1)
	for j in range(1, nz, 2):
		for i: int in [0, nx]:
			_set_border_height(vertices, j * row + i, row)
	_mesh_origin = rect.position
	_mesh_step = step
	_mesh_cells = Vector2i(nx, nz)

	# Normals by central differences on the height grid (one-sided at the border).
	var normals := PackedVector3Array()
	normals.resize(count)
	var weights := PackedFloat32Array()
	weights.resize(count * TerrainSplat.LAYER_COUNT)
	var tints := PackedVector2Array()
	tints.resize(count)
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
			# The jittered tile type keeps forest edges from following the hex outline.
			var jittered := GroundNoise.jitter(v.x, v.z)
			var jc := Hex.from_world(Vector3(jittered.x, 0.0, jittered.y), hex_size)
			var jittered_type := int(_grid.get_terrain(jc)) if _grid.has_tile(jc) else -1
			var on_map := _grid.has_tile(Hex.from_world(v, hex_size))
			var w := _splat(jittered_type, n.y, v, _splat_noise(v.x, v.z))
			for layer in TerrainSplat.LAYER_COUNT:
				weights[(j * row + i) * TerrainSplat.LAYER_COUNT + layer] = w[layer]
			tints[j * row + i] = Vector2(1.0 if on_map else OFF_MAP_VALUE, 1.0)

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

	# Blend across tile borders: average with the neighbours within one mesh step.
	weights = TerrainSplat.smooth(weights, row, nz + 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = tints
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	TerrainGround.add_surface(mesh, arrays, weights)
	mesh.surface_set_material(0, _terrain_material())
	var instance := MeshInstance3D.new()
	instance.name = "Terrain"
	instance.set_layer_mask_value(TERRAIN_VISUAL_LAYER, true)
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return instance


## The two TerrainSplat noises at world (x, z): fine moisture (x) and the dry/moist macro (y).
static func _splat_noise(x: float, z: float) -> Vector2:
	return Vector2(GroundNoise.moisture_k(x, z), GroundNoise.macro_k(x, z))


## Ground layer weights (TerrainSplat) at vertex `v` with normal Y `normal_y` on terrain type
## `type` (-1 off the map); `noise` from _splat_noise(v.x, v.z).
static func _splat(type: int, normal_y: float, v: Vector3, noise: Vector2) -> PackedFloat32Array:
	return TerrainSplat.weights(
		type, 1.0 - normal_y, v.y, TerrainSurface.WATER_SURFACE, noise.x, noise.y
	)


## The ground material shared by the playable terrain and the backdrop (TerrainGround).
func _terrain_material() -> ShaderMaterial:
	if _ground_material == null:
		_ground_material = TerrainGround.material(quality)
	return _ground_material


func _set_border_height(vertices: PackedVector3Array, index: int, stride: int) -> void:
	var h := (vertices[index - stride].y + vertices[index + stride].y) * 0.5
	vertices[index].y = h
	_mesh_heights[index] = h


## The non-playable scenery ring around `rect` (the playable mesh), see BackdropMesh.
func _build_backdrop(rect: Rect2) -> MeshInstance3D:
	_backdrop = BackdropMesh.new(rect, _mesh_cells, _mesh_heights, BACKDROP_WIDTH, DETAIL_TILE)
	var mesh := _backdrop.build_mesh(_backdrop_vertex, TerrainGround.add_surface)
	mesh.surface_set_material(0, _terrain_material())
	var instance := MeshInstance3D.new()
	instance.name = "Backdrop"
	instance.set_layer_mask_value(TERRAIN_VISUAL_LAYER, true)
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Backdrop vertex: TerrainSplat weights followed by the value and saturation factors. At the
## seam it equals the playable margin (off-map plains, OFF_MAP_VALUE); over BACKDROP_FADE units
## it blends into the nearest border tile's terrain with the muted backdrop look, so the
## playable edge reads without a hard line.
func _backdrop_vertex(
	x: float, z: float, h: float, normal_y: float, distance: float, ca: int, cb: int
) -> PackedFloat32Array:
	var border := Vector2(
		_mesh_origin.x + 2 * ca * _mesh_step.x, _mesh_origin.y + 2 * cb * _mesh_step.y
	)
	var v := Vector3(x, h, z)
	var noise := _splat_noise(x, z)
	var seam := _splat(-1, normal_y, v, noise)
	# The nearest border tiles' terrain, averaged along the border: a single nearest tile
	# would extend every border tile outwards as a stripe.
	var counts := {}
	for offset: Vector2 in BACKDROP_TYPE_SAMPLES:
		var type := _nearest_tile_type(border + offset * hex_size)
		counts[type] = counts.get(type, 0) + 1
	var land := PackedFloat32Array()
	land.resize(TerrainSplat.LAYER_COUNT)
	for type: int in counts:
		var share: float = counts[type] / float(BACKDROP_TYPE_SAMPLES.size())
		var w := _splat(type, normal_y, v, noise)
		for layer in TerrainSplat.LAYER_COUNT:
			land[layer] += w[layer] * share
	var t := TerrainNoise.smooth(0.0, BACKDROP_FADE, distance)
	var result := PackedFloat32Array()
	for layer in TerrainSplat.LAYER_COUNT:
		result.append(lerpf(seam[layer], land[layer], t))
	result.append(lerpf(OFF_MAP_VALUE, BACKDROP_VALUE, t))
	result.append(lerpf(1.0, BACKDROP_SATURATION, t))
	return result


## Terrain type of the map tile nearest to world point `p` (cached per hex it falls in).
func _nearest_tile_type(p: Vector2) -> int:
	var key := Hex.from_world(Vector3(p.x, 0.0, p.y), hex_size)
	if not _nearest_type_cache.has(key):
		var best := -1
		var best_distance := INF
		for c in _grid.coords():
			var w := Hex.to_world(c, hex_size)
			var dist := Vector2(w.x, w.z).distance_squared_to(p)
			if dist < best_distance:
				best_distance = dist
				best = int(_grid.get_terrain(c))
		_nearest_type_cache[key] = best
	return _nearest_type_cache[key]


## Distant forest shell over the backdrop lattice: the forest share of the nearest border tiles
## (the same samples as the backdrop ground) faded in with the distance from the playable mesh,
## drawn by canopy.gdshader as crowns.
func _build_backdrop_canopy() -> MeshInstance3D:
	var lift := VisualScale.tree_scale() * BackdropCanopy.HEIGHT
	var mesh := _backdrop.build_mesh(_canopy_vertex, BackdropCanopy.add_surface.bind(lift))
	mesh.surface_set_material(0, BackdropCanopy.material())
	var instance := MeshInstance3D.new()
	instance.name = "BackdropCanopy"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## BackdropMesh vertex callback of the canopy: forest cover in the first value (the rest is
## unused padding of the shared vertex layout).
func _canopy_vertex(
	_x: float, _z: float, _h: float, _normal_y: float, distance: float, ca: int, cb: int
) -> PackedFloat32Array:
	var border := Vector2(
		_mesh_origin.x + 2 * ca * _mesh_step.x, _mesh_origin.y + 2 * cb * _mesh_step.y
	)
	var forest := 0
	for offset: Vector2 in BACKDROP_TYPE_SAMPLES:
		if _nearest_tile_type(border + offset * hex_size) == Terrain.Type.FOREST:
			forest += 1
	var cover := forest / float(BACKDROP_TYPE_SAMPLES.size())
	cover *= TerrainNoise.smooth(BackdropCanopy.FADE_FROM, BackdropCanopy.FADE_TO, distance)
	var result := PackedFloat32Array()
	result.resize(TerrainSplat.LAYER_COUNT + 2)
	result[0] = cover
	return result


## Trees, bushes and rocks on the backdrop: ScatterPlanner over a virtual tile ring that copies
## the nearest map tile's terrain, at BACKDROP_SCATTER_DENSITY, sitting on the backdrop ground.
func _build_backdrop_scatter(inner: Rect2) -> void:
	var ring := HexGrid.new()
	var outer := _backdrop.outer_rect()
	var lo := Hex.from_world(Vector3(outer.position.x, 0.0, outer.position.y), hex_size)
	var hi := Hex.from_world(Vector3(outer.end.x, 0.0, outer.end.y), hex_size)
	var reach := maxi(absi(hi.x - lo.x), absi(hi.y - lo.y)) + 2
	var center := Hex.from_world(Vector3(outer.get_center().x, 0.0, outer.get_center().y), hex_size)
	for q in range(center.x - reach, center.x + reach + 1):
		for r in range(center.y - reach, center.y + reach + 1):
			var c := Vector2i(q, r)
			var w := Hex.to_world(c, hex_size)
			var p := Vector2(w.x, w.z)
			if _grid.has_tile(c) or inner.has_point(p) or not outer.has_point(p):
				continue
			var border := BackdropHeights.nearest_border_point(inner, p.x, p.y)
			ring.set_terrain(c, _nearest_tile_type(border) as Terrain.Type)
	var surface := BackdropSurface.new(ring, visible_ground_height)
	var plan := ScatterPlanner.plan(ring, surface, SCATTER_SEED)
	# Far away: the ground cover is not worth its triangles.
	plan["ground_cover"] = []
	# Deterministic per-position thinning (no spatial pattern from the plan order).
	for key: String in _PLAN_KEYS:
		var kept: Array = []
		for item: Dictionary in plan[key]:
			var p: Vector3 = item["position"]
			var q := Vector2(p.x, p.z)
			if (
				q.distance_to(q.clamp(inner.position, inner.end)) <= BACKDROP_SCATTER_REACH
				and (
					TerrainNoise.hash(p.x * 7.13, p.z * 5.71, BACKDROP_THIN_SEED)
					< BACKDROP_SCATTER_DENSITY
				)
			):
				kept.append(item)
		plan[key] = kept
	_build_scatter(plan, "Backdrop")


## Bushes and rocks as MultiMeshInstance3Ds – no node per bush or rock; the trees of the plan are
## collected for the TreeField (TASK-060). Instance colours multiply the baked vertex colours of
## the foliage meshes.
func _build_scatter(plan: Dictionary, prefix: String) -> void:
	var tree_list := _backdrop_trees if prefix == "Backdrop" else _map_trees
	tree_list.append_array(plan["trees"])
	for key: String in ["young_trees", "edge_shrubs", "ground_cover"]:
		tree_list.append_array(plan[key])
	# Thickets on open ground (TASK-070) belong to the playable map only.
	if prefix != "Backdrop":
		tree_list.append_array(plan["meadow_scrub"])
	var crown_material := _scatter_material(Color.WHITE, 0.92, true)
	var bushes: Array = plan["bushes"]
	_add_scatter(
		prefix + "Bushes",
		FoliageMeshes.bush(),
		crown_material,
		_tree_transforms(bushes, VisualScale.bush_scale()),
		_tree_colors(bushes, BUSH_COLOR_A, BUSH_COLOR_B)
	)
	var rock_transforms: Array[Transform3D] = []
	var rock_colors := PackedColorArray()
	for r: Dictionary in plan["rocks"]:
		var s: float = r["scale"] * VisualScale.rock_scale()
		var basis := (
			Basis.from_euler(r["rotation"], EULER_ORDER_XYZ)
			* Basis.from_scale(Vector3(s, 0.7 * s, s))
		)
		rock_transforms.append(Transform3D(basis, r["position"]))
		rock_colors.append(ROCK_COLOR_A.lerp(ROCK_COLOR_B, fposmod(s * ROCK_SHADE_FREQ, 1.0)))
	# The rock mesh has no vertex colours (white); the instance colour tints it.
	var rock_material := _scatter_material(Color.WHITE, 0.95, true)
	_add_scatter(
		prefix + "Rocks", FoliageMeshes.rock(), rock_material, rock_transforms, rock_colors
	)


## Bush transforms (trees: TreeField.tree_transform): the meshes are built with their base at
## y = 0 and sit on the planted position. `size_multiplier` (VisualScale) scales the instance
## about its base, so the planned positions stay the same.
static func _tree_transforms(trees: Array, size_multiplier: float = 1.0) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for tree: Dictionary in trees:
		var s: float = tree["scale"] * size_multiplier
		var h: float = tree["height_scale"] * size_multiplier
		var basis := Basis(Vector3.UP, tree["yaw"]) * Basis.from_scale(Vector3(s, h, s))
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
	# One node for the whole map, so every shadow cascade drew all of it (~11M of ~15M triangles).
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tiles_root.add_child(instance)


## Linear ground colour under a grass clump: the mean albedo of each ground layer
## (TerrainTextures "average_colors", tint included) weighted by the TerrainSplat weights the
## terrain shader blends.
func _grass_color(p: Vector3) -> Color:
	var averages: Array[Color] = (
		TerrainTextures.arrays(TerrainGround.texture_size(quality))["average_colors"]
	)
	var slope := GrassPlanner.slope(_surface, p.x, p.z)
	var normal_y := 1.0 / sqrt(1.0 + slope * slope)
	var terrain := _grid.get_terrain(Hex.from_world(p, hex_size))
	var weights := _splat(terrain, normal_y, p, _splat_noise(p.x, p.z))
	var color := Color(0, 0, 0)
	for layer in TerrainSplat.LAYER_COUNT:
		color += averages[layer] * weights[layer]
	return Color(color.r, color.g, color.b)


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
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter(&"normal_map", _water_normal_texture())
	var look_water := LookPreset.water_params()
	for key: String in look_water:
		material.set_shader_parameter(StringName(key), look_water[key])
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
		if _grid.get_terrain(c) == Terrain.Type.WATER:
			continue  # never over water; shared shore edges are drawn by the land side
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
	_grid_material = material
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


## Reach outline (outer boundary of reach + the unit tile) in the faction colour `color`, and a
## dim over every land tile outside it.
func show_reach(coords: Array[Vector2i], color: Color, unit_tile: Vector2i) -> void:
	_reach_set.clear()
	for c in coords:
		_reach_set[c] = true
	_reach_color = color
	var area: Array[Vector2i] = coords.duplicate()
	area.append(unit_tile)
	var edges := OverlayGeometry.boundary_edges(area, hex_size)
	var ribbons := OverlayGeometry.edge_ribbons(edges, REACH_LINE_WIDTH, REACH_LINE_SEGMENTS)
	_reach_line.mesh = _triangles_mesh(_drape(ribbons, 0.0))
	_reach_line.position.y = REACH_LINE_LIFT
	_reach_line.material_override = _overlay_material(Color(color, REACH_LINE_ALPHA))
	_reach_line.visible = true
	var outside: Array[Vector2i] = []
	for c in _grid.coords():
		if _grid.get_terrain(c) != Terrain.Type.WATER and not _reach_set.has(c) and c != unit_tile:
			outside.append(c)
	_set_overlay(_dim, outside, DIM_SHAPE, DIM_COLOR, DIM_LIFT)
	_update_grid()
	_refresh_hover_fill()


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
	for instance in [_reach_line, _dim, _attack_fill, _attack_ring]:
		(instance as MeshInstance3D).visible = false
		(instance as MeshInstance3D).mesh = null
	_reach_set.clear()
	_update_grid()
	_refresh_hover_fill()


## Hover ring + fill on `coord` (Vector2i), or hidden for null. Geometry is rebuilt only
## when the tile changes.
func set_hover(coord: Variant) -> void:
	if typeof(coord) == typeof(_hover_coord) and coord == _hover_coord:
		return
	_hover_coord = coord
	var show := coord != null
	_hover_ring.visible = show
	if not show:
		_hover_fill.visible = false
		return
	_hover_ring.mesh = _triangles_mesh(_tile_shape(coord, HOVER_RING_SHAPE))
	_hover_ring.position.y = HOVER_RING_LIFT
	_hover_fill.mesh = _triangles_mesh(_tile_shape(coord, HOVER_FILL_SHAPE))
	_hover_fill.position.y = HOVER_FILL_LIFT
	_refresh_hover_fill()


## The hover wash (faction colour) shows only on a tile inside the current reach.
func _refresh_hover_fill() -> void:
	var inside := _hover_coord != null and _reach_set.has(_hover_coord)
	_hover_fill.visible = inside
	if inside:
		GroundOverlay.set_color(
			_hover_fill.material_override as ShaderMaterial, Color(_reach_color, HOVER_FILL_ALPHA)
		)


## Camera distance drives the grid fade (called by the battle controller on change).
func set_camera_distance(distance: float) -> void:
	if is_equal_approx(distance, _camera_distance):
		return
	_camera_distance = distance
	_update_grid()


## Grid mode auto (fades with zoom) <-> off. A view setting only.
func cycle_grid_mode() -> void:
	_grid_auto = not _grid_auto
	_update_grid()


func _update_grid() -> void:
	if _grid_lines == null:
		return
	_grid_lines.visible = _grid_auto
	_grid_material.albedo_color.a = OverlayGeometry.grid_alpha(
		_camera_distance, _reach_line.visible
	)


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
	instance.material_override = _overlay_material(color, shape.y != 0.0)  # patches: fills


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


static func _overlay_material(color: Color, pulled := true) -> ShaderMaterial:
	return GroundOverlay.material(color, pulled)


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
