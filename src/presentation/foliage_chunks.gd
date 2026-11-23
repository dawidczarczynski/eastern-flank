class_name FoliageChunks
extends RefCounted
## The planted scenery of a MapView as two chunk layers (TASK-072b): "scatter" – bushes and rocks
## (ScatterChunks nodes under "Bushes", "Rocks", "BackdropBushes", "BackdropRocks") – and "trees"
## (TreeField chunks: trees, young trees, edge shrubs, ground cover, meadow scrub). A chunk's
## content is the ScatterPlanner plan of the map (plus hedgerows) and of the virtual tile ring
## around it (the backdrop: nearest map terrain, BACKDROP_SCATTER_DENSITY, within
## BACKDROP_SCATTER_REACH of the playable mesh) restricted to the chunk – the same items an eager
## plan of the whole map has there, whatever the build order. Both layers read one cached plan per
## chunk (planned once, on a worker thread). Burnt ground (BurntGround) is remembered and applied
## to chunks built later.

const SCATTER_NODES: Array[String] = ["Bushes", "Rocks", "BackdropBushes", "BackdropRocks"]
const LAYER_COUNT := 2

## Real scale (TASK-135): Callable(x, z) -> the drawn near surface height the map trees stand on
## (unset: their planned height).
var ground := Callable()
## Real tree features (TASK-199b, TreeFeatureSet, BattleCover.tree_features_for_battle): the OSM
## trees of the map, or null; the rule fill of TreeFeatures needs none. Set before the first plan.
var tree_features: TreeFeatureSet

var _grid: HexGrid
var _surface: TerrainSurface
var _parcels: ParcelMap
var _seed := 0
## Playable mesh rectangle (backdrop thinning) and the playable tiles' bounds (TreeField).
var _inner := Rect2()
var _playable := Rect2()
var _trees: TreeField
## Virtual backdrop tiles and the ground they stand on (null: no backdrop scatter).
var _ring: HexGrid
var _ring_surface: TerrainSurface
## The land-cover look (TASK-108g), or null: the scatter follows the hex types.
var _look: CoverLook
var _parents: Dictionary = {}
var _crown_material: StandardMaterial3D
var _rock_material: StandardMaterial3D
var _mutex := Mutex.new()
## Vector2i chunk -> {"plan": {map, backdrop}, "taken": {layer: true}}.
var _cache: Dictionary = {}
## Vector2i chunk -> Array[MultiMeshInstance3D] of the scatter layer.
var _scatter_nodes: Dictionary = {}
## Burnt circles: Vector3(x, radius, z).
var _burns: Array[Vector3] = []


func _init(
	grid: HexGrid,
	surface: TerrainSurface,
	parcels: ParcelMap,
	seed_value: int,
	inner: Rect2,
	playable: Rect2,
	trees: TreeField,
	ring: HexGrid = null,
	ring_surface: TerrainSurface = null,
	look: CoverLook = null
) -> void:
	_grid = grid
	_look = look
	_surface = surface
	_parcels = parcels
	_seed = seed_value
	_inner = inner
	_playable = playable
	_trees = trees
	_ring = ring
	_ring_surface = ring_surface
	for node_name in SCATTER_NODES:
		var parent := Node3D.new()
		parent.name = node_name
		_parents[node_name] = parent
	_crown_material = MapView._scatter_material(Color.WHITE, 0.92, true)
	# The rock mesh has no vertex colours (white); the instance colour tints it.
	_rock_material = MapView._scatter_material(Color.WHITE, 0.95, true)


## The parent nodes (added to the map view by the caller; backdrop ones only with a ring).
func parents() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node_name in SCATTER_NODES:
		if _ring != null or not node_name.begins_with("Backdrop"):
			result.append(_parents[node_name])
	return result


## Where foliage can stand: the playable mesh and the backdrop scatter reach around it.
func area() -> Rect2:
	return _inner.grow(MapView.BACKDROP_SCATTER_REACH if _ring != null else 0.0)


func scatter_layer() -> ChunkLayer:
	var result := ChunkLayer.new(
		&"scatter", TreeField.CHUNK_SIZE, area(), build_scatter, free_scatter, plan_scatter
	)
	result.prepare = prepare
	return result


