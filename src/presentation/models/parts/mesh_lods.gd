class_name MeshLods
extends RefCounted
## Levels of detail for the procedural unit models (ADR 0023): `apply(root)` swaps the mesh of
## every MeshInstance3D under a built model for the same geometry, indexed, with coarser levels
## the renderer picks per instance when their error stays under a pixel (colour and shadow passes
## alike). Model files need no LOD code.
## The levels are made for kit geometry – one mesh is hundreds of separate closed primitives
## (chamfered boxes, rods, lathes) with hard edges, which Godot's own generator
## (ImporterMesh.generate_lods) leaves almost untouched. For each error of LEVEL_ERRORS (model
## units, 1 = 10 m):
## - vertices are welded by position alone, so every primitive is a closed shape, and simplified
##   within the error (chamfers and bevel rings collapse first);
## - primitives smaller than PRUNE_FACTOR errors (bolts, handles – about a pixel when the level
##   shows) are left out;
## - every corner takes the original vertex at its position whose normal fits the new face best,
##   so the levels share the full mesh's vertex buffer and its colour masks; a primitive the
##   simplifier broke (a thin plate folded through its thickness) keeps its finer triangles.

## Smaller meshes are left alone (nothing to gain).
const MIN_TRIANGLES := 64
## Allowed error of the generated levels in model units (1 unit = 10 m): 3 cm .. 1 m.
const LEVEL_ERRORS: Array[float] = [0.003, 0.006, 0.012, 0.025, 0.05, 0.1]
## Error (model units) allowed in the default battle view, where a pixel covers ~15 cm of a
## model: the levels are compared by what they draw there.
const REFERENCE_ERROR := 0.0147
## Vertices at one position whose normals differ by less than this are welded by the engine's
## generator.
const NORMAL_MERGE_ANGLE := 60.0
## A level shows once its error is at most this many pixels (the renderer switches at one pixel
## of the stored error, which is the real one divided by this): half a pixel keeps silhouettes
## and the baked vertex shading steady, and leaves the full mesh for close-ups.
const ERROR_PIXELS := 0.5
## A primitive whose longest side is below this many errors (1.25 px when the level shows) is
## dropped from a level.
const PRUNE_FACTOR := 2.5
## A level is kept when it has at most this share of the previous level's triangles.
const MIN_GAIN := 0.8
## A simplified face needs a vertex normal within ~75 degrees of its own at every corner.
const MIN_FIT := 0.25
## Share of a simplified primitive's area that may be such unfitting faces before it counts as
## broken and keeps its finer triangles.
const MAX_BAD_AREA := 0.05
## Positions closer than this (mesh units) are one point.
const WELD := 1e-5
## Bump when the generator changes, so stored levels are made again.
const CACHE_VERSION := 1
## Stored meshes above which the cache file starts over (old geometry is never looked up again).
const MAX_STORED := 3000
## Mesh metadata: the number of generated levels below the full mesh (tests, tools).
const META_LOD_COUNT := &"lod_count"
## Mesh metadata: the generated levels as [error in mesh units, triangles] pairs, finest first
## (PackedFloat32Array; summed over the surfaces of a level). See `triangles_at`.
const META_LOD_LEVELS := &"lod_levels"

## Folder of the level cache on disk; "" switches it off (the tests). Generating the levels of a
## model takes 0.3-0.6 s, reading them back a few ms: keyed by the mesh's geometry, so a changed
## model is simply generated again.
static var cache_dir := "user://cache"
static var _cache: Dictionary = {}  # source mesh instance id -> Mesh
static var _stored: Dictionary = {}  # geometry key -> [[arrays, lods] per surface]
static var _stored_read := false
static var _dirty := false
static var _fit_dot := 1.0


## Replaces the mesh of every MeshInstance3D under `root` (inclusive) by `with_lods` of it;
## `root` is a model at scale 1 (model units), the instances' own scale is taken into account.
static func apply(root: Node, to_model := Basis.IDENTITY) -> void:
	var spatial := root as Node3D
	var basis := to_model * spatial.basis if spatial != null else to_model
	var instance := root as MeshInstance3D
	if instance != null and instance.mesh != null:
		var scale := basis.get_scale().abs()
		instance.mesh = with_lods(instance.mesh, maxf(scale.x, maxf(scale.y, scale.z)))
	for child in root.get_children():
		apply(child, basis)


