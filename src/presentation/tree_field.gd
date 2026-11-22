class_name TreeField
extends Node3D
## The trees of a MapView (TASK-060): the planned trees (ScatterPlanner, map and backdrop) are
## grouped into CHUNK_SIZE x CHUNK_SIZE world-unit chunks (built and freed around the camera by the
## ChunkManager, TASK-072b, through FoliageChunks); each chunk gets one
## MultiMeshInstance3D per species x variant x LOD that has instances, with its origin at the
## chunk centre (visibility ranges measure from the node origin, so whole chunks switch).
## LOD0 (TreeMeshes.lod0: bark + leaf cards) is drawn up to LOD_DISTANCE from the camera, LOD1
## (TreeMeshes.lod1: bark + solid crown) up to LOD2_DISTANCE, LOD2 (TreeMeshes.lod2, coarser,
## trees only – scrub keeps LOD1) beyond, and all cast shadows (the cards' shadows are
## alpha-scissored). The LODs hand over per tree in the vertex shader: each tree switches at its
## own random point of the margin around the distance, measured from its base (`lod_bands`), so
## a stand changes gradually and no tree is drawn twice. The nodes' visibility ranges only cull
## whole chunks: RANGE_SLACK wider than the bands and without Godot's own range fade (which
## draws fading instances alpha-blended without the depth prepass, ~5 ms on the target GPU).
## Backdrop trees farther than BACKDROP_LOD0_REACH outside the playable tiles get only a
## "far" node with the LOD1 mesh and no range, which keeps the LOD0 triangles within the budget
## (LOD0_TRIANGLE_BUDGET within BUDGET_RADIUS of any playable tile centre).
## Species, variant and per-instance colour / wind phase come from TreeSpecies.pick.
## Under the `true` VisualScale preset (TASK-135, ADR 0026) the ranges are metres scaled by each
## species' real height (VegetationRanges): LOD0 up to the full range, then one impostor node per
## chunk (TreeImpostors, all species) up to the impostor range – where the canopy shell takes over
## on forest tiles – or, off the forest, until the impostor is under a couple of pixels; LOD1 /
## LOD2 are not used. Trees then stand on the drawn near surface (`ground`), sunk by a few
## decimetres instead of TREE_SINK.

enum Lod { NEAR, FAR_RANGE, FAR_ONLY, DISTANT, IMPOSTOR }

const CHUNK_SIZE := 8.0
const LOD_DISTANCE := 30.0
const LOD_MARGIN := 4.0
## Trees (not scrub) switch from LOD1 to the coarser LOD2 (TreeMeshes.lod2) here: on a large map
## thousands of distant LOD1 crowns were tiny triangles that cost ~2 ms on the target GPU.
const LOD2_DISTANCE := 46.0
const LOD2_MARGIN := 4.0
## A node's visibility range (measured from the chunk centre at y = 0) reaches this much past the
## switch band of its trees (measured per tree): no tree is farther from its chunk's centre.
const RANGE_SLACK := 8.0
## LOD_DISTANCE + LOD_MARGIN + CameraMath.CLOSE_RANGE_DISTANCE (7, the closest zoom before
## TASK-111; closer zooms bring the camera nearer its target, so this still bounds them).
const BUDGET_RADIUS := 41.0
const LOD0_TRIANGLE_BUDGET := 1100000
const BACKDROP_LOD0_REACH := 14.0
const LEAF_TEXTURE_SIZE := 128
## Low ground cover: no shadow casting (nor do backdrop trees: the shadow pass drew them in every
## cascade and cost most of the frame's triangles).
const NO_SHADOW_SPECIES := [&"undergrowth"]
## Scrub is small: its LOD0 range is shorter (and it therefore costs less of the budget).
const SCRUB_LOD_DISTANCE := {&"shrub": 22.0, &"undergrowth": 12.0}
const SCRUB_LOD_MARGIN := 2.0
const CLUSTER_SEED := 11
const NEEDLE_SEED := 23
const SHADER := preload("res://assets/shaders/foliage.gdshader")
## LOD1 / LOD2: the opaque variant (solid crown, no alpha, no wind).
const SOLID_SHADER := preload("res://assets/shaders/foliage_solid.gdshader")
## Species leaf colours (sRGB) and bark colours; the instance variation shifts them.
const LEAF_COLORS := {
	&"pine": Color("#41623f"),
	&"spruce": Color("#30503a"),
	&"birch": Color("#8fa94e"),
	&"oak": Color("#628538"),
	&"alder": Color("#557c36"),
	&"shrub": Color("#6a8c3a"),
	&"undergrowth": Color("#86a043"),
}
const BARK_COLORS := {
	&"pine": Color("#6e4c34"),
	&"spruce": Color("#4c3c2e"),
	&"birch": Color("#d6d2c4"),
	&"oak": Color("#4c3e2e"),
	&"alder": Color("#57493a"),
	&"shrub": Color("#5a4632"),
	&"undergrowth": Color("#4a4a30"),
}
## LOD1 crown albedo relative to the card texture's mean luminance (the cards' shadowed
## interior shows through the gaps, so the solid crown is darker than the texture itself).
const SOLID_LUMINANCE_FACTOR := 0.68
## Shader defaults of lod_band_in / lod_band_out: always in, never out.
const NO_LOD_IN := Vector2(-2.0, -1.0)
const NO_LOD_OUT := Vector2(1.0e8, 1.0e9)
## MultiMesh buffer floats per tree: TRANSFORM_3D (12) and the custom data (4).
const BUFFER_STRIDE := 16

