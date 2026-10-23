class_name TreeField
extends Node3D
## The trees of a MapView (TASK-060): the planned trees (ScatterPlanner, map and backdrop) are
## grouped into CHUNK_SIZE x CHUNK_SIZE world-unit chunks; each chunk gets one
## MultiMeshInstance3D per species x variant x LOD that has instances, with its origin at the
## chunk centre (visibility ranges measure from the node origin, so whole chunks switch).
## LOD0 (TreeMeshes.lod0: bark + leaf cards) is drawn up to LOD_DISTANCE from the camera, LOD1
## (TreeMeshes.lod1: bark + solid crown) from there on; both fade over LOD_MARGIN
## (VISIBILITY_RANGE_FADE_SELF) and cast shadows (the cards' shadows are alpha-scissored).
## Backdrop trees farther than BACKDROP_LOD0_REACH outside the playable tiles get only a
## "far" node with the LOD1 mesh and no range, which keeps the LOD0 triangles within the budget
## (LOD0_TRIANGLE_BUDGET within BUDGET_RADIUS of any playable tile centre).
## Species, variant and per-instance colour / wind phase come from TreeSpecies.pick.

enum Lod { NEAR, FAR_RANGE, FAR_ONLY }

const CHUNK_SIZE := 8.0
const LOD_DISTANCE := 30.0
const LOD_MARGIN := 4.0
## LOD_DISTANCE + LOD_MARGIN + CameraMath.MIN_DISTANCE: the worst case at full zoom-in.
const BUDGET_RADIUS := 41.0
const LOD0_TRIANGLE_BUDGET := 1100000
const BACKDROP_LOD0_REACH := 14.0
const LEAF_TEXTURE_SIZE := 128
## Low ground cover: no shadow casting.
const UNDERGROWTH := &"undergrowth"
## Scrub is small: its LOD0 range is shorter (and it therefore costs less of the budget).
const SCRUB_LOD_DISTANCE := {&"shrub": 22.0, &"undergrowth": 12.0}
const SCRUB_LOD_MARGIN := 2.0
const CLUSTER_SEED := 11
const NEEDLE_SEED := 23
const SHADER := preload("res://assets/shaders/foliage.gdshader")
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

static var _textures: Dictionary = {}

var _planned := 0
var _backdrop := 0
var _materials: Dictionary = {}
var _nodes: Dictionary = {Lod.NEAR: [], Lod.FAR_RANGE: [], Lod.FAR_ONLY: []}
## Node -> its instance transforms relative to the node (the headless dummy renderer keeps no
## MultiMesh instance data, so tests and statistics read them here).
var _local_transforms: Dictionary = {}


## Builds the chunk nodes for the map trees and the backdrop trees (ScatterPlanner tree
## dictionaries). `playable` is the rectangle of the playable tiles (XZ).
func setup(map_trees: Array, backdrop_trees: Array, playable: Rect2) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_nodes = {Lod.NEAR: [], Lod.FAR_RANGE: [], Lod.FAR_ONLY: []}
	_local_transforms.clear()
	_planned = map_trees.size() + backdrop_trees.size()
	_backdrop = backdrop_trees.size()
	if _planned == 0:
		return
	# group key -> {chunk, species, variant, lod, transforms, customs}
	var groups: Dictionary = {}
	for i in _planned:
		var backdrop := i >= map_trees.size()
		var tree: Dictionary = backdrop_trees[i - map_trees.size()] if backdrop else map_trees[i]
		var pick := TreeSpecies.pick(tree)
		var transform := tree_transform(tree)
		var p: Vector3 = tree["position"]
		var chunk := chunk_of(p)
		var far_only := (
			backdrop and _outside_distance(playable, Vector2(p.x, p.z)) > BACKDROP_LOD0_REACH
		)
		var lods: Array[Lod] = [Lod.NEAR, Lod.FAR_RANGE]
		if far_only:
			lods = [Lod.FAR_ONLY]
		for lod in lods:
			var variant: int = pick["variant"] if lod == Lod.NEAR else 0
			var key := "%d_%d_%s_%d_%d" % [chunk.x, chunk.y, pick["species"], variant, lod]
			if not groups.has(key):
				groups[key] = {
					"chunk": chunk,
					"species": pick["species"],
					"variant": variant,
					"lod": lod,
					"transforms": [],
					"customs": [],
				}
			(groups[key]["transforms"] as Array).append(transform)
			(groups[key]["customs"] as Array).append(pick["custom"])
	var keys := groups.keys()
	keys.sort()
	for key: String in keys:
		_add_group(key, groups[key])


