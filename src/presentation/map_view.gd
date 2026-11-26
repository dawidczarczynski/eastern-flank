# gdlint: disable=max-public-methods
class_name MapView
extends Node3D
## Map view: builds the terrain (heights from TerrainSurface, per-vertex ground layer weights from
## TerrainSplat drawn by assets/shaders/terrain.gdshader with the TerrainTextures arrays), a
## translucent water plane and faint hex grid lines from a HexGrid, draws the reach wash,
## attack-target rings, hover ring and path dots (TASK-017).
## Port of the design's terrain (docs/design/v1/game_screen.scene.js, "terrain mesh").
## The world is chunked (TASK-072b, ADR 0024): terrain, bushes and rocks, trees, grass, grid lines
## and ground marks are ChunkLayers of one ChunkManager and exist only within metre-based rings
## around the camera target (ChunkRings); the coarse terrain covers the rest of the map. Call
## set_camera_target() when the camera moves; _process() builds within the frame budget, and
## finish_chunks() builds everything at once (loading screen, tests, screenshots).
## Real scale (TASK-135): RealScaleVegetation (dense forest, near grass, camera-centred chunks).

## The terrain mesh covers the map bounds plus this margin (world units) on every side.
const EXTENT := 6.0
## Terrain mesh vertices per world unit. The design uses 6 and the task suggests 5, but
## TerrainField.height costs ~75 µs per call in GDScript, so 5 took ~3.5 s for the 12×10
## map. TASK-027 measured the default map: 3 -> ~0.95 s, 4 -> ~1.6 s, 5 -> ~2.5 s, 6 -> ~3.7 s
## (excluding ~0.3 s once for the detail textures); 4 is the compromise, the normal map
## supplies the fine detail (TerrainLattice.RESOLUTION).
const RESOLUTION := 4.0
## Farmland parcels (TASK-108f) reach this far beyond the playable mesh into the backdrop ring.
const PARCEL_MARGIN := 2.0
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

@export var hex_size: float = 1.0

## Graphics quality switches (GraphicsQuality.features), set by BattleController before use.
var quality: Dictionary = {}
## The land cover of the map (TASK-108g, LandCover.for_map), set before build(); null or without a
## raster: the look follows the hex types. `_look` is its CoverLook for this build.
var land_cover: LandCover
## The satellite colour layer of the map (TASK-192b, BattleCover.colour_for_battle), set before
## build(); null (no layer, or not the `true` VisualScale preset): the textured look only.
var satellite: SatelliteColour
## The real field parcels of the map (TASK-215b, BattleCover.parcels_for_battle), set before
## build(); null (no polygons, or not the `true` VisualScale preset): the procedural strips only.
var real_parcels: RealParcels
## The OSM tree features of the map (TASK-199b, BattleCover.tree_features_for_battle), set before
## build(); null (none, or not the `true` VisualScale preset).
var tree_features: TreeFeatureSet
## Chunk plans and the coarse terrain run on the worker threads; off: on the caller's thread,
## same result.
var threads := true
var _look: CoverLook
var _grid: HexGrid
var _surface: TerrainSurface
## The terrain lattice (its origin, cell size and cell counts are kept as _mesh_* for the
## overlays and the backdrop seam).
var _lattice: TerrainLattice
var _mesh_origin := Vector2.ZERO
var _mesh_step := Vector2.ONE
var _mesh_cells := Vector2i.ZERO
var _terrain: TerrainChunks
## The near terrain LOD (TASK-134), null on LOW quality.
var _near: TerrainNear
## Whether the near terrain layer is on (camera close enough, TerrainNear.wanted).
var _near_on := false
var _chunks := ChunkManager.new()
## Real-scale forest and near grass, and the camera-centred chunk manager (TASK-135).
var _vegetation := RealScaleVegetation.new()
var _foliage: FoliageChunks
var _backdrop: BackdropMesh
## The ground ShaderMaterial shared by the terrain and the backdrop (one per build).
var _ground_material: ShaderMaterial
## The baked farmland parcels of this build (FieldParcels), or null on a map without fields.
var _parcels: ParcelMap
## The map terrain the backdrop copies (one per build, after the terrain mesh).
var _backdrop_types: BackdropTypes
## Mean linear albedo per ground layer (TerrainTextures "average_colors"), read by the grass
## planning threads; filled on the main thread before they start.
var _layer_averages: Array[Color] = []
var _tiles_root := Node3D.new()
var _reach_line := MeshInstance3D.new()
var _dim := MeshInstance3D.new()
## Reach tiles of the current selection (the unit's own tile excluded) and its colour.
var _reach_set := {}
var _reach_color := Color.WHITE
## Parent of the grid line chunks ("GridLines_<x>_<z>"); Vector2i chunk -> MeshInstance3D.
var _grid_lines: Node3D
var _grid_chunks: Dictionary = {}
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