static var _textures: Dictionary = {}
## "species:variant" -> LOD0 model size (scale 1), filled by prime_sizes().
static var _model_sizes: Dictionary = {}

var _planned := 0
var _backdrop := 0
var _materials: Dictionary = {}
var _impostor_material: ShaderMaterial
var _nodes: Dictionary = {
	Lod.NEAR: [], Lod.FAR_RANGE: [], Lod.FAR_ONLY: [], Lod.DISTANT: [], Lod.IMPOSTOR: []
}
## Node -> its MultiMesh buffer (the headless dummy renderer keeps no MultiMesh instance data, so
## tests and statistics read the transforms here).
var _local_transforms: Dictionary = {}
## Vector2i chunk -> Array[MultiMeshInstance3D] of the built chunks, and their tree counts
## (Vector2i(map, backdrop)).
var _chunk_nodes: Dictionary = {}
var _chunk_counts: Dictionary = {}


## Builds the chunk nodes for all the map trees and the backdrop trees at once (ScatterPlanner
## tree dictionaries). `playable` is the rectangle of the playable tiles (XZ). The chunked world
## (TASK-072b, FoliageChunks) uses plan_chunk / build_chunk / free_chunk instead.
func setup(map_trees: Array, backdrop_trees: Array, playable: Rect2) -> void:
	clear()
	var by_chunk: Dictionary = {}  # chunk -> [map trees, backdrop trees]
	for list_index in 2:
		for tree: Dictionary in [map_trees, backdrop_trees][list_index]:
			var lists: Array = by_chunk.get_or_add(chunk_of(tree["position"]), [[], []])
			(lists[list_index] as Array).append(tree)
	var chunks := by_chunk.keys()
	chunks.sort()
	for chunk: Vector2i in chunks:
		var lists: Array = by_chunk[chunk]
		build_chunk(chunk, plan_chunk(chunk, lists[0], lists[1], playable))


## Frees every chunk.
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_nodes = {Lod.NEAR: [], Lod.FAR_RANGE: [], Lod.FAR_ONLY: [], Lod.DISTANT: [], Lod.IMPOSTOR: []}
	_local_transforms.clear()
	_chunk_nodes.clear()
	_chunk_counts.clear()
	_planned = 0
	_backdrop = 0