func tree_layer() -> ChunkLayer:
	var result := ChunkLayer.new(
		&"trees", TreeField.CHUNK_SIZE, area(), build_trees, free_trees, plan_trees
	)
	result.prepare = prepare
	return result


## Main thread, before plans run on the worker threads: fills the lazy caches they read.
func prepare() -> void:
	_surface.prime()
	TreeField.prime_sizes()
	FeatureRibbonPlanner.is_clear(_grid, 0.0, 0.0)


## Remembers a burnt circle and burns the built chunks it touches (BurntGround).
func burn(center: Vector2, radius: float) -> void:
	_burns.append(Vector3(center.x, radius, center.y))
	var nodes: Array = []
	for list: Array in _scatter_nodes.values():
		nodes.append_array(list)
	nodes.append_array(_trees.get_children())
	BurntGround.burn_instances(nodes, center, radius)


## The map and backdrop plan of `chunk` for layer `consumer`, planned once for both layers.
func source(chunk: Vector2i, consumer: StringName) -> Dictionary:
	_mutex.lock()
	var entry: Variant = _cache.get(chunk)
	_mutex.unlock()
	var plan: Dictionary
	if entry != null:
		plan = (entry as Dictionary)["plan"]
	else:
		plan = _plan_source(chunk)
	_mutex.lock()
	var stored: Dictionary = _cache.get_or_add(chunk, {"plan": plan, "taken": {}})
	(stored["taken"] as Dictionary)[consumer] = true
	plan = stored["plan"]
	if (stored["taken"] as Dictionary).size() >= LAYER_COUNT:
		_cache.erase(chunk)
	_mutex.unlock()
	return plan


func _plan_source(chunk: Vector2i) -> Dictionary:
	var rect := Rect2(Vector2(chunk) * TreeField.CHUNK_SIZE, Vector2.ONE * TreeField.CHUNK_SIZE)
	var map := ScatterPlanner.plan_rect(_grid, _surface, _seed, rect, _parcels, _look)
	var hedges := ScatterPlanner.plan_hedges(_grid, _surface, _parcels, rect)
	(map["trees"] as Array).append_array(hedges["trees"])
	(map["edge_shrubs"] as Array).append_array(hedges["edge_shrubs"])
	# Riparian belt of shrubs and alders along rivers (empty on maps without rivers).
	var riparian := RiparianPlanner.plan(_grid, _surface, _parcels, rect, _look)
	(map["trees"] as Array).append_array(riparian["trees"])
	(map["edge_shrubs"] as Array).append_array(riparian["edge_shrubs"])
	# Real tree features (TASK-199b; true preset only, the list is empty otherwise).
	(map["trees"] as Array).append_array(
		TreeFeatures.plan(_grid, _surface, _seed, rect, _parcels, _look, tree_features)
	)
	var backdrop := {}
	for key: String in ScatterPlanner.PLAN_KEYS:
		backdrop[key] = []
	if _ring != null and not _inner.encloses(rect):
		backdrop = ScatterPlanner.plan_rect(_ring, _ring_surface, _seed, rect, _parcels, _look)
		# Far away: the ground cover is not worth its triangles.
		backdrop["ground_cover"] = []
		# Deterministic per-position thinning (no spatial pattern from the plan order).
		for key: String in ScatterPlanner.PLAN_KEYS:
			var kept: Array = []
			for item: Dictionary in backdrop[key]:
				var p: Vector3 = item["position"]
				var q := Vector2(p.x, p.z)
				if (
					(
						q.distance_to(q.clamp(_inner.position, _inner.end))
						<= MapView.BACKDROP_SCATTER_REACH
					)
					and (
						TerrainNoise.hash(p.x * 7.13, p.z * 5.71, MapView.BACKDROP_THIN_SEED)
						< MapView.BACKDROP_SCATTER_DENSITY
					)
				):
					kept.append(item)
			backdrop[key] = kept
	return {"map": map, "backdrop": backdrop}