func _ready() -> void:
	add_child(_tiles_root)
	_grass.name = "Grass"
	add_child(_grass)
	_trees.name = "Trees"
	add_child(_trees)
	add_child(_vegetation.forest)
	add_child(_vegetation.grass_near)
	add_child(_vegetation.shrubs)
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


## Worker threads may still be planning chunks of this view: let them finish before it goes.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_chunks.wait()
		_vegetation.chunks.wait()


## The hover ring pulses; geometry is only rebuilt in set_hover(). Chunks around the camera
## target are built within the frame budget (ChunkManager.process).
func _process(_delta: float) -> void:
	_chunks.process()
	_follow_viewport_camera()
	_vegetation.process()
	if _hover_ring.visible:
		var color := GroundOverlay.color_of(_hover_ring_material)
		color.a = OverlayGeometry.hover_alpha(Time.get_ticks_msec())
		GroundOverlay.set_color(_hover_ring_material, color)


func build(grid: HexGrid) -> void:
	# Before any material: the world shaders read the cloud globals (a texture one must exist).
	CloudShadows.setup(quality.get("clouds", true))
	_chunks.reset()
	_chunks = ChunkManager.new(ChunkRings.load_default(), quality.get("small_chunk_rings", false))
	_chunks.threads = threads
	_vegetation.reset(_chunks, quality.get("small_chunk_rings", false), threads, quality)
	_grid = grid
	_look = CoverLook.make(land_cover)
	_surface = TerrainSurface.new(grid)
	_shape_cache.clear()
	_clear_children(_tiles_root)
	_grid_chunks.clear()
	var centers: Array[Vector3] = []
	for c in grid.coords():
		centers.append(Hex.to_world(c, hex_size))
	var playable := CameraMath.map_bounds(centers, hex_size)
	var rect := playable.grow(EXTENT)
	# Packs the ground textures on worker threads while the mesh is built.
	TerrainTextures.request(TerrainGround.texture_size(quality))
	_ground_material = null
	# Farmland parcels (TASK-108f) over the mesh and the near backdrop; null without fields. Baked
	# on a worker thread while the terrain and the backdrop are built (it reads the grid only).
	_parcels = null
	var bake_rect := rect.grow(PARCEL_MARGIN)
	var baked: Array = [null]
	var real := real_parcels
	var bake := func() -> void:
		var mpp := FieldParcels.DEFAULT_METRES_PER_PIXEL
		baked[0] = FieldParcels.bake(grid, hex_size, bake_rect, mpp, {}, _look, real)
	var bake_task := -1
	if threads:
		bake_task = WorkerThreadPool.add_task(bake, true, "Farmland parcels")
	else:
		bake.call()
	# The planners read the surface and the ribbon index from the worker threads: fill their lazy
	# caches first.
	_surface.prime()
	FeatureRibbonPlanner.is_clear(_grid, 0.0, 0.0)
	_lattice = TerrainLattice.new(rect, _surface)
	_mesh_origin = _lattice.origin
	_mesh_step = Vector2.ONE * TerrainLattice.STEP
	_mesh_cells = _lattice.cells
	_terrain = TerrainChunks.new(grid, hex_size, _lattice, _terrain_material(), _look)
	_tiles_root.add_child(_terrain.coarse_root)
	_tiles_root.add_child(_terrain.fine_root)
	_terrain.build_all_coarse(threads)
	_chunks.register(_terrain.chunk_layer())
	_near = null
	if quality.get("terrain_lod", true):
		_near = TerrainNear.new(_terrain, _surface)
		_tiles_root.add_child(_near.root)
		_chunks.register(_near.chunk_layer())
		_near_on = TerrainNear.wanted(_camera_distance, false)
		_chunks.set_enabled(TerrainNear.LAYER, _near_on)
	_tiles_root.add_child(_build_backdrop(_lattice.rect()))
	FeatureRibbons.add_to(_tiles_root, _grid, _ribbon_drape, _terrain_material(), quality, false)
	if bake_task >= 0:
		WorkerThreadPool.wait_for_task_completion(bake_task)
	_parcels = baked[0]
	TerrainGround.set_parcels(_terrain_material(), _parcels, quality)
	_trees.clear()
	_foliage = null
	if quality.get("foliage", true):
		var ring: HexGrid = null
		var ring_surface: TerrainSurface = null
		if quality.get("backdrop_scatter", true):
			ring = _backdrop_ring(_lattice.rect())
			ring_surface = BackdropSurface.new(ring, visible_ground_height)
			_tiles_root.add_child(_build_backdrop_canopy())
		_foliage = FoliageChunks.new(
			grid,
			_surface,
			_parcels,
			SCATTER_SEED,
			_lattice.rect(),
			playable,
			_trees,
			ring,
			ring_surface,
			_look
		)
		_foliage.tree_features = tree_features
		for parent in _foliage.parents():
			_tiles_root.add_child(parent)
		_chunks.register(_foliage.scatter_layer())
		_chunks.register(_foliage.tree_layer())
	if _foliage != null:
		# Real scale (TASK-135): the map trees on the drawn near surface, the dense forest.
		if VisualScale.is_true_size():
			_foliage.ground = vegetation_ground_height
		var shell := _vegetation.build_forest(
			grid, vegetation_ground_height, _lattice, SCATTER_SEED, _lattice.rect(), _parcels, _look
		)
		if shell != null:
			SatelliteColour.apply(shell.mesh.surface_get_material(0) as ShaderMaterial, satellite)
			_tiles_root.add_child(shell)
	_tiles_root.add_child(WaterPlane.build(rect, DETAIL_SIZE))
	Wind.setup(quality.get("wind", true))
	# The grass stands on the drawn mesh: its heights are a lookup in the mesh's height grid,
	# far cheaper than the surface (noise octaves per query) and safe on the planning threads.
	var grass_free := _chunks.free_radius(&"grass")
	# Real scale: the clumps stand on the drawn near surface, not the 36 m lattice (TASK-135).
	var grass_ground := vegetation_ground_height if VisualScale.is_true_size() else mesh_height_at
	_grass.setup(
		grid,
		BackdropSurface.new(grid, grass_ground),
		playable,
		quality.get("grass_density", 1.0),
		_grass_color,
		GrassPlanner.INSTANCE_BUDGET,
		_parcels,
		PI * grass_free * grass_free,
		_look
	)
	if _grass.is_active():
		var grass_layer := _grass.chunk_layer(_chunks.invalidate)
		var grass_prepare := grass_layer.prepare
		grass_layer.prepare = func() -> void:
			grass_prepare.call()
			_prime_grass_colors()
		_chunks.register(grass_layer)
	_vegetation.build_grass(
		_grass, grid, BackdropSurface.new(grid, grass_ground), playable, _prime_grass_colors
	)
	_grid_lines = _build_grid_lines()
	_tiles_root.add_child(_grid_lines)
	_chunks.register(
		ChunkLayer.new(
			&"grid",
			TreeField.CHUNK_SIZE,
			_lattice.rect(),
			_build_grid_chunk,
			_free_grid_chunk,
			_plan_grid_chunk
		)
	)
	_update_grid()