## The MultiMesh groups of one chunk's trees: {"map": count, "backdrop": count, "groups": [{key,
## species, variant, lod, backdrop, count, buffer (PackedFloat32Array: MultiMesh TRANSFORM_3D
## relative to the chunk centre + custom data, BUFFER_STRIDE floats per tree)}]}, sorted by key.
## Pure (TreeSpecies.pick and VisualScale only; prime_sizes() first when it runs on a worker
## thread). Under the `true` preset: `ground` (Callable(x, z) -> float, thread-safe) re-seats the
## map trees on the drawn near surface, `canopy` (Callable(position) -> bool) tells the trees on
## forest tiles (their impostors end where the canopy shell starts); the impostors of the chunk
## are one extra group ({lod: IMPOSTOR, buffer: TreeImpostors.buffer}).
static func plan_chunk(
	chunk: Vector2i,
	map_trees: Array,
	backdrop_trees: Array,
	playable: Rect2,
	ground := Callable(),
	canopy := Callable()
) -> Dictionary:
	var groups: Dictionary = {}
	var origin := chunk_center(chunk)
	var total := map_trees.size() + backdrop_trees.size()
	var true_size := VisualScale.is_true_size()
	var vegetation := LookPreset.vegetation() if true_size else {}
	var impostors := {}
	for i in total:
		var backdrop := i >= map_trees.size()
		var tree: Dictionary = backdrop_trees[i - map_trees.size()] if backdrop else map_trees[i]
		var pick := TreeSpecies.pick(tree)
		var transform := tree_transform(tree, pick["species"], pick["variant"])
		var p: Vector3 = tree["position"]
		var far_only := (
			backdrop and _outside_distance(playable, Vector2(p.x, p.z)) > BACKDROP_LOD0_REACH
		)
		var lods: Array[Lod] = [Lod.NEAR, Lod.FAR_RANGE]
		if has_lod2(pick["species"]):
			lods.append(Lod.DISTANT)
		if far_only:
			lods = [Lod.FAR_ONLY]
		var custom: Color = pick["custom"]
		if true_size:
			lods.assign([] if far_only else [Lod.NEAR])
			if ground.is_valid() and not backdrop:
				transform.origin.y = ground.call(p.x, p.z) - sink(pick["species"], vegetation)
			var impostor := _impostor_entry(
				tree, pick, transform, far_only, canopy.is_valid() and canopy.call(p), vegetation
			)
			(impostors.get_or_add(backdrop, []) as Array).append(impostor)
		var local := Transform3D(transform.basis, transform.origin - origin)
		for lod in lods:
			var variant: int = pick["variant"] if lod == Lod.NEAR else 0
			var key := (
				"%d_%d_%s_%d_%d_%d"
				% [chunk.x, chunk.y, pick["species"], variant, lod, int(backdrop)]
			)
			if not groups.has(key):
				groups[key] = {
					"key": key,
					"species": pick["species"],
					"variant": variant,
					"lod": lod,
					"backdrop": backdrop,
					"local": [] as Array[Transform3D],
					"customs": [],
				}
			var group: Dictionary = groups[key]
			(group["local"] as Array[Transform3D]).append(local)
			(group["customs"] as Array).append(custom)
	var keys := groups.keys()
	keys.sort()
	var sorted: Array = []
	for key: String in keys:
		var group: Dictionary = groups[key]
		group["buffer"] = instance_buffer(group["local"], group["customs"])
		group["count"] = (group["local"] as Array).size()
		group.erase("customs")
		group.erase("local")
		sorted.append(group)
	for backdrop: bool in [false, true]:
		var entries: Array = impostors.get(backdrop, [])
		if entries.is_empty():
			continue
		(
			sorted
			. append(
				{
					"key": "%d_%d_impostor_%d" % [chunk.x, chunk.y, int(backdrop)],
					"species": &"impostor",
					"variant": 0,
					"lod": Lod.IMPOSTOR,
					"backdrop": backdrop,
					"buffer": TreeImpostors.buffer(entries, origin),
					"count": entries.size(),
				}
			)
		)
	return {"map": map_trees.size(), "backdrop": backdrop_trees.size(), "groups": sorted}