## Bush and rock instances of `chunk` per node name: {name: [Array[Transform3D], colours]}.
func plan_scatter(chunk: Vector2i) -> Dictionary:
	var plan := source(chunk, &"scatter")
	var result := {}
	for prefix: String in ["", "Backdrop"]:
		var part: Dictionary = plan["backdrop" if prefix == "Backdrop" else "map"]
		var bushes: Array = part["bushes"]
		result[prefix + "Bushes"] = [
			MapView._tree_transforms(bushes, VisualScale.bush_scale()),
			MapView._tree_colors(bushes, MapView.BUSH_COLOR_A, MapView.BUSH_COLOR_B)
		]
		var rock_transforms: Array[Transform3D] = []
		var rock_colors := PackedColorArray()
		for r: Dictionary in part["rocks"]:
			var s: float = r["scale"] * VisualScale.rock_scale()
			var basis := (
				Basis.from_euler(r["rotation"], EULER_ORDER_XYZ)
				* Basis.from_scale(Vector3(s, 0.7 * s, s))
			)
			rock_transforms.append(Transform3D(basis, r["position"]))
			rock_colors.append(
				MapView.ROCK_COLOR_A.lerp(
					MapView.ROCK_COLOR_B, fposmod(s * MapView.ROCK_SHADE_FREQ, 1.0)
				)
			)
		result[prefix + "Rocks"] = [rock_transforms, rock_colors]
	return result


func build_scatter(chunk: Vector2i, plan: Dictionary) -> void:
	free_scatter(chunk)
	var nodes: Array[MultiMeshInstance3D] = []
	for node_name: String in plan:
		if not _parents.has(node_name):
			continue
		var entry: Array = plan[node_name]
		var bushes := node_name.ends_with("Bushes")
		var built := ScatterChunks.build_chunk(
			node_name,
			FoliageMeshes.bush() if bushes else FoliageMeshes.rock(),
			_crown_material if bushes else _rock_material,
			entry[0],
			entry[1],
			chunk,
			FoliageMeshes.bush_far() if bushes else null
		)
		for node in built:
			(_parents[node_name] as Node3D).add_child(node)
		nodes.append_array(built)
	_scatter_nodes[chunk] = nodes
	_apply_burns(nodes)


func free_scatter(chunk: Vector2i) -> void:
	for node: MultiMeshInstance3D in _scatter_nodes.get(chunk, []):
		node.get_parent().remove_child(node)
		node.queue_free()
	_scatter_nodes.erase(chunk)


## The TreeField plan of `chunk` (map trees with the open-ground thickets, backdrop trees).
func plan_trees(chunk: Vector2i) -> Dictionary:
	var plan := source(chunk, &"trees")
	var lists: Array = []
	for part_name: String in ["map", "backdrop"]:
		var part: Dictionary = plan[part_name]
		var trees: Array = []
		for key: String in ["trees", "young_trees", "edge_shrubs", "ground_cover"]:
			trees.append_array(part[key])
		# Thickets on open ground (TASK-070) belong to the playable map only.
		if part_name == "map":
			trees.append_array(part["meadow_scrub"])
		lists.append(trees)
	return TreeField.plan_chunk(chunk, lists[0], lists[1], _playable, ground, is_forest)


## Whether `position` lies on a forest tile of the map, or on the forest cover with a land-cover
## raster (its trees' impostors end at the canopy shell, TASK-135). Pure.
func is_forest(position: Vector3) -> bool:
	if _look != null:
		return _look.is_forest(position.x, position.z)
	var coord := Hex.from_world(position, TerrainField.HEX_SIZE)
	return _grid.has_tile(coord) and _grid.get_terrain(coord) == Terrain.Type.FOREST


func build_trees(chunk: Vector2i, plan: Dictionary) -> void:
	_trees.build_chunk(chunk, plan)
	_apply_burns(_trees.chunk_nodes(chunk))


func free_trees(chunk: Vector2i) -> void:
	_trees.free_chunk(chunk)


## Scatter nodes of the built chunks (statistics, tests).
func scatter_nodes() -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for list: Array in _scatter_nodes.values():
		result.append_array(list)
	return result


func _apply_burns(nodes: Array) -> void:
	for burn_circle in _burns:
		BurntGround.burn_instances(nodes, Vector2(burn_circle.x, burn_circle.z), burn_circle.y)