## The chunk manager of this view: other systems (GroundMarksView) register their layers here.
func chunks() -> ChunkManager:
	return _chunks


## Where the camera looks (XZ): chunks near it are built (in _process, within the frame budget),
## chunks far from it freed.
func set_camera_target(target: Vector2) -> void:
	_chunks.update(target)


## Builds every chunk the rings ask for around the current camera target now (loading screen,
## tests, screenshots); `target` moves the target first; the camera-centred layers too.
func finish_chunks(target: Variant = null) -> void:
	if target != null:
		_chunks.update(target)
	_follow_viewport_camera()
	_chunks.finish_all()
	_vegetation.finish()


## True when every chunk around the camera target (and the camera) is built.
func chunks_settled() -> bool:
	return _chunks.is_settled() and _vegetation.is_settled()


func vegetation() -> RealScaleVegetation:
	return _vegetation


## Camera position (world) for the real-scale vegetation; _process() passes the viewport camera's.
func set_camera_position(position: Vector3) -> void:
	if _lattice == null:
		return
	_vegetation.set_camera(position, position.y - visible_ground_height(position.x, position.z))


func _follow_viewport_camera() -> void:
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position != _vegetation.camera_position:
		set_camera_position(camera.global_position)


## The drawn ground real-size vegetation stands on (TASK-135): the near terrain surface, else the
## lattice; `point`: the surface at the point (impostors: 1/3 of the cost, cm apart). Thread-safe.
func vegetation_ground_height(x: float, z: float, point := false) -> float:
	if _near != null and _lattice.rect().has_point(Vector2(x, z)):
		return _near.surface_point_height(x, z) if point else _near.surface_height_at(x, z)
	return _lattice.mesh_height_at(x, z)