## `mesh` with indexed surfaces and generated levels (materials and surface names kept); `mesh`
## itself when it is too small, not made of triangles or already processed. `scale`: model units
## per mesh unit (the scale of the instance inside its model).
static func with_lods(mesh: Mesh, scale := 1.0) -> Mesh:
	var id := mesh.get_instance_id()
	if _cache.has(id):
		return _cache[id]
	if mesh.has_meta(META_LOD_COUNT):
		return mesh
	var result := mesh
	if mesh is ArrayMesh and _triangles(mesh as ArrayMesh) >= MIN_TRIANGLES:
		result = _build(mesh as ArrayMesh, maxf(scale, 1e-6))
	_cache[id] = result
	return result


## Generated levels of a mesh returned by `with_lods` (0 for an untouched mesh).
static func lod_count(mesh: Mesh) -> int:
	return mesh.get_meta(META_LOD_COUNT, 0)


## Triangles of `mesh` at full detail (all surfaces).
static func triangles(mesh: Mesh) -> int:
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return mesh.get_faces().size() / 3
	var total := 0
	for surface in array_mesh.get_surface_count():
		var indices := array_mesh.surface_get_array_index_len(surface)
		total += (indices if indices > 0 else array_mesh.surface_get_array_len(surface)) / 3
	return total


## Triangles the renderer draws of `mesh` when an error of `max_error` (mesh units) is allowed:
## the coarsest generated level whose error stays within it, else the full mesh. One pixel of
## error at pixel size p (world units) and instance scale s is `max_error` = p / s.
static func triangles_at(mesh: Mesh, max_error: float) -> int:
	var levels: PackedFloat32Array = mesh.get_meta(META_LOD_LEVELS, PackedFloat32Array())
	var result := triangles(mesh)
	for i in range(0, levels.size(), 2):
		if levels[i] > max_error:
			break
		result = int(levels[i + 1])
	return result


## Forgets the processed meshes (not the disk cache).
static func clear_cache() -> void:
	_cache.clear()


static func _triangles(mesh: ArrayMesh) -> int:
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return 0
	return triangles(mesh)


static func _build(mesh: ArrayMesh, scale: float) -> ArrayMesh:
	var key := _key(mesh, scale)
	var surfaces: Array = _stored_surfaces(key)
	if surfaces.is_empty():
		for surface in mesh.get_surface_count():
			surfaces.append(_surface(mesh, surface, scale))
		if key != "":
			_stored[key] = surfaces
			_dirty = true
	var result := ArrayMesh.new()
	var counts := {}  # error (mesh units) -> triangles over all surfaces
	for surface in mesh.get_surface_count():
		var arrays: Array = surfaces[surface][0]
		var lods: Dictionary = surfaces[surface][1]
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
		result.surface_set_material(surface, mesh.surface_get_material(surface))
		result.surface_set_name(surface, mesh.surface_get_name(surface))
		for error: float in lods:
			counts[error] = counts.get(error, 0) + (lods[error] as PackedInt32Array).size() / 3
	var errors := counts.keys()
	errors.sort()
	var listed := PackedFloat32Array()
	for error: float in errors:
		listed.append(error)
		listed.append(counts[error])
	result.resource_name = mesh.resource_name
	result.set_meta(META_LOD_COUNT, errors.size())
	result.set_meta(META_LOD_LEVELS, listed)
	return result


## One surface of `mesh` indexed, with its levels: [arrays, {error: indices}].
static func _surface(mesh: ArrayMesh, surface: int, scale: float) -> Array:
	var st := SurfaceTool.new()
	st.create_from(mesh, surface)
	st.index()
	var arrays := st.commit_to_arrays()
	var lods := levels(arrays, scale)
	# Smooth organic shells (the soldiers) simplify better with the engine's own generator,
	# which weighs the normals: take whichever draws less in the battle view.
	var engine := engine_levels(arrays)
	var reference := REFERENCE_ERROR / scale
	if _count_at(engine["lods"], reference) < _count_at(lods, reference):
		return [engine["arrays"], engine["lods"]]
	return [arrays, lods]


