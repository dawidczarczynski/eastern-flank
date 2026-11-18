extends RefCounted
## Loads a reference GLB (a Meshy model used instead of photos, TASK-179) and normalises it to the
## unit catalog's dimensions: model faces +X, stands on y = 0, centred in x/z, scaled uniformly so
## its length equals the catalog length (a foot unit: its height). Pure geometry, no rendering;
## used by tools/render_glb.gd (tools/analyze_glb.sh). The GLB is a reference only: it never
## enters the game.

## Share of the length at each end used to tell the front from the rear.
const END_SLAB := 0.12
## The model's bounding box may differ at most this much from the catalog before the run fails.
const MAX_DEVIATION := 0.25
## Thin outliers (antennas, flag poles) are ignored when the height is compared with the catalog:
## the height is measured up to this share of the vertices.
const HEIGHT_PERCENTILE := 0.98
## Names of the --front values: the GLB axis that points to the vehicle's front.
const FRONT_YAW_DEG := {"+x": 0.0, "-x": 180.0, "+z": 90.0, "-z": -90.0}


## The GLB scene root, or null (missing file, no mesh).
static func load_scene(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	var scene := document.generate_scene(state)
	if scene == null or not scene is Node3D or mesh_instances(scene).is_empty():
		if scene != null:
			scene.free()
		return null
	return scene as Node3D


static func mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(mesh_instances(child))
	return found


## All vertices of the scene in the space of `scene` (the node transforms applied).
static func vertices(scene: Node3D) -> PackedVector3Array:
	var all := PackedVector3Array()
	for instance in mesh_instances(scene):
		var transform := _relative_transform(instance, scene)
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var positions: Variant = arrays[Mesh.ARRAY_VERTEX]
			if positions is PackedVector3Array:
				all.append_array(transform * (positions as PackedVector3Array))
	return all


## The scene's triangles with `scene.transform` applied too (after normalise(): metres, front
## +X): {"positions": PackedVector3Array, "indices": PackedInt32Array (a triangle list)}.
## Input of tools/glb_measurements.gd (TASK-180).
static func triangles(scene: Node3D) -> Dictionary:
	var positions := PackedVector3Array()
	var indices := PackedInt32Array()
	for instance in mesh_instances(scene):
		var transform := scene.transform * _relative_transform(instance, scene)
		for surface in instance.mesh.get_surface_count():
			if instance.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
			if not vertex_data is PackedVector3Array:
				continue
			var surface_points := vertex_data as PackedVector3Array
			var base := positions.size()
			positions.append_array(transform * surface_points)
			var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
			if index_data is PackedInt32Array and not (index_data as PackedInt32Array).is_empty():
				for index in index_data as PackedInt32Array:
					indices.append(base + index)
			else:
				for i in surface_points.size() - surface_points.size() % 3:
					indices.append(base + i)
	return {"positions": positions, "indices": indices}


static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var transform := Transform3D()
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform


static func bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var low := points[0]
	var high := points[0]
	for point in points:
		low = low.min(point)
		high = high.max(point)
	return AABB(low, high - low)


## Rotation about Y (degrees) that makes the longer horizontal axis lie along +X and the narrower
## end (a gun barrel, a thin nose) the front. `front` ("+x", "-x", "+z", "-z", "" = automatic)
## names the GLB axis pointing to the front. The glTF up axis is +Y.
static func front_yaw_deg(points: PackedVector3Array, front: String = "") -> float:
	if front != "":
		return FRONT_YAW_DEG[front]
	var box := bounds(points)
	var along_z := box.size.z > box.size.x
	var yaw := 90.0 if along_z else 0.0
	var aligned := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3.ZERO) * points
	if _end_area(aligned, true) > _end_area(aligned, false):
		return yaw + 180.0  # the narrow end is at -x: turn it to the front
	return yaw


## Cross-section (width x height of the bounding box) of the slab at the front (+x) or rear end.
static func _end_area(points: PackedVector3Array, front_end: bool) -> float:
	var box := bounds(points)
	var slab := box.size.x * END_SLAB
	var low := PackedVector3Array()
	for point in points:
		var inside := point.x >= box.end.x - slab if front_end else point.x <= box.position.x + slab
		if inside:
			low.append(point)
	var part := bounds(low)
	return part.size.y * part.size.z


## Normalises `scene` in place (its transform is set) and returns what was applied:
## {"yaw_deg", "scale" (metres per GLB unit), "front_auto", "size_m" (Vector3: x length, y height,
## z width after scaling), "source_size" (Vector3, GLB units), "warnings" (Array[String])}.
## `real`: {"length", "width", "height"} in metres (or {"height"} for a foot unit); {} = none.
static func normalise(scene: Node3D, real: Dictionary, front: String = "") -> Dictionary:
	scene.transform = Transform3D()
	var points := vertices(scene)
	var source := bounds(points)
	var yaw := front_yaw_deg(points, front)
	var rotated_points := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3.ZERO) * points
	var rotated := bounds(rotated_points)
	var foot := real.has("height") and not real.has("length")
	var target := float(real.get("height", 1.0)) if foot else float(real.get("length", 1.0))
	var extent := rotated.size.y if foot else rotated.size.x
	var scale := target / maxf(extent, 0.000001) if not real.is_empty() else 1.0
	var centre := rotated.get_center()
	var offset := Vector3(-centre.x, -rotated.position.y, -centre.z) * scale
	scene.transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(yaw)).scaled(Vector3.ONE * scale), offset
	)
	var size := rotated.size * scale
	var robust := Vector3(size.x, _robust_height(rotated_points) * scale, size.z)
	return {
		"yaw_deg": fposmod(yaw, 360.0),
		"scale": scale,
		"front_auto": front == "",
		"size_m": size,
		"source_size": source.size,
		"robust_height_m": robust.y,
		"warnings": warnings(robust, real),
	}


## Height of the body without thin outliers: from the lowest point to the HEIGHT_PERCENTILE of
## the vertex heights (GLB units).
static func _robust_height(points: PackedVector3Array) -> float:
	var heights := PackedFloat32Array()
	heights.resize(points.size())
	for i in points.size():
		heights[i] = points[i].y
	heights.sort()
	return heights[int((heights.size() - 1) * HEIGHT_PERCENTILE)] - heights[0]


## Deviations of the normalised size (x length, y height, z width) from the catalog beyond
## MAX_DEVIATION; a foot unit compares nothing but the height it was scaled to.
static func warnings(size: Vector3, real: Dictionary) -> Array[String]:
	var found: Array[String] = []
	if real.is_empty() or not real.has("length"):
		return found
	var checks := {"width": [size.z, "width"], "height": [size.y, "height"]}
	for key: String in checks:
		var model: float = checks[key][0]
		var expected: float = real[key]
		var deviation := absf(model - expected) / expected
		if deviation > MAX_DEVIATION:
			found.append(
				(
					"%s %.2f m vs. catalog %.2f m (%+.0f%%)"
					% [key, model, expected, (model - expected) / expected * 100.0]
				)
			)
	return found