## The terrain chunks (fine and coarse nodes), for tests and statistics.
func terrain() -> TerrainChunks:
	return _terrain


## The near terrain LOD (null on LOW quality), for tests and statistics.
func terrain_near() -> TerrainNear:
	return _near


## The bushes and rocks (null without foliage), for tests and statistics.
func foliage() -> FoliageChunks:
	return _foliage


## Burns the scatter around a wreck (BurntGround), also in chunks built later.
func burn_ground(center: Vector2, radius: float) -> void:
	if _foliage != null:
		_foliage.burn(center, radius)
	_vegetation.burn(center, radius)


## The grass (TASK-057), for tests and statistics.
func grass() -> GrassField:
	return _grass


## The trees (TASK-060), for tests and statistics.
func trees() -> TreeField:
	return _trees


## The surface the terrain mesh is built from; use it for picking and placing things.
func surface() -> TerrainSurface:
	return _surface


## Height of the drawn terrain mesh at (x, z) – what overlays and markers drape onto. Thread-safe
## (the grass plans read it).
func mesh_height_at(x: float, z: float) -> float:
	return _lattice.mesh_height_at(x, z)


## Height of the ground the player sees at (x, z): the terrain mesh on the playable rectangle,
## the backdrop beyond it. The camera keeps its clearance above this.
func visible_ground_height(x: float, z: float) -> float:
	if _lattice.rect().has_point(Vector2(x, z)):
		return _lattice.mesh_height_at(x, z)
	return maxf(_backdrop.height_at(x, z), TerrainSurface.WATER_SURFACE)


## The ground the camera keeps its clearance above (TASK-111): visible_ground_height, and on the
## playable rectangle also the finer surface the near terrain LOD (TerrainNear) draws, which can
## rise above the coarser lattice between its vertices – at a 26 m close-up that matters – and
## never below the water plane (WaterPlane), so the camera stays out of a lake.
func camera_ground_height(x: float, z: float) -> float:
	var h := maxf(visible_ground_height(x, z), TerrainSurface.WATER_SURFACE)
	if _near != null and _lattice.rect().has_point(Vector2(x, z)):
		h = maxf(h, _near.surface_height_at(x, z))
	return h


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
		TerrainGround.set_parcels(_ground_material, _parcels, quality)
		SatelliteColour.apply(_ground_material, satellite)
	return _ground_material


## The non-playable scenery ring around `rect` (the playable mesh), see BackdropMesh.
func _build_backdrop(rect: Rect2) -> MeshInstance3D:
	_backdrop_types = BackdropTypes.new(_grid, hex_size, _mesh_origin, _mesh_step, _look)
	_backdrop = BackdropMesh.new(rect, _mesh_cells, _lattice.height, BACKDROP_WIDTH, DETAIL_TILE)
	# The vertex callbacks run on the worker threads: fill the shares they read first.
	for key in _backdrop.border_keys():
		_backdrop_types.border_shares(key.x, key.y)
	var mesh := _backdrop.build_mesh(
		_backdrop_types.backdrop_vertex, TerrainGround.add_surface, threads
	)
	mesh.surface_set_material(0, _terrain_material())
	var instance := MeshInstance3D.new()
	instance.name = "Backdrop"
	instance.set_layer_mask_value(TERRAIN_VISUAL_LAYER, true)
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Distant forest shell over the backdrop lattice: the forest share of the nearest border tiles
## (the same samples as the backdrop ground) faded in with the distance from the playable mesh,
## drawn by canopy.gdshader as crowns.
func _build_backdrop_canopy() -> MeshInstance3D:
	var lift := VisualScale.tree_scale() * BackdropCanopy.HEIGHT
	var mesh := _backdrop.build_mesh(
		_backdrop_types.canopy_vertex, BackdropCanopy.add_surface.bind(lift), threads
	)
	var canopy := BackdropCanopy.material()
	SatelliteColour.apply(canopy, satellite)
	mesh.surface_set_material(0, canopy)
	var instance := MeshInstance3D.new()
	instance.name = "BackdropCanopy"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## The virtual tiles of the backdrop scatter (FoliageChunks): a tile ring around the map that