## How far (world units) a planted item of `species` sinks into the drawn ground at real scale.
static func sink(species: StringName, vegetation: Dictionary) -> float:
	var metres: float = (
		vegetation["scrub_sink_m"] if SCRUB_LOD_DISTANCE.has(species) else vegetation["tree_sink_m"]
	)
	return MapScale.to_units(metres)


## The impostor of a planned tree under the `true` preset (TreeImpostors.entry): from its full
## range on (always for the far backdrop, which has no full trees) to its impostor range on forest
## tiles (the canopy shell beyond) or its vanish range elsewhere.
static func _impostor_entry(
	tree: Dictionary,
	pick: Dictionary,
	transform: Transform3D,
	far_only: bool,
	on_canopy: bool,
	vegetation: Dictionary
) -> Array:
	var species: StringName = pick["species"]
	var size := model_size(species, pick["variant"])
	var height_m := VegetationRanges.species_height_m(species)
	var full := 0.0 if far_only else VegetationRanges.full_range(height_m, vegetation)
	var out := (
		VegetationRanges.impostor_range(height_m, vegetation)
		if on_canopy and has_lod2(species)
		else VegetationRanges.vanish_range(height_m, vegetation)
	)
	var s: float = tree["scale"] * VisualScale.tree_size(species, pick["variant"])
	var h: float = tree["height_scale"] * VisualScale.tree_size(species, pick["variant"])
	return TreeImpostors.entry(
		species,
		pick["variant"],
		transform.origin,
		maxf(size.x, size.z) * s,
		size.y * h,
		pick["custom"],
		full,
		out
	)


## MultiMesh buffer of TRANSFORM_3D instances with custom data (BUFFER_STRIDE floats each).
static func instance_buffer(local: Array[Transform3D], customs: Array) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(local.size() * BUFFER_STRIDE)
	for i in local.size():
		var b := local[i].basis
		var o := local[i].origin
		var custom: Color = customs[i]
		var k := i * BUFFER_STRIDE
		buffer[k] = b.x.x
		buffer[k + 1] = b.y.x
		buffer[k + 2] = b.z.x
		buffer[k + 3] = o.x
		buffer[k + 4] = b.x.y
		buffer[k + 5] = b.y.y
		buffer[k + 6] = b.z.y
		buffer[k + 7] = o.y
		buffer[k + 8] = b.x.z
		buffer[k + 9] = b.y.z
		buffer[k + 10] = b.z.z
		buffer[k + 11] = o.z
		buffer[k + 12] = custom.r
		buffer[k + 13] = custom.g
		buffer[k + 14] = custom.b
		buffer[k + 15] = custom.a
	return buffer


## Fills the lazy caches plan_chunk reads (the model heights under the `true` VisualScale preset),
## so worker threads only read them.
static func prime_sizes() -> void:
	for species: StringName in SCRUB_LOD_DISTANCE.keys() + TreeSpecies.all():
		for variant in TreeMeshes.VARIANTS:
			VisualScale.tree_size(species, variant)
			model_size(species, variant)
	TreeImpostors.prime()


## Size of a species' LOD0 model (scale 1), cached (prime_sizes() fills it on the main thread).
static func model_size(species: StringName, variant: int) -> Vector3:
	var key := "%s:%d" % [species, variant]
	if not _model_sizes.has(key):
		_model_sizes[key] = TreeMeshes.lod0(species, variant).get_aabb().size
	return _model_sizes[key]


## Adds the nodes of a planned chunk (main thread).
func build_chunk(chunk: Vector2i, plan: Dictionary) -> void:
	free_chunk(chunk)
	var nodes: Array[MultiMeshInstance3D] = []
	for group: Dictionary in plan["groups"]:
		nodes.append(_add_group(chunk, group))
	_chunk_nodes[chunk] = nodes
	_chunk_counts[chunk] = Vector2i(plan["map"], plan["backdrop"])
	_planned += plan["map"] + plan["backdrop"]
	_backdrop += plan["backdrop"]