## Cache key of a mesh's geometry at `scale` ("" = no cache): the sizes and content hashes of
## its vertex data.
static func _key(mesh: ArrayMesh, scale: float) -> String:
	if cache_dir == "":
		return ""
	var parts: Array = [CACHE_VERSION, snappedf(scale, 1e-4)]
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		parts.append(mesh.surface_get_array_len(surface))
		for channel: int in [
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX
		]:
			parts.append(hash(arrays[channel]))
	return str(parts)


## The stored surfaces of `key` ([] when there are none); reads the cache file at the first call.
static func _stored_surfaces(key: String) -> Array:
	if key == "":
		return []
	if not _stored_read:
		_stored_read = true
		var file := FileAccess.open(cache_path(), FileAccess.READ)
		if file != null:
			var data: Variant = file.get_var()
			if data is Dictionary and (data as Dictionary).get("version", 0) == CACHE_VERSION:
				_stored = data["meshes"]
	return _stored.get(key, [])


static func cache_path() -> String:
	return cache_dir.path_join("mesh_lods.bin")


## Writes the levels generated since the last call to the cache file (a temp file renamed over
## the old one); ModelParts.cached calls it after each newly built model.
static func flush() -> void:
	if not _dirty or cache_dir == "":
		return
	_dirty = false
	if _stored.size() > MAX_STORED:
		_stored.clear()
		return
	DirAccess.make_dir_recursive_absolute(cache_dir)
	var path := cache_path()
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_var({"version": CACHE_VERSION, "meshes": _stored})
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)


## Indices drawn of `lods` ({error: indices}) when `max_error` is allowed; a huge number without
## a level that fits (the full mesh).
static func _count_at(lods: Dictionary, max_error: float) -> int:
	var best := 1 << 30
	for error: float in lods:
		if error <= max_error:
			best = mini(best, (lods[error] as PackedInt32Array).size())
	return best


## The levels Godot's generator (ImporterMesh.generate_lods) makes of indexed triangle `arrays`:
## {"arrays": the surface arrays they index (its own vertex order), "lods": {error: indices}}.
static func engine_levels(arrays: Array) -> Dictionary:
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(NORMAL_MERGE_ANGLE, NORMAL_MERGE_ANGLE, [])
	var lods := {}
	for lod in importer.get_surface_lod_count(0):
		lods[importer.get_surface_lod_size(0, lod)] = importer.get_surface_lod_indices(0, lod)
	return {"arrays": importer.get_surface_arrays(0), "lods": lods}


