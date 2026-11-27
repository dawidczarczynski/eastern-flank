class_name RealScaleVegetation
extends RefCounted
## MapView's real-scale vegetation (TASK-135, ADR 0026; `true` VisualScale preset only): the dense
## forest (ForestField: GPU-placed full trees around the camera and impostors around the camera
## target, the ForestShell canopy beyond), the GPU-placed shrubs and near grass (ShrubField,
## GpuGrassField) and
## the second, camera-centred ChunkManager that carries the layers following the camera rather than
## its target. The near layers (full trees, near grass, impostors) are switched off while the camera
## is higher above the ground than they reach (with hysteresis), so a zoomed-out view plans and
## draws none of them.

## Main-thread build time per frame of the camera-centred layers, on top of the main manager's.
const CAMERA_CHUNK_BUDGET_USEC := 2000
## A layer goes off once the camera is this many times its reach above the ground and on again
## below LAYER_ON x: the lead lets the chunks stream in while the camera zooms down, before the
## canopy shell fades out and the layer has to carry the forest.
const LAYER_OFF := 2.5
const LAYER_ON := 2.0

var forest := ForestField.new()
## GPU-placed shrubs (TASK-217a, ADR 0033): two instant layers on the camera manager.
var shrubs := ShrubField.new()
## GPU-placed near grass (TASK-217b, ADR 0033): one instant layer on the camera manager, HIGH only.
var grass := GpuGrassField.new()
var chunks := ChunkManager.new()
## The last camera position (INF: none yet).
var camera_position := Vector3.INF

var _main: ChunkManager
var _active := false
## Layer id -> whether it is on.
var _on: Dictionary = {}
var _shrubs_on := false
var _grass_on := false
## The drawn near heights the GPU-placed trees, shrubs and grass stand on (TASK-217a): one window
## on the camera target, shared (null: no near terrain, everything stands on the lattice).
var _near_heights: NearHeightCache
## GraphicsQuality features of the build (the shrubs' range).
var _quality: Dictionary = {}


func _init() -> void:
	forest.name = "Forest"
	grass.name = "Grass"
	shrubs.name = "Shrubs"


## A new build: a fresh camera manager (same rings and threading as `main`); nothing is active
## until build_forest / build_grass.
func reset(main: ChunkManager, low_quality: bool, threads: bool, quality := {}) -> void:
	_quality = quality
	chunks.reset()
	chunks = ChunkManager.new(ChunkRings.load_default(), low_quality)
	chunks.threads = threads
	chunks.budget_usec = CAMERA_CHUNK_BUDGET_USEC
	_main = main
	_on.clear()
	_active = VisualScale.is_true_size()
	camera_position = Vector3.INF
	forest.clear()
	grass.clear()
	shrubs.clear()
	_shrubs_on = false
	_grass_on = false
	_near_heights = null


## The forest of `grid` (or of the land-cover `look`, TASK-108g) over `rect`; returns the canopy
## shell node to add (null without forest).
## `lattice` is the drawn terrain lattice (the GPU-placed trees, impostors and the shell, ADR 0027).
func build_forest(
	grid: HexGrid,
	lattice: TerrainLattice,
	seed_value: int,
	rect: Rect2,
	parcels: ParcelMap,
	look: CoverLook = null
) -> MeshInstance3D:
	if not _active:
		return null
	forest.setup(grid, seed_value, rect, lattice, parcels, look)
	forest.use_near_heights(_near_window(lattice))
	_main.register(forest.impostor_layer())
	build_shrubs(
		grid, lattice, seed_value, rect, parcels, look.cover if look != null else null, _quality
	)
	var shell := ForestShell.build(grid, rect, lattice.mesh_height_at, look)
	if shell != null:
		forest.bind_shell(shell.mesh.surface_get_material(0) as ShaderMaterial)
	return shell