## Drops the nodes of `chunk`.
func free_chunk(chunk: Vector2i) -> void:
	if not _chunk_nodes.has(chunk):
		return
	for node: MultiMeshInstance3D in _chunk_nodes[chunk]:
		for lod: Lod in _nodes:
			(_nodes[lod] as Array).erase(node)
		_local_transforms.erase(node)
		remove_child(node)
		node.queue_free()
	var counts: Vector2i = _chunk_counts[chunk]
	_planned -= counts.x + counts.y
	_backdrop -= counts.y
	_chunk_nodes.erase(chunk)
	_chunk_counts.erase(chunk)


## The nodes of a built chunk (none when it is not built).
func chunk_nodes(chunk: Vector2i) -> Array[MultiMeshInstance3D]:
	return _chunk_nodes.get(chunk, [] as Array[MultiMeshInstance3D])


## World transform of a planned tree: base at the planted position, scaled by the planned scale
## and VisualScale.tree_size (tree_scale(), or the species' real height under the `true`
## preset) about the base (positions stay the same).
static func tree_transform(tree: Dictionary, species := &"", variant := 0) -> Transform3D:
	var size := VisualScale.tree_size(species, variant)
	var s: float = tree["scale"] * size
	var h: float = tree["height_scale"] * size
	var basis := Basis(Vector3.UP, tree["yaw"]) * Basis.from_scale(Vector3(s, h, s))
	return Transform3D(basis, tree["position"])


static func lod_distance(species: StringName) -> float:
	return SCRUB_LOD_DISTANCE.get(species, LOD_DISTANCE)


## Whether the species gets a LOD2 node (trees yes, the small scrub keeps LOD1 to the horizon).
static func has_lod2(species: StringName) -> bool:
	return not SCRUB_LOD_DISTANCE.has(species)


static func lod_margin(species: StringName) -> float:
	return SCRUB_LOD_MARGIN if SCRUB_LOD_DISTANCE.has(species) else LOD_MARGIN


static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK_SIZE), floori(p.z / CHUNK_SIZE))


static func chunk_center(chunk: Vector2i) -> Vector3:
	return Vector3((chunk.x + 0.5) * CHUNK_SIZE, 0.0, (chunk.y + 0.5) * CHUNK_SIZE)


## Trees planned (map + backdrop) and of them on the backdrop.
func planned_count() -> int:
	return _planned


func backdrop_count() -> int:
	return _backdrop


## LOD0 (cards) nodes, LOD1 nodes (beyond LOD_DISTANCE) and the always-LOD1 far backdrop nodes.
func lod0_nodes() -> Array[MultiMeshInstance3D]:
	return _typed(_nodes[Lod.NEAR])


func lod1_nodes() -> Array[MultiMeshInstance3D]:
	return _typed(_nodes[Lod.FAR_RANGE])


func far_nodes() -> Array[MultiMeshInstance3D]:
	return _typed(_nodes[Lod.FAR_ONLY])


## LOD2 nodes (beyond LOD2_DISTANCE, trees only).
func lod2_nodes() -> Array[MultiMeshInstance3D]:
	return _typed(_nodes[Lod.DISTANT])


## Impostor nodes (`true` preset only, one per chunk and map / backdrop).
func impostor_nodes() -> Array[MultiMeshInstance3D]:
	return _typed(_nodes[Lod.IMPOSTOR])