## The coarser levels of indexed triangle `arrays` (Mesh.ARRAY_*): {error in mesh units: indices
## into the same vertices}, as ArrayMesh.add_surface_from_arrays takes them. `scale`: model units
## per mesh unit.
static func levels(arrays: Array, scale := 1.0) -> Dictionary:
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		normals = arrays[Mesh.ARRAY_NORMAL]
	if indices.size() < MIN_TRIANGLES * 3:
		return {}
	# Weld by position: `point_of[v]` is the welded point of vertex v, `first` / `next` chain the
	# vertices of a point.
	var lookup := {}
	var points := PackedVector3Array()
	var point_of := PackedInt32Array()
	point_of.resize(vertices.size())
	var first := PackedInt32Array()
	var next := PackedInt32Array()
	next.resize(vertices.size())
	for v in vertices.size():
		var key := vertices[v].snappedf(WELD)
		var point: int = lookup.get(key, -1)
		if point < 0:
			point = points.size()
			lookup[key] = point
			points.append(vertices[v])
			first.append(-1)
		point_of[v] = point
		next[v] = first[point]
		first[point] = v
	var welded := PackedInt32Array()
	welded.resize(indices.size())
	for i in indices.size():
		welded[i] = point_of[indices[i]]
	# Primitives = connected components of the welded triangles: `root_of[point]`, the longest
	# side of each in `side`, its triangles at the current level in `shown`.
	var parent := PackedInt32Array()
	parent.resize(points.size())
	for p in points.size():
		parent[p] = p
	for i in range(0, welded.size(), 3):
		var a := _find(parent, welded[i])
		var b := _find(parent, welded[i + 1])
		var c := _find(parent, welded[i + 2])
		parent[b] = a
		parent[c] = a
	var root_of := PackedInt32Array()
	root_of.resize(points.size())
	var low := {}
	var high := {}
	var extent_low := points[0]
	var extent_high := points[0]
	for p in points.size():
		var root := _find(parent, p)
		root_of[p] = root
		var at := points[p]
		low[root] = (low[root] as Vector3).min(at) if low.has(root) else at
		high[root] = (high[root] as Vector3).max(at) if high.has(root) else at
		extent_low = extent_low.min(at)
		extent_high = extent_high.max(at)
	var side := {}
	var shown := {}
	for root: int in low:
		var size: Vector3 = high[root] - low[root]
		side[root] = maxf(size.x, maxf(size.y, size.z))
		shown[root] = PackedInt32Array()
	for i in range(0, indices.size(), 3):
		var triangle: PackedInt32Array = shown[root_of[welded[i]]]
		triangle.append(indices[i])
		triangle.append(indices[i + 1])
		triangle.append(indices[i + 2])
	var extent_size := extent_high - extent_low
	var extent := maxf(maxf(extent_size.x, maxf(extent_size.y, extent_size.z)), 1e-9)
	var simplifier := SurfaceTool.new()
	var welded_arrays := []
	welded_arrays.resize(Mesh.ARRAY_MAX)
	welded_arrays[Mesh.ARRAY_VERTEX] = points
	welded_arrays[Mesh.ARRAY_INDEX] = welded
	simplifier.create_from_arrays(welded_arrays)
	var result := {}
	var last := indices.size()
	for model_error in LEVEL_ERRORS:
		var error := model_error / scale
		# The simplifier's error is relative to the mesh's longest side.
		var simple := simplifier.generate_lod(error / extent, 3)
		# The simplified triangles per primitive, each corner on the original vertex at its
		# position whose normal fits the new face best. Faces no vertex normal fits are `bad`
		# (folded over); a primitive with more than MAX_BAD_AREA of them (a thin plate folded
		# through its thickness, a shape turned inside out) keeps the triangles it had.
		var fresh := {}
		var area := {}
		var bad := {}
		for i in range(0, simple.size(), 3):
			var a := simple[i]
			var b := simple[i + 1]
			var c := simple[i + 2]
			var face := (points[c] - points[a]).cross(points[b] - points[a])
			var size := face.length()
			if size <= 0.0:
				continue
			face /= size
			var root := root_of[a]
			var va := _fit(a, face, first, next, normals)
			var fit := _fit_dot
			var vb := _fit(b, face, first, next, normals)
			fit = minf(fit, _fit_dot)
			var vc := _fit(c, face, first, next, normals)
			if not fresh.has(root):
				fresh[root] = PackedInt32Array()
				area[root] = 0.0
				bad[root] = 0.0
			area[root] += size
			if minf(fit, _fit_dot) < MIN_FIT:
				bad[root] += size
			var triangle: PackedInt32Array = fresh[root]
			triangle.append(va)
			triangle.append(vb)
			triangle.append(vc)
		var kept := PackedInt32Array()
		var prune := error * PRUNE_FACTOR
		for root: int in shown:
			if side[root] < prune:
				continue
			if fresh.has(root) and bad[root] <= area[root] * MAX_BAD_AREA:
				if (
					(fresh[root] as PackedInt32Array).size()
					< (shown[root] as PackedInt32Array).size()
				):
					shown[root] = fresh[root]
			kept.append_array(shown[root])
		if kept.is_empty():
			break
		if kept.size() <= last * MIN_GAIN:
			result[error / ERROR_PIXELS] = kept
			last = kept.size()
	return result


## Root of `p` in the union-find `parent` (with path halving).
static func _find(parent: PackedInt32Array, p: int) -> int:
	while parent[p] != p:
		parent[p] = parent[parent[p]]
		p = parent[p]
	return p


## The vertex at welded point `point` whose normal fits the unit face normal `face` best; the
## fit (their dot product, 1 without normals) is left in `_fit_dot`.
static func _fit(
	point: int,
	face: Vector3,
	first: PackedInt32Array,
	next: PackedInt32Array,
	normals: PackedVector3Array
) -> int:
	var best := first[point]
	_fit_dot = 1.0
	if normals.is_empty():
		return best
	_fit_dot = normals[best].dot(face)
	var v := next[best]
	while v >= 0:
		var dot := normals[v].dot(face)
		if dot > _fit_dot:
			_fit_dot = dot
			best = v
		v = next[v]
	return best
