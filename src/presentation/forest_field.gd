class_name ForestField
extends Node3D
## The dense real-scale forest (TASK-135, ADR 0026; only under the `true` VisualScale preset): the
## ForestFill trees (with ScatterPlanner's planned trees ~2 000 per forest hex) as two chunk
## layers of MapView.
##
## - "forest_full" (FULL_CHUNK chunks, on MapView's camera-centred ChunkManager): full 3D trees
##   (TreeMeshes LOD0, one MultiMesh per species and variant), each drawn up to its full range
##   (VegetationRanges, scaled by the species' height) – the same per-tree hand-over band as
##   TreeField.
## - "forest" (IMPOSTOR_CHUNK chunks, on the camera-target ChunkManager): one impostor MultiMesh
##   per chunk (TreeImpostors) from the full range to the impostor range, where the canopy shell
##   (ForestShell) takes over.
##
## The full-tree budget (update(), every frame): the built full chunks within the full range are
## taken nearest first while their tree count stays within LookPreset.vegetation()
## "full_tree_cap" (VegetationRanges.budget_reach); the rest is hidden and the reach caps the
## LOD0 materials' `lod_cap` and the impostors' `full_reach`, so the dropped trees – the farthest
## – are drawn as impostors instead, tree by tree, with no gap and no double draw. A full chunk
## the camera manager has not built yet (or never builds: layer off) caps the reach the same way.

## Which ground a plan puts its trees on: the drawn near surface (full trees), the surface at the
## point (impostors near the target) or the drawn lattice (impostors beyond the near terrain).
enum Ground { NEAR, MID, FAR }

const FULL_LAYER := &"forest_full"
const IMPOSTOR_LAYER := &"forest"
const FULL_CHUNK := 1.0
const IMPOSTOR_CHUNK := 2.0
const NO_CAP := 1.0e9
## Impostor chunks beyond this distance (m) from the camera target stand on the lattice height,
## sunk by FAR_SINK_M: the near terrain (433 m ring, built to 650 m) is not drawn there.
const FAR_GROUND_REACH_M := 900.0
const FAR_SINK_M := 1.5
## Far impostor chunks plan every other tree (ForestFill `thin`), each crown this much wider.
const FAR_CROWN_WIDEN := 1.4

var _grid: HexGrid
var _ground := Callable()
## The drawn lattice height (thread-safe, ~10x cheaper than the near surface): where the near
## terrain is not drawn (far impostor chunks) the trees stand on it.
var _far_ground := Callable()
## The surface height at the point (impostors near the target, ~1/3 of `_ground`'s cost).
var _mid_ground := Callable()
## The camera target (world xz) the near terrain is centred on: impostor chunks farther from it
## than FAR_GROUND_REACH_M plan with `_far_ground`. INF: always the near surface.
var _plan_target := Vector2.INF
var _parcels: ParcelMap
var _seed := 0
var _area := Rect2()
var _values: Dictionary = {}
## The largest full band end of any species (world units): chunks farther away hold no full tree.
var _max_full := 0.0
var _max_impostor := 0.0
## Vector2i full chunk -> {"nodes": Array[MultiMeshInstance3D], "count": int, "low": float,
## "high": float (lowest / highest tree base)} – also for chunks without trees.
var _full: Dictionary = {}
## Vector2i impostor chunk -> MultiMeshInstance3D (only chunks with trees).
var _impostors: Dictionary = {}
## Node -> its MultiMesh buffer (tests: the headless renderer keeps no instance data).
var _buffers: Dictionary = {}
var _full_materials: Dictionary = {}
var _impostor_material: ShaderMaterial
var _reach := INF
var _applied_cap := -1.0
var _camera := Vector3.INF
var _visible_full := 0
var _burns: Array[Vector3] = []
## Built impostor chunks as a mask over the area (one pixel per chunk, 255 = built) for the canopy
## shell: over a chunk not built yet the shell stays drawn at any distance, so a forest whose
## impostors are still being planned shows as canopy, never as bare ground.
var _coverage: Image
var _coverage_texture: ImageTexture
var _coverage_dirty := false
var _coverage_origin := Vector2i.ZERO