## copies the nearest map tile's terrain, as far as the backdrop scatter reaches (plus a margin for
## the edge plants, which look at the neighbours).
func _backdrop_ring(inner: Rect2) -> HexGrid:
	var ring := HexGrid.new()
	var outer := _backdrop.outer_rect().intersection(
		inner.grow(BACKDROP_SCATTER_REACH + ScatterPlanner.TILE_REACH + 2.0 * hex_size)
	)
	for c in ScatterPlanner.coords_near(_all_tiles_grid(outer), outer):
		var w := Hex.to_world(c, hex_size)
		var p := Vector2(w.x, w.z)
		if _grid.has_tile(c) or inner.has_point(p):
			continue
		var border := BackdropHeights.nearest_border_point(inner, p.x, p.y)
		ring.set_terrain(c, _backdrop_types.ring_type(p, border) as Terrain.Type)
	return ring


## A grid with a tile on every hex centre of `rect` (to enumerate the hexes there).
func _all_tiles_grid(rect: Rect2) -> HexGrid:
	var all := HexGrid.new()
	var r0 := floori(rect.position.y / (1.5 * hex_size))
	var r1 := ceili(rect.end.y / (1.5 * hex_size))
	for r in range(r0, r1 + 1):
		var q0 := floori(rect.position.x / (Hex.SQRT3 * hex_size) - r / 2.0)
		var q1 := ceili(rect.end.x / (Hex.SQRT3 * hex_size) - r / 2.0)
		for q in range(q0, q1 + 1):
			all.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	return all


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


## Main thread, before grass plans run: the layer colours the planning threads read.
func _prime_grass_colors() -> void:
	if _layer_averages.is_empty():
		_layer_averages.assign(
			TerrainTextures.arrays(TerrainGround.texture_size(quality))["average_colors"]
		)


## Linear ground colour under a grass clump: the mean albedo of each ground layer
## (TerrainTextures "average_colors", tint included) weighted by the TerrainSplat weights the
## terrain shader blends.
func _grass_color(p: Vector3) -> Color:
	if _layer_averages.is_empty():
		_prime_grass_colors()
	var averages := _layer_averages
	var slope := GrassPlanner.slope(_surface, p.x, p.z)
	var normal_y := 1.0 / sqrt(1.0 + slope * slope)
	var terrain := (
		_look.terrain_at(p.x, p.z)
		if _look != null
		else _grid.get_terrain(Hex.from_world(p, hex_size))
	)
	var weights := _splat(terrain, normal_y, p, _splat_noise(p.x, p.z))
	var color := Color(0, 0, 0)
	for layer in TerrainSplat.LAYER_COUNT:
		color += averages[layer] * weights[layer]
	return Color(color.r, color.g, color.b)


## Height of the terrain mesh at (x, z) (TerrainLattice.mesh_height_at): matches the drawn mesh
## exactly (lines never sink into it) and is much cheaper than TerrainSurface.ground_height.
func _mesh_ground_height(x: float, z: float) -> float:
	return _lattice.mesh_height_at(x, z)


## The parent of the grid line chunks and their shared material (the "grid" chunk layer builds
## the lines of the tiles whose centre lies in a chunk; shared edges are drawn twice, like in the
## design).
func _build_grid_lines() -> Node3D:
	var material := StandardMaterial3D.new()
	_grid_material = material
	material.albedo_color = GRID_LINE_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var root := Node3D.new()
	root.name = "GridLines"
	return root