## Instance transforms of one of this field's nodes, relative to the node (decoded from the kept
## MultiMesh buffer: the headless dummy renderer keeps no instance data).
func instance_transforms(node: MultiMeshInstance3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var buffer: PackedFloat32Array = _local_transforms.get(node, PackedFloat32Array())
	var stride := TreeImpostors.STRIDE if node.multimesh.use_colors else BUFFER_STRIDE
	for k in range(0, buffer.size(), stride):
		result.append(
			Transform3D(
				Vector3(buffer[k], buffer[k + 4], buffer[k + 8]),
				Vector3(buffer[k + 1], buffer[k + 5], buffer[k + 9]),
				Vector3(buffer[k + 2], buffer[k + 6], buffer[k + 10]),
				Vector3(buffer[k + 3], buffer[k + 7], buffer[k + 11])
			)
		)
	return result


static func instance_total(nodes: Array[MultiMeshInstance3D]) -> int:
	var total := 0
	for node in nodes:
		total += node.multimesh.instance_count
	return total


## LOD0 triangles of all instances in chunks whose centre lies within `radius` of `point` (XZ).
func lod0_triangles_within(point: Vector2, radius: float) -> int:
	var total := 0
	for node in lod0_nodes():
		# The budget radius is for the standard range; a shorter-range species is seen closer only.
		var species: StringName = node.get_meta(&"species", &"")
		var reach := (
			radius - LOD_DISTANCE - LOD_MARGIN + lod_distance(species) + lod_margin(species)
		)
		if Vector2(node.position.x, node.position.z).distance_to(point) <= reach:
			total += node.multimesh.instance_count * TreeMeshes.triangle_count(node.multimesh.mesh)
	return total


func _typed(nodes: Array) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for node: MultiMeshInstance3D in nodes:
		result.append(node)
	return result


static func _outside_distance(rect: Rect2, p: Vector2) -> float:
	return p.distance_to(p.clamp(rect.position, rect.end))


func _add_group(chunk: Vector2i, group: Dictionary) -> MultiMeshInstance3D:
	var species: StringName = group["species"]
	var lod: Lod = group["lod"]
	var count: int = group["count"]
	if lod == Lod.IMPOSTOR:
		return _add_impostors(chunk, group)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	match lod:
		Lod.NEAR:
			multi.mesh = TreeMeshes.lod0(species, group["variant"])
		Lod.DISTANT:
			multi.mesh = TreeMeshes.lod2(species)
		_:
			multi.mesh = TreeMeshes.lod1(species)
	multi.instance_count = count
	multi.buffer = group["buffer"]
	var instance := MultiMeshInstance3D.new()
	instance.name = "Trees_" + String(group["key"])
	instance.multimesh = multi
	instance.material_override = _material(species, lod)
	instance.position = chunk_center(chunk)
	instance.set_meta(&"species", species)
	instance.set_meta(&"backdrop", group["backdrop"])
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if species in NO_SHADOW_SPECIES or group["backdrop"]
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)
	var bands := lod_bands(species, lod)
	if lod == Lod.NEAR and VisualScale.is_true_size():
		bands = true_bands(species)
	var band_in: Vector2 = bands["in"]
	var band_out: Vector2 = bands["out"]
	if band_in != NO_LOD_IN:
		instance.visibility_range_begin = maxf(band_in.x - RANGE_SLACK, 0.0)
	if band_out != NO_LOD_OUT:
		instance.visibility_range_end = band_out.y + RANGE_SLACK
	add_child(instance)
	(_nodes[lod] as Array).append(instance)
	_local_transforms[instance] = group["buffer"]
	return instance


## The impostor node of a chunk (`true` preset): every species in one MultiMesh, no shadow.
func _add_impostors(chunk: Vector2i, group: Dictionary) -> MultiMeshInstance3D:
	if _impostor_material == null:
		_impostor_material = TreeImpostors.material(LookPreset.vegetation()["band_share"])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Trees_" + String(group["key"])
	instance.multimesh = TreeImpostors.multimesh(group["buffer"])
	instance.material_override = _impostor_material
	instance.position = chunk_center(chunk)
	instance.set_meta(&"species", group["species"])
	instance.set_meta(&"backdrop", group["backdrop"])
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	(_nodes[Lod.IMPOSTOR] as Array).append(instance)
	_local_transforms[instance] = group["buffer"]
	return instance


## LOD0 bands of a species under the `true` preset: always in, out across its full range
## (VegetationRanges, metres scaled by the species' real height).
static func true_bands(species: StringName) -> Dictionary:
	var height_m := VegetationRanges.species_height_m(species)
	return {
		"in": NO_LOD_IN,
		"out": VegetationRanges.band(VegetationRanges.full_range(height_m)),
	}