## Prepares the field for a map: `ground` is Callable(x, z) -> float (the drawn near surface,
## thread-safe), `area` the rectangle the forest may cover (the playable mesh).
func setup(
	grid: HexGrid,
	ground: Callable,
	seed_value: int,
	area: Rect2,
	parcels: ParcelMap = null,
	far_ground: Callable = Callable(),
	mid_ground: Callable = Callable()
) -> void:
	clear()
	_grid = grid
	_ground = ground
	_far_ground = far_ground if far_ground.is_valid() else ground
	_mid_ground = mid_ground if mid_ground.is_valid() else ground
	_seed = seed_value
	_area = area
	_parcels = parcels
	_values = LookPreset.vegetation()
	_max_full = 0.0
	_max_impostor = 0.0
	for species in TreeSpecies.all():
		var height_m := VegetationRanges.species_height_m(species)
		_max_full = maxf(
			_max_full, VegetationRanges.band(VegetationRanges.full_range(height_m, _values)).y
		)
		_max_impostor = maxf(
			_max_impostor,
			VegetationRanges.band(VegetationRanges.impostor_range(height_m, _values)).y
		)
		var material := TreeField.new_material(species, TreeField.Lod.NEAR)
		material.set_shader_parameter(&"lod_out", TreeField.true_bands(species)["out"])
		_full_materials[species] = material
	_impostor_material = TreeImpostors.material(_values["band_share"])
	_coverage_origin = Vector2i(
		floori(area.position.x / IMPOSTOR_CHUNK), floori(area.position.y / IMPOSTOR_CHUNK)
	)
	var last := Vector2i(floori(area.end.x / IMPOSTOR_CHUNK), floori(area.end.y / IMPOSTOR_CHUNK))
	var cells := last - _coverage_origin + Vector2i.ONE
	_coverage = Image.create(cells.x, cells.y, false, Image.FORMAT_L8)
	_coverage_texture = ImageTexture.create_from_image(_coverage)
	_coverage_dirty = false
	_applied_cap = -1.0
	_set_reach(INF)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_full.clear()
	_impostors.clear()
	_buffers.clear()
	_burns.clear()
	_visible_full = 0


func full_layer() -> ChunkLayer:
	var result := ChunkLayer.new(FULL_LAYER, FULL_CHUNK, _area, _build_full, _free_full, plan_full)
	result.prepare = prepare
	return result


func impostor_layer() -> ChunkLayer:
	var result := ChunkLayer.new(
		IMPOSTOR_LAYER, IMPOSTOR_CHUNK, _area, _build_impostors, _free_impostors, plan_impostors
	)
	result.prepare = prepare
	return result


## Main thread, before plans run on the worker threads: fills the lazy caches they read.
func prepare() -> void:
	TreeField.prime_sizes()
	FeatureRibbonPlanner.is_clear(_grid, 0.0, 0.0)


## The largest full band end (x) and impostor band end (y) of any species (world units).
func max_ranges() -> Vector2:
	return Vector2(_max_full, _max_impostor)


## The fill trees of a rectangle with their species pick and world transform: [[tree, pick,
## Transform3D]]. Pure.
func _trees_in(rect: Rect2, ground_kind := Ground.NEAR) -> Array:
	var result: Array = []
	var sink := TreeField.sink(&"pine", _values)
	var ground := _ground
	if ground_kind == Ground.MID:
		ground = _mid_ground
	elif ground_kind == Ground.FAR:
		# The lattice is coarser than the near surface: sink the bases so none float.
		ground = _far_ground
		sink += MapScale.to_units(FAR_SINK_M)
	var thin := ground_kind == Ground.FAR
	for tree: Dictionary in ForestFill.plan_rect(
		_grid, ground, _seed, rect, _parcels, _values, thin
	):
		var pick := TreeSpecies.pick(tree)
		result.append([tree, pick, fill_transform(tree, pick, sink, _values)])
	return result


## World transform of a fill tree: its real size (VisualScale.tree_size), the crown narrowed to
## forest_crown_width_m, the base sunk by `sink` into the ground at its position.
static func fill_transform(
	tree: Dictionary, pick: Dictionary, sink: float, values: Dictionary
) -> Transform3D:
	var species: StringName = pick["species"]
	var variant: int = pick["variant"]
	var size := VisualScale.tree_size(species, variant)
	var model := TreeField.model_size(species, variant)
	var width := maxf(model.x, model.z) * size
	var narrow := clampf(
		MapScale.to_units(float(values["forest_crown_width_m"])) / maxf(width, 1.0e-6), 0.2, 1.0
	)
	var s: float = tree["scale"] * size
	var h: float = tree["height_scale"] * size
	var basis := (
		Basis(Vector3.UP, tree["yaw"]) * Basis.from_scale(Vector3(s * narrow, h, s * narrow))
	)
	var p: Vector3 = tree["position"]
	return Transform3D(basis, Vector3(p.x, p.y - sink, p.z))