## The shrubs of `grid` over `rect` (TASK-217a; build_forest calls it after the forest, whose
## stand mask gives the forest edges); `quality` the GraphicsQuality features.
func build_shrubs(
	grid: HexGrid,
	lattice: TerrainLattice,
	seed_value: int,
	rect: Rect2,
	parcels: ParcelMap,
	land_cover: LandCover,
	quality: Dictionary
) -> void:
	if not _active:
		return
	shrubs.setup(grid, lattice, seed_value, rect, parcels, land_cover, forest.fill(), quality)
	shrubs.use_near_heights(_near_window(lattice))
	chunks.register(shrubs.near_layer())
	chunks.register(shrubs.impostor_layer())
	_shrubs_on = true


## The shared near-height window (null without a near terrain layer), made on first use.
func _near_window(lattice: TerrainLattice) -> NearHeightCache:
	if _near_heights == null:
		var near_layer := _main.layer(TerrainNear.LAYER)
		if near_layer != null and near_layer.build_chunk.get_object() is TerrainNear:
			var near := near_layer.build_chunk.get_object() as TerrainNear
			_near_heights = NearHeightCache.new(near, near_layer, lattice.origin)
	return _near_heights


## The near grass (TASK-217b): over the maps of the shrubs (build_shrubs runs first: their masks,
## lattice heights and drawn near heights are the grass's), coloured by the ground textures'
## layers and the map's satellite colour layer (or null). None on a quality without "gpu_grass".
func build_grass(seed_value: int, parcels: ParcelMap, satellite: SatelliteColour) -> void:
	if not _active or not _shrubs_on or not _quality.get("gpu_grass", true):
		return
	var averages: Array = (
		TerrainTextures.arrays(TerrainGround.texture_size(_quality))["average_colors"]
	)
	var ground: Array = [averages[TerrainSplat.GRASS], averages[TerrainSplat.DRY_GRASS]]
	if grass.setup(shrubs, seed_value, parcels, ground, satellite, _quality):
		chunks.register(grass.chunk_layer())
		_grass_on = true


## The camera is at `position`, `gap` above the ground under it.
func set_camera(position: Vector3, gap: float) -> void:
	camera_position = position
	if not _active:
		return
	chunks.update(Vector2(position.x, position.z))
	var ranges := forest.max_ranges()
	_switch_full_trees(gap, ranges.x)
	if _grass_on:
		_switch(chunks, GpuGrassField.LAYER, gap, grass.ring())
	if _shrubs_on:
		var shrub_ranges := shrubs.ranges_m()
		_switch(chunks, ShrubField.NEAR_LAYER, gap, MapScale.to_units(shrub_ranges.x))
		_switch(chunks, ShrubField.IMPOSTOR_LAYER, gap, MapScale.to_units(shrub_ranges.y))
	# The impostors stay built at any height: they cost nothing drawn beyond their range
	# (visibility range).
	forest.update(position)


func process() -> void:
	chunks.process()
	_update_near()


## Builds every camera-centred chunk now (loading screen, tests, screenshots).
func finish() -> void:
	if camera_position == Vector3.INF:
		return
	chunks.finish_all()
	forest.update(camera_position)
	_update_near()


## The near-height window follows the camera target (once a frame; a no-op when nothing changed).
func _update_near() -> void:
	if _near_heights != null and _main.has_target():
		_near_heights.update(_main.target())


func is_settled() -> bool:
	return camera_position == Vector3.INF or chunks.is_settled()


func burn(center: Vector2, radius: float) -> void:
	forest.burn(center, radius)
	if _shrubs_on:
		shrubs.burn(center, radius)
	if _grass_on:
		grass.burn(center, radius)


## The GPU full trees (no chunk layer) run only while the camera is low enough to see trees within
## their range (the same hysteresis as the chunk layers).
func _switch_full_trees(gap: float, reach: float) -> void:
	var on: bool = _on.get(ForestField.FULL_TREES, true)
	on = gap < reach * (LAYER_OFF if on else LAYER_ON)
	_on[ForestField.FULL_TREES] = on
	forest.set_full_active(on)


func _switch(manager: ChunkManager, id: StringName, gap: float, reach: float) -> void:
	var on: bool = _on.get(id, true)
	on = gap < reach * (LAYER_OFF if on else LAYER_ON)
	_on[id] = on
	manager.set_enabled(id, on)