## World transform of a planned tree: base at the planted position, scaled by the planned scale
## and VisualScale.tree_scale() about the base (positions stay the same).
static func tree_transform(tree: Dictionary) -> Transform3D:
	var size := VisualScale.tree_scale()
	var s: float = tree["scale"] * size
	var h: float = tree["height_scale"] * size
	var basis := Basis(Vector3.UP, tree["yaw"]) * Basis.from_scale(Vector3(s, h, s))
	return Transform3D(basis, tree["position"])


static func lod_distance(species: StringName) -> float:
	return SCRUB_LOD_DISTANCE.get(species, LOD_DISTANCE)


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


## Instance transforms of one of this field's nodes, relative to the node.
func instance_transforms(node: MultiMeshInstance3D) -> Array[Transform3D]:
	return _local_transforms.get(node, [] as Array[Transform3D])


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


func _add_group(key: String, group: Dictionary) -> void:
	var species: StringName = group["species"]
	var lod: Lod = group["lod"]
	var chunk: Vector2i = group["chunk"]
	var origin := chunk_center(chunk)
	var transforms: Array = group["transforms"]
	var customs: Array = group["customs"]
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = (
		TreeMeshes.lod0(species, group["variant"]) if lod == Lod.NEAR else TreeMeshes.lod1(species)
	)
	multi.instance_count = transforms.size()
	var local: Array[Transform3D] = []
	for i in transforms.size():
		var t: Transform3D = transforms[i]
		local.append(Transform3D(t.basis, t.origin - origin))
		multi.set_instance_transform(i, local[i])
		multi.set_instance_custom_data(i, customs[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Trees_" + key
	instance.multimesh = multi
	instance.material_override = _material(species, lod != Lod.NEAR)
	instance.position = origin
	instance.set_meta(&"species", species)
	var distance := lod_distance(species)
	var margin := lod_margin(species)
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if species == UNDERGROWTH
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)
	match lod:
		Lod.NEAR:
			instance.visibility_range_end = distance
			instance.visibility_range_end_margin = margin
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		Lod.FAR_RANGE:
			instance.visibility_range_begin = distance
			instance.visibility_range_begin_margin = margin
			instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(instance)
	(_nodes[lod] as Array).append(instance)
	_local_transforms[instance] = local


func _material(species: StringName, solid: bool) -> ShaderMaterial:
	var key := "%s_%s" % [species, solid]
	if _materials.has(key):
		return _materials[key]
	var conifer := TreeSpecies.is_conifer(species)
	var texture := leaf_texture(conifer)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"leaf_texture", texture)
	material.set_shader_parameter(&"leaf_color", LEAF_COLORS[species])
	material.set_shader_parameter(&"bark_color", BARK_COLORS[species])
	material.set_shader_parameter(&"birch_bark", species == &"birch")
	material.set_shader_parameter(&"solid_crown", solid)
	material.set_shader_parameter(
		&"solid_luminance", _textures["%s_lum" % conifer] * SOLID_LUMINANCE_FACTOR
	)
	material.set_shader_parameter(&"tree_height", TreeMeshes.TREE_HEIGHT)
	_materials[key] = material
	return material


## The cached card texture: needles for conifers, a leaf cluster otherwise (its mean linear
## luminance is kept for the LOD1 crown).
static func leaf_texture(conifer: bool) -> ImageTexture:
	var key := "%s" % conifer
	if not _textures.has(key):
		var image := (
			LeafTexture.needles(LEAF_TEXTURE_SIZE, NEEDLE_SEED)
			if conifer
			else LeafTexture.cluster(LEAF_TEXTURE_SIZE, CLUSTER_SEED)
		)
		_textures[key] = ImageTexture.create_from_image(image)
		_textures["%s_lum" % conifer] = _mean_luminance(image)
	return _textures[key]


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