## The shader's switch bands of a species' LOD: {in, out}, each (begin, end) as the distance of a
## tree's base from the camera (a tree switches at its own point of the band); NO_LOD_IN /
## NO_LOD_OUT where the LOD has no such limit.
static func lod_bands(species: StringName, lod: Lod) -> Dictionary:
	var near := Vector2(
		lod_distance(species) - lod_margin(species), lod_distance(species) + lod_margin(species)
	)
	var far := Vector2(LOD2_DISTANCE - LOD2_MARGIN, LOD2_DISTANCE + LOD2_MARGIN)
	match lod:
		Lod.NEAR:
			return {"in": NO_LOD_IN, "out": near}
		Lod.FAR_RANGE:
			return {"in": near, "out": far if has_lod2(species) else NO_LOD_OUT}
		Lod.DISTANT:
			return {"in": far, "out": NO_LOD_OUT}
	return {"in": NO_LOD_IN, "out": NO_LOD_OUT}


func _material(species: StringName, lod: Lod) -> ShaderMaterial:
	var key := "%s_%d" % [species, lod]
	if not _materials.has(key):
		_materials[key] = new_material(species, lod)
	return _materials[key]


## A new material of a species' LOD (the `true` preset's bands for LOD0 under it).
static func new_material(species: StringName, lod: Lod) -> ShaderMaterial:
	var solid := lod != Lod.NEAR
	var conifer := TreeSpecies.is_conifer(species)
	var texture := leaf_texture(conifer)
	var material := ShaderMaterial.new()
	material.shader = SOLID_SHADER if solid else SHADER
	material.set_shader_parameter(&"leaf_texture", texture)
	material.set_shader_parameter(
		&"leaf_color", LookPreset.leaf_color(species, LEAF_COLORS[species])
	)
	material.set_shader_parameter(&"bark_color", BARK_COLORS[species])
	material.set_shader_parameter(&"birch_bark", species == &"birch")
	material.set_shader_parameter(
		&"solid_luminance", mean_leaf_luminance(conifer) * SOLID_LUMINANCE_FACTOR
	)
	material.set_shader_parameter(&"tree_height", TreeMeshes.TREE_HEIGHT)
	var bands := lod_bands(species, lod)
	if lod == Lod.NEAR and VisualScale.is_true_size():
		bands = true_bands(species)
	material.set_shader_parameter(&"lod_in", bands["in"])
	material.set_shader_parameter(&"lod_out", bands["out"])
	return material


## The cached card texture: needles for conifers, a leaf cluster otherwise – many small twigs /
## leaves under the `true` VisualScale preset, where a card is metres wide (its mean linear
## luminance is kept for the LOD1 crown).
static func leaf_texture(conifer: bool) -> ImageTexture:
	var key := _leaf_key(conifer)
	if not _textures.has(key):
		var image: Image
		if conifer and VisualScale.is_true_size():
			image = LeafTexture.small_needles(LEAF_TEXTURE_SIZE, NEEDLE_SEED)
		elif conifer:
			image = LeafTexture.needles(LEAF_TEXTURE_SIZE, NEEDLE_SEED)
		elif VisualScale.is_true_size():
			image = LeafTexture.small_leaves(LEAF_TEXTURE_SIZE, CLUSTER_SEED)
		else:
			image = LeafTexture.cluster(LEAF_TEXTURE_SIZE, CLUSTER_SEED)
		_textures[key] = ImageTexture.create_from_image(image)
		_textures[key + "_lum"] = _mean_luminance(image)
	return _textures[key]


## Mean linear luminance of the card texture (the solid crowns' and impostors' albedo factor).
static func mean_leaf_luminance(conifer: bool) -> float:
	leaf_texture(conifer)
	return _textures[_leaf_key(conifer) + "_lum"]


static func _leaf_key(conifer: bool) -> String:
	if conifer:
		return "small_needles" if VisualScale.is_true_size() else "needles"
	return "small_leaves" if VisualScale.is_true_size() else "cluster"


static func _mean_luminance(image: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y)
			if c.a > 0.5:
				total += c.srgb_to_linear().r
				count += 1
	return total / maxi(count, 1)
