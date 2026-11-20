class_name ChunkLayer
extends RefCounted
## One layer of the chunked world (TASK-072b): what a system (terrain, scatter, trees, grass,
## ground marks, ...) hands the ChunkManager so its content exists only near the camera. The
## manager never knows what a layer draws; a new layer (TASK-134 terrain LOD, TASK-135 impostors)
## is one more ChunkLayer, not a manager change.
##
## The interface is three callables:
##   plan_chunk(chunk: Vector2i) -> Variant   optional; runs on a WorkerThreadPool thread, so it
##       may only read shared state (no Nodes, no RenderingServer, no GameState.rng) and must
##       give the same result for the same chunk in any order (ADR 0022 rule 2).
##   build_chunk(chunk: Vector2i, plan: Variant)   main thread: makes the nodes from the plan.
##   free_chunk(chunk: Vector2i)   main thread: drops the chunk's nodes.
## `prepare` (optional, main thread) runs before a batch of plans starts, e.g. to fill the lazy
## caches the planners read (TerrainSurface.prime).
## A chunk is the square Rect2(origin + chunk * chunk_size, chunk_size); only chunks that touch
## `area` exist.

## Ring id in ChunkRings.reach_m.
var id: StringName
var chunk_size := 8.0
var origin := Vector2.ZERO
var area := Rect2()
var plan_chunk := Callable()
var build_chunk := Callable()
var free_chunk := Callable()
var prepare := Callable()


func _init(
	layer_id: StringName,
	size: float,
	layer_area: Rect2,
	build_fn: Callable,
	free_fn: Callable,
	plan_fn := Callable(),
	layer_origin := Vector2.ZERO
) -> void:
	id = layer_id
	chunk_size = size
	area = layer_area
	build_chunk = build_fn
	free_chunk = free_fn
	plan_chunk = plan_fn
	origin = layer_origin


## World rectangle (XZ) of `chunk`.
func chunk_rect(chunk: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(chunk) * chunk_size, Vector2.ONE * chunk_size)


## The chunk that holds world point (x, z).
func chunk_at(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - origin.x) / chunk_size), floori((z - origin.y) / chunk_size))


## Distance (XZ) from `point` to the nearest point of `chunk` (0 inside it).
func distance_to(chunk: Vector2i, point: Vector2) -> float:
	var rect := chunk_rect(chunk)
	return point.distance_to(point.clamp(rect.position, rect.end))


## The layer's plan of `chunk` (null without a planner).
func plan(chunk: Vector2i) -> Variant:
	return plan_chunk.call(chunk) if plan_chunk.is_valid() else null