static func _chunk_rect(chunk: Vector2i, size: float) -> Rect2:
	return Rect2(Vector2(chunk) * size, Vector2.ONE * size)


static func _chunk_origin(rect: Rect2, y: float) -> Vector3:
	var c := rect.get_center()
	return Vector3(c.x, y, c.y)


## Full trees of a chunk: {"count", "low", "high", "groups": [{species, variant, buffer, count}]}.
## Pure.
func plan_full(chunk: Vector2i) -> Dictionary:
	var rect := _chunk_rect(chunk, FULL_CHUNK)
	var trees := _trees_in(rect)
	var low := INF
	var high := -INF
	for entry: Array in trees:
		var y: float = (entry[2] as Transform3D).origin.y
		low = minf(low, y)
		high = maxf(high, y)
	var origin := _chunk_origin(rect, 0.0 if trees.is_empty() else 0.5 * (low + high))
	var groups: Dictionary = {}
	for entry: Array in trees:
		var pick: Dictionary = entry[1]
		var key := "%s_%d" % [pick["species"], pick["variant"]]
		var t: Transform3D = entry[2]
		var group: Dictionary = (
			groups
			. get_or_add(
				key,
				{
					"species": pick["species"],
					"variant": pick["variant"],
					"local": [] as Array[Transform3D],
					"customs": [],
				}
			)
		)
		(group["local"] as Array[Transform3D]).append(Transform3D(t.basis, t.origin - origin))
		(group["customs"] as Array).append(pick["custom"])
	var keys := groups.keys()
	keys.sort()
	var sorted: Array = []
	for key: String in keys:
		var group: Dictionary = groups[key]
		(
			sorted
			. append(
				{
					"species": group["species"],
					"variant": group["variant"],
					"count": (group["local"] as Array).size(),
					"buffer": TreeField.instance_buffer(group["local"], group["customs"]),
				}
			)
		)
	return {"count": trees.size(), "low": low, "high": high, "origin": origin, "groups": sorted}


func _build_full(chunk: Vector2i, plan: Dictionary) -> void:
	_free_full(chunk)
	var nodes: Array[MultiMeshInstance3D] = []
	for group: Dictionary in plan["groups"]:
		var species: StringName = group["species"]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = TreeMeshes.lod0(species, group["variant"])
		multi.instance_count = group["count"]
		multi.buffer = group["buffer"]
		var node := MultiMeshInstance3D.new()
		node.name = "Forest_%d_%d_%s_%d" % [chunk.x, chunk.y, species, group["variant"]]
		node.multimesh = multi
		node.material_override = _full_materials[species]
		node.position = plan["origin"]
		node.set_meta(&"species", species)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.visible = false
		add_child(node)
		_buffers[node] = group["buffer"]
		nodes.append(node)
	_full[chunk] = {
		"nodes": nodes, "count": plan["count"], "low": plan["low"], "high": plan["high"]
	}
	_burn_nodes(nodes)
	if _camera != Vector3.INF:
		update(_camera)


func _free_full(chunk: Vector2i) -> void:
	var entry: Dictionary = _full.get(chunk, {})
	if entry.is_empty():
		return
	for node: MultiMeshInstance3D in entry["nodes"]:
		_buffers.erase(node)
		remove_child(node)
		node.queue_free()
	_full.erase(chunk)


## Whether `rect` lies beyond the near terrain around the camera target (so its trees stand on
## the cheaper lattice height).
func _is_far(rect: Rect2) -> bool:
	if not _plan_target.is_finite():
		return false
	var d := _plan_target.distance_to(_plan_target.clamp(rect.position, rect.end))
	return d > MapScale.to_units(FAR_GROUND_REACH_M)


## The camera target for plan_impostors' choice of ground (main thread, every frame).
func set_plan_target(target: Vector2) -> void:
	_plan_target = target


