class_name ScatterChunks
extends RefCounted
## Bushes and rocks of a MapView as chunked MultiMeshes (TASK-108 performance): one
## MultiMeshInstance3D per TreeField chunk under one parent node. A single node for the whole map
## had a map-sized AABB, so every bush and rock was drawn every frame wherever the camera looked
## (on the 6x larger imported maps ~3 M triangles, ~5 ms on the target GPU); chunks are frustum
## culled. With a far mesh each chunk gets a near node up to BUSH_LOD_DISTANCE from the camera
## (measured from the chunk centre) and a "<name>Far_<x>_<z>" node from there on. The switch is
## hard (BUSH_LOD_MARGIN is only its hysteresis): the two meshes differ by one subdivision of a
## blob a dozen pixels wide, while Godot's range fade draws both alpha-blended without the depth
## prepass (~0.6 ms on the target GPU), and the near mesh out to 28 units cost another ~1.8 ms.

const BUSH_LOD_DISTANCE := 16.0
const BUSH_LOD_MARGIN := 2.0


## The parent node `node_name` with the chunk nodes "<node_name>_<x>_<z>" (and the far ones).
static func build(
	node_name: String,
	mesh: Mesh,
	material: Material,
	transforms: Array[Transform3D],
	colors: PackedColorArray,
	far_mesh: Mesh = null
) -> Node3D:
	var parent := Node3D.new()
	parent.name = node_name
	var groups: Dictionary = {}  # chunk -> Array of instance indices
	for i in transforms.size():
		(groups.get_or_add(TreeField.chunk_of(transforms[i].origin), []) as Array).append(i)
	var chunks := groups.keys()
	chunks.sort()
	for chunk: Vector2i in chunks:
		var members: Array = groups[chunk]
		var chunk_transforms: Array[Transform3D] = []
		var chunk_colors := PackedColorArray()
		for index: int in members:
			chunk_transforms.append(transforms[index])
			if not colors.is_empty():
				chunk_colors.append(colors[index])
		for node in build_chunk(
			node_name, mesh, material, chunk_transforms, chunk_colors, chunk, far_mesh
		):
			parent.add_child(node)
	return parent


## The nodes of one chunk (TASK-072b: the chunked world builds them one chunk at a time):
## "<node_name>_<x>_<z>" and, with a far mesh, "<node_name>Far_<x>_<z>". `transforms` are world
## transforms of the chunk's instances.
static func build_chunk(
	node_name: String,
	mesh: Mesh,
	material: Material,
	transforms: Array[Transform3D],
	colors: PackedColorArray,
	chunk: Vector2i,
	far_mesh: Mesh = null
) -> Array[MultiMeshInstance3D]:
	var result: Array[MultiMeshInstance3D] = []
	if transforms.is_empty():
		return result
	var members: Array = range(transforms.size())
	var origin := TreeField.chunk_center(chunk)
	var near := _chunk(mesh, material, transforms, colors, members, origin)
	near.name = "%s_%d_%d" % [node_name, chunk.x, chunk.y]
	result.append(near)
	if far_mesh == null:
		return result
	near.visibility_range_end = BUSH_LOD_DISTANCE
	near.visibility_range_end_margin = BUSH_LOD_MARGIN
	var far := _chunk(far_mesh, material, transforms, colors, members, origin)
	far.name = "%sFar_%d_%d" % [node_name, chunk.x, chunk.y]
	far.visibility_range_begin = BUSH_LOD_DISTANCE
	far.visibility_range_begin_margin = BUSH_LOD_MARGIN
	result.append(far)
	return result


## One chunk: the `members` of `transforms` / `colors` relative to `origin`.
static func _chunk(
	mesh: Mesh,
	material: Material,
	transforms: Array[Transform3D],
	colors: PackedColorArray,
	members: Array,
	origin: Vector3
) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = not colors.is_empty()
	multi.mesh = mesh
	multi.instance_count = members.size()
	for k in members.size():
		var index: int = members[k]
		var t := transforms[index]
		multi.set_instance_transform(k, Transform3D(t.basis, t.origin - origin))
		if multi.use_colors:
			multi.set_instance_color(k, colors[index])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
	instance.position = origin
	# No shadows: small, and once drawn into every cascade they cost most of the frame.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
