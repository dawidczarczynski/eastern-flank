class_name RealScaleVegetation
extends RefCounted
## MapView's real-scale vegetation (TASK-135, ADR 0026; `true` VisualScale preset only): the dense
## forest (ForestField: full trees around the camera, impostors around the camera target, the
## ForestShell canopy beyond), the real-density grass near the camera (GrassNear) and the second,
## camera-centred ChunkManager that carries the layers following the camera rather than its
## target. The near layers (full trees, near grass, impostors) are switched off while the camera
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
var grass_near := GrassNear.new()
var chunks := ChunkManager.new()
## The last camera position (INF: none yet).
var camera_position := Vector3.INF

var _main: ChunkManager
var _active := false
## Layer id -> whether it is on.
var _on: Dictionary = {}


func _init() -> void:
	forest.name = "Forest"
	grass_near.name = "GrassNear"


## A new build: a fresh camera manager (same rings and threading as `main`); nothing is active
## until build_forest / build_grass.
func reset(main: ChunkManager, low_quality: bool, threads: bool) -> void:
	chunks.reset()
	chunks = ChunkManager.new(ChunkRings.load_default(), low_quality)
	chunks.threads = threads
	chunks.budget_usec = CAMERA_CHUNK_BUDGET_USEC
	_main = main
	_on.clear()
	_active = VisualScale.is_true_size()
	camera_position = Vector3.INF
	forest.clear()
	grass_near.clear()


## The forest of `grid` over `rect`; returns the canopy shell node to add (null without forest).
## `ground` is MapView.vegetation_ground_height (thread-safe: the full trees), `lattice` the drawn
## terrain lattice (the GPU-placed impostors and the shell, ADR 0027).
func build_forest(
	grid: HexGrid,
	ground: Callable,
	lattice: TerrainLattice,
	seed_value: int,
	rect: Rect2,
	parcels: ParcelMap
) -> MeshInstance3D:
	if not _active:
		return null
	forest.setup(grid, ground, seed_value, rect, lattice, parcels)
	_main.register(forest.impostor_layer())
	chunks.register(forest.full_layer())
	var shell := ForestShell.build(grid, rect, lattice.mesh_height_at)
	if shell != null:
		forest.bind_shell(shell.mesh.surface_get_material(0) as ShaderMaterial)
	return shell


## The near grass on `grass`'s look (an active GrassField), standing on `surface`; `prime` runs
## before its plans (the ground colours the grass buffers read).
func build_grass(
	grass: GrassField, grid: HexGrid, surface: TerrainSurface, area: Rect2, prime: Callable
) -> void:
	grass.clearing_listeners.clear()
	if not _active or not grass.is_active():
		return
	grass_near.setup(grass, grid, surface, area)
	var layer := grass_near.chunk_layer()
	var near_prepare := layer.prepare
	layer.prepare = func() -> void:
		near_prepare.call()
		prime.call()
	chunks.register(layer)
	grass.clearing_listeners.append(
		func(rect: Rect2) -> void: chunks.invalidate(GrassNear.LAYER, rect)
	)


## The camera is at `position`, `gap` above the ground under it.
func set_camera(position: Vector3, gap: float) -> void:
	camera_position = position
	if not _active:
		return
	chunks.update(Vector2(position.x, position.z))
	var ranges := forest.max_ranges()
	_switch(chunks, ForestField.FULL_LAYER, gap, ranges.x)
	_switch(chunks, GrassNear.LAYER, gap, grass_near.draw_range())
	# The impostors stay built at any height: they cost nothing drawn beyond their range
	# (visibility range).
	forest.update(position)


func process() -> void:
	chunks.process()


## Builds every camera-centred chunk now (loading screen, tests, screenshots).
func finish() -> void:
	if camera_position == Vector3.INF:
		return
	chunks.finish_all()
	forest.update(camera_position)


func is_settled() -> bool:
	return camera_position == Vector3.INF or chunks.is_settled()


func burn(center: Vector2, radius: float) -> void:
	forest.burn(center, radius)


func _switch(manager: ChunkManager, id: StringName, gap: float, reach: float) -> void:
	var on: bool = _on.get(id, true)
	on = gap < reach * (LAYER_OFF if on else LAYER_ON)
	_on[id] = on
	manager.set_enabled(id, on)
