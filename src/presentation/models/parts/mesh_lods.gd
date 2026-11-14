class_name MeshLods
extends RefCounted
## Levels of detail for the procedural unit models: `with_lods(mesh)` returns the same geometry
## indexed and with Godot's automatic LODs (ImporterMesh.generate_lods, the simplifier the scene
## importer uses), cached per source mesh; `apply(root)` swaps the meshes of every MeshInstance3D
## under a built model. The renderer then picks per instance the coarsest level whose error stays
## under a pixel, in the colour and the shadow passes alike. Without it a model is ~100 k unshared
## triangles at any distance: ten units in the battle overview, a few dozen pixels each, were 1 M
## triangles and ~2.5 ms on the target GPU.

## Smaller meshes are left alone (nothing to gain, and the simplifier needs some triangles).
const MIN_TRIANGLES := 64
## Vertices at one position whose normals differ by less than this are welded for simplifying.
const NORMAL_MERGE_ANGLE := 60.0
## Mesh metadata: the number of generated levels below the full mesh (tests, tools).
const META_LOD_COUNT := &"lod_count"

static var _cache: Dictionary = {}  # source mesh instance id -> ArrayMesh


## Replaces the mesh of every MeshInstance3D under `root` (inclusive) by `with_lods` of it.
static func apply(root: Node) -> void:
	var instance := root as MeshInstance3D
	if instance != null and instance.mesh != null:
		instance.mesh = with_lods(instance.mesh)
	for child in root.get_children():
		apply(child)


## `mesh` with indexed surfaces and generated LODs (materials and surface names kept); `mesh`
## itself when it is too small, not made of triangles or already processed.
static func with_lods(mesh: Mesh) -> Mesh:
	var id := mesh.get_instance_id()
	if _cache.has(id):
		return _cache[id]
	var result := mesh
	if mesh.has_meta(META_LOD_COUNT):
		return mesh
	if mesh is ArrayMesh and _triangles(mesh as ArrayMesh) >= MIN_TRIANGLES:
		result = _build(mesh as ArrayMesh)
	_cache[id] = result
	return result


## Generated levels of a mesh returned by `with_lods` (0 for an untouched mesh).
static func lod_count(mesh: Mesh) -> int:
	return mesh.get_meta(META_LOD_COUNT, 0)


static func clear_cache() -> void:
	_cache.clear()


static func _triangles(mesh: ArrayMesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return 0
		var indices := mesh.surface_get_array_index_len(surface)
		total += (indices if indices > 0 else mesh.surface_get_array_len(surface)) / 3
	return total


static func _build(mesh: ArrayMesh) -> ArrayMesh:
	var importer := ImporterMesh.new()
	for surface in mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(mesh, surface)
		st.index()
		importer.add_surface(
			Mesh.PRIMITIVE_TRIANGLES,
			st.commit_to_arrays(),
			[],
			{},
			mesh.surface_get_material(surface),
			mesh.surface_get_name(surface)
		)
	importer.generate_lods(NORMAL_MERGE_ANGLE, NORMAL_MERGE_ANGLE, [])
	var levels := 0
	for surface in importer.get_surface_count():
		levels = maxi(levels, importer.get_surface_lod_count(surface))
	var result := importer.get_mesh()
	result.resource_name = mesh.resource_name
	result.set_meta(META_LOD_COUNT, levels)
	return result