## The line points of the tile outlines in `chunk` (worker thread: reads the grid and the mesh
## heights only).
func _plan_grid_chunk(chunk: Vector2i) -> PackedVector3Array:
	var corners: Array[Vector2] = []
	for s in 7:
		var angle := deg_to_rad(60.0 * s - 30.0)
		corners.append(Vector2(cos(angle), sin(angle)) * hex_size)
	var rect := Rect2(Vector2(chunk) * TreeField.CHUNK_SIZE, Vector2.ONE * TreeField.CHUNK_SIZE)
	var points := PackedVector3Array()
	for c in ScatterPlanner.coords_near(_grid, rect):
		var center := Hex.to_world(c, hex_size)
		if not ScatterPlanner.in_rect(center, rect):
			continue  # on the chunk's end edge: the next chunk draws it
		if _grid.get_terrain(c) == Terrain.Type.WATER:
			continue  # never over water; shared shore edges are drawn by the land side
		for s in 6:
			for k in GRID_LINE_SEGMENTS:
				for t: float in [float(k) / GRID_LINE_SEGMENTS, float(k + 1) / GRID_LINE_SEGMENTS]:
					var p := corners[s].lerp(corners[s + 1], t)
					var x := center.x + p.x
					var z := center.z + p.y
					points.append(Vector3(x, _mesh_ground_height(x, z) + GRID_LINE_OFFSET, z))
	return points


func _build_grid_chunk(chunk: Vector2i, points: PackedVector3Array) -> void:
	_free_grid_chunk(chunk)
	if points.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh.surface_set_material(0, _grid_material)
	var instance := MeshInstance3D.new()
	instance.name = "GridLines_%d_%d" % [chunk.x, chunk.y]
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grid_lines.add_child(instance)
	_grid_chunks[chunk] = instance


func _free_grid_chunk(chunk: Vector2i) -> void:
	var node: MeshInstance3D = _grid_chunks.get(chunk)
	if node != null:
		_grid_lines.remove_child(node)
		node.queue_free()
	_grid_chunks.erase(chunk)


## The built grid line chunks, for tests.
func grid_line_nodes() -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	result.assign(_grid_chunks.values())
	return result


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


## Marks the tiles a ranged unit can shoot at (RangeOverlayModel sets): tint and outline of the
## effective range, a paler band for the `extended` range and a dark wash on the `blocked` tiles
## (RangeOverlayMesh). Two meshes in all, the tints are vertex colours.
func show_attack_range(
	effective: Array[Vector2i], extended: Array[Vector2i] = [], blocked: Array[Vector2i] = []
) -> void:
	var any := not effective.is_empty() or not extended.is_empty()
	_range_fill.visible = any
	_range_line.visible = any
	if not any:
		_range_fill.mesh = null
		_range_line.mesh = null
		return
	var tile_shape := func(c: Vector2i) -> PackedVector3Array:
		return _tile_shape(c, RANGE_FILL_SHAPE)
	var fill := RangeOverlayMesh.fill(effective, extended, blocked, tile_shape)
	_range_fill.mesh = _triangles_mesh(fill[0], fill[1])
	_range_fill.position.y = RANGE_FILL_LIFT
	_range_fill.material_override = _overlay_material(Color.WHITE, false)
	var outline := RangeOverlayMesh.outline(effective, extended, hex_size, _drape)
	_range_line.mesh = _triangles_mesh(outline[0], outline[1])
	_range_line.position.y = RANGE_LINE_LIFT
	_range_line.material_override = _overlay_material(Color.WHITE)


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
	if _near != null:
		_near_on = TerrainNear.wanted(distance, _near_on)
		_chunks.set_enabled(TerrainNear.LAYER, _near_on)
	_update_grid()


## Grid mode auto (fades with zoom) <-> off. A view setting only. Returns whether the grid is on.
func cycle_grid_mode() -> bool:
	_grid_auto = not _grid_auto
	_update_grid()
	return _grid_auto


## Sets the grid mode (auto on / off) without toggling; a view setting only.
func set_grid_auto(on: bool) -> void:
	_grid_auto = on
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


## Ribbon and bridge points: the exact ground (TerrainSurface), which the near terrain LOD draws
## close up; the coarse mesh seen from afar can rise above it, so the ribbon shaders pull the
## ribbon towards the camera in depth instead of lifting the geometry.
func _ribbon_drape(points: PackedVector2Array, lift: float) -> PackedVector3Array:
	return OverlayGeometry.drape_with(points, _surface.ground_height, lift)


## Overlay points follow the drawn mesh (_mesh_ground_height), not TerrainSurface.ground_height:
## the mesh is a coarse linear interpolation of the surface, so hills can poke through
## overlays that follow the exact surface, and the mesh query is ~100x cheaper in GDScript
## (thousands of vertices per rebuild).
func _drape(points: PackedVector2Array, lift: float) -> PackedVector3Array:
	return OverlayGeometry.drape_with(points, _mesh_ground_height, lift)


static func _triangles_mesh(
	vertices: PackedVector3Array, colors := PackedColorArray()
) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
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