## The impostors of a chunk: {"count", "origin", "buffer"}. Pure.
func plan_impostors(chunk: Vector2i) -> Dictionary:
	var rect := _chunk_rect(chunk, IMPOSTOR_CHUNK)
	var far := _is_far(rect)
	var kind := Ground.FAR if far else Ground.MID
	var ground := _far_ground if far else _mid_ground
	var sink := TreeField.sink(&"pine", _values)
	if far:
		sink += MapScale.to_units(FAR_SINK_M)
	var widen := FAR_CROWN_WIDEN if far else 1.0
	var crown := MapScale.to_units(float(_values["forest_crown_width_m"]))
	# Per species: [full range, impostor range, per variant [crown width at scale 1 (narrowed as
	# fill_transform does), height at scale 1]] – the same numbers fill_transform works with.
	var species_data: Dictionary = {}
	var entries: Array = []
	var total_y := 0.0
	var fill := ForestFill.plan_rect(
		_grid, ground, _seed, rect, _parcels, _values, kind == Ground.FAR
	)
	for tree: Dictionary in fill:
		var pick := TreeSpecies.pick(tree)
		var species: StringName = pick["species"]
		var variant: int = pick["variant"]
		var data: Array = species_data.get(species, [])
		if data.is_empty():
			data = _impostor_species_data(species, crown)
			species_data[species] = data
		var sizes: Vector2 = (data[2] as Array)[variant]
		var p: Vector3 = tree["position"]
		var origin := Vector3(p.x, p.y - sink, p.z)
		var width: float = sizes.x * float(tree["scale"]) * widen
		var height: float = sizes.y * float(tree["height_scale"])
		entries.append(
			TreeImpostors.entry(
				species, variant, origin, width, height, pick["custom"], data[0], data[1]
			)
		)
		total_y += origin.y
	var origin := _chunk_origin(rect, total_y / maxi(fill.size(), 1))
	return {
		"count": entries.size(),
		"origin": origin,
		"buffer": TreeImpostors.buffer(entries, origin),
	}


## [full range, impostor range, per variant Vector2(crown width, height) at tree scale 1] of a
## species for plan_impostors (`crown`: forest_crown_width_m in world units).
func _impostor_species_data(species: StringName, crown: float) -> Array:
	var height_m := VegetationRanges.species_height_m(species)
	var sizes: Array = []
	for variant in TreeMeshes.VARIANTS:
		var size := VisualScale.tree_size(species, variant)
		var model := TreeField.model_size(species, variant)
		var natural := maxf(model.x, model.z) * size
		sizes.append(Vector2(minf(natural, crown), model.y * size))
	return [
		VegetationRanges.full_range(height_m, _values),
		VegetationRanges.impostor_range(height_m, _values),
		sizes,
	]


func _build_impostors(chunk: Vector2i, plan: Dictionary) -> void:
	_free_impostors(chunk)
	_set_covered(chunk, true)
	if plan["count"] == 0:
		return
	var node := MultiMeshInstance3D.new()
	node.name = "ForestImpostors_%d_%d" % [chunk.x, chunk.y]
	node.multimesh = TreeImpostors.multimesh(plan["buffer"])
	node.material_override = _impostor_material
	node.position = plan["origin"]
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = _max_impostor + IMPOSTOR_CHUNK
	add_child(node)
	_buffers[node] = plan["buffer"]
	_impostors[chunk] = node
	_burn_nodes([node])


func _free_impostors(chunk: Vector2i) -> void:
	_set_covered(chunk, false)
	var node: MultiMeshInstance3D = _impostors.get(chunk)
	if node == null:
		return
	_buffers.erase(node)
	remove_child(node)
	node.queue_free()
	_impostors.erase(chunk)


func _set_covered(chunk: Vector2i, built: bool) -> void:
	if _coverage == null:
		return
	var p := chunk - _coverage_origin
	if p.x < 0 or p.y < 0 or p.x >= _coverage.get_width() or p.y >= _coverage.get_height():
		return
	_coverage.set_pixel(p.x, p.y, Color.WHITE if built else Color.BLACK)
	_coverage_dirty = true


## Whether the impostor chunk is built (the coverage mask the canopy shell reads).
func is_covered(chunk: Vector2i) -> bool:
	var p := chunk - _coverage_origin
	if _coverage == null or p.x < 0 or p.y < 0:
		return false
	if p.x >= _coverage.get_width() or p.y >= _coverage.get_height():
		return false
	return _coverage.get_pixel(p.x, p.y).r > 0.5


## Hands the coverage mask to the canopy shell's material (see `_coverage`).
func bind_shell(material: ShaderMaterial) -> void:
	if material == null or _coverage_texture == null:
		return
	material.set_shader_parameter(&"coverage", _coverage_texture)
	material.set_shader_parameter(&"use_coverage", 1.0)
	material.set_shader_parameter(&"coverage_origin", Vector2(_coverage_origin) * IMPOSTOR_CHUNK)
	material.set_shader_parameter(
		&"coverage_extent", Vector2(_coverage.get_size()) * IMPOSTOR_CHUNK
	)


## The full-tree budget for a camera at `camera` (world): which full chunks are drawn and from
## which distance the impostors take over (see the class comment). Main thread, every frame.
func update(camera: Vector3) -> void:
	_camera = camera
	if _grid == null:
		return
	if _coverage_dirty:
		_coverage_dirty = false
		_coverage_texture.update(_coverage)
	var cap := int(_values["full_tree_cap"])
	var entries: Array[Vector2] = []
	var distances: Dictionary = {}
	for chunk: Vector2i in _full:
		# As the 32-bit float budget_reach compares and returns (a chunk at the reach is out).
		var d := Vector2(_distance(chunk, camera), 0.0).x
		distances[chunk] = d
		if d < _max_full:
			entries.append(Vector2(d, (_full[chunk] as Dictionary)["count"]))
	var reach := minf(VegetationRanges.budget_reach(entries, cap), _unbuilt_reach(camera))
	_visible_full = 0
	for chunk: Vector2i in _full:
		var entry: Dictionary = _full[chunk]
		var on: bool = distances[chunk] < minf(reach, _max_full)
		for node: MultiMeshInstance3D in entry["nodes"]:
			node.visible = on
		if on:
			_visible_full += int(entry["count"])
	_set_reach(reach)


## The nearest distance of a full chunk within the full range that is not built (its trees
## would otherwise be drawn by neither LOD), INF if there is none.
func _unbuilt_reach(camera: Vector3) -> float:
	var result := INF
	var first := Vector2i(
		floori((camera.x - _max_full) / FULL_CHUNK), floori((camera.z - _max_full) / FULL_CHUNK)
	)
	var last := Vector2i(
		floori((camera.x + _max_full) / FULL_CHUNK), floori((camera.z + _max_full) / FULL_CHUNK)
	)
	for x in range(first.x, last.x + 1):
		for z in range(first.y, last.y + 1):
			var chunk := Vector2i(x, z)
			if _full.has(chunk) or not _chunk_rect(chunk, FULL_CHUNK).intersects(_area):
				continue
			var rect := _chunk_rect(chunk, FULL_CHUNK)
			var flat := Vector2(camera.x, camera.z)
			var d := flat.distance_to(flat.clamp(rect.position, rect.end))
			if d < _max_full:
				result = minf(result, d)
	return result


## Distance from the camera to the nearest tree base a full chunk can hold.
func _distance(chunk: Vector2i, camera: Vector3) -> float:
	var entry: Dictionary = _full[chunk]
	var rect := _chunk_rect(chunk, FULL_CHUNK)
	var flat := Vector2(camera.x, camera.z)
	var dxz := flat.distance_to(flat.clamp(rect.position, rect.end))
	if int(entry["count"]) == 0:
		return dxz
	var dy := camera.y - clampf(camera.y, entry["low"], entry["high"])
	return sqrt(dxz * dxz + dy * dy)


func _set_reach(reach: float) -> void:
	var cap := minf(reach, NO_CAP)
	_reach = reach
	if is_equal_approx(cap, _applied_cap):
		return
	_applied_cap = cap
	for material: ShaderMaterial in _full_materials.values():
		material.set_shader_parameter(&"lod_cap", cap)
	if _impostor_material != null:
		_impostor_material.set_shader_parameter(&"full_reach", cap)


## The budget's reach of the last update() (INF: every full chunk in range is drawn).
func reach() -> float:
	return _reach


## Full trees submitted by the last update() (the visible full chunks' instances).
func visible_full_count() -> int:
	return _visible_full


## Full nodes of the built chunks (visible or not).
func full_nodes() -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for entry: Dictionary in _full.values():
		result.append_array(entry["nodes"])
	return result


func impostor_nodes() -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	for node: MultiMeshInstance3D in _impostors.values():
		result.append(node)
	return result


## World positions of the trees of one of this field's nodes (tree bases).
func instance_positions(node: MultiMeshInstance3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	var buffer: PackedFloat32Array = _buffers.get(node, PackedFloat32Array())
	var stride := TreeImpostors.STRIDE if node.multimesh.use_colors else TreeField.BUFFER_STRIDE
	for k in range(0, buffer.size(), stride):
		result.append(node.position + Vector3(buffer[k + 3], buffer[k + 7], buffer[k + 11]))
	return result


## Remembers a burnt circle (BurntGround) and burns the built nodes it touches.
func burn(center: Vector2, radius: float) -> void:
	_burns.append(Vector3(center.x, radius, center.y))
	_burn_nodes(get_children())


func _burn_nodes(nodes: Array) -> void:
	for burn_circle in _burns:
		BurntGround.burn_instances(nodes, Vector2(burn_circle.x, burn_circle.z), burn_circle.y)
