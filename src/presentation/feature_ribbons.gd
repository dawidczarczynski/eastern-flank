class_name FeatureRibbons
extends RefCounted
## Builds the road / river ribbon meshes of a map (TASK-108) from FeatureRibbonPlanner's flat
## triangles (smooth chained centrelines): one MeshInstance3D per kind (one draw call each),
## draped on the drawn terrain mesh.
##
## The terrain mesh is piecewise linear with creases every 0.25 units, so a flat ribbon triangle
## draped only at its corners can dip under a convex crest between them. Each corner is lifted
## (`drape_lifted`) by twice the largest height the terrain rises above the triangle at its edge
## midpoints and centroid (for one crease along an edge the midpoint sees at least half of the
## worst dip), the largest of all triangles sharing that corner (the mesh is indexed, so shared
## corners stay together).


## The ribbon of `kind` as one flat mesh; `drape` is Callable(points: PackedVector2Array,
## lift: float) -> PackedVector3Array (MapView._drape, the terrain mesh height). Null when the
## grid has no links of `kind` (generated maps).
static func build(
	grid: HexGrid, kind: FeatureRibbonPlanner.Kind, drape: Callable
) -> MeshInstance3D:
	var indexed := FeatureRibbonPlanner.mesh(grid, kind)
	var points: PackedVector2Array = indexed["points"]
	if points.is_empty():
		return null
	var indices: PackedInt32Array = indexed["indices"]
	var vertices := drape_lifted(points, indices, FeatureRibbonPlanner.lift(kind), drape)
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material(kind))
	var instance := MeshInstance3D.new()
	instance.name = "Roads" if kind == FeatureRibbonPlanner.Kind.ROAD else "Rivers"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## The flat mesh (`points`, triangle `indices`) draped by `drape` at `lift`, every point raised
## by its crest lift.
static func drape_lifted(
	points: PackedVector2Array, indices: PackedInt32Array, lift: float, drape: Callable
) -> PackedVector3Array:
	var ground: PackedVector3Array = drape.call(points, 0.0)
	var count := indices.size() / 3
	# Probes per triangle: the three edge midpoints and the centroid.
	var probes := PackedVector2Array()
	probes.resize(count * 4)
	for t in count:
		var a := points[indices[3 * t]]
		var b := points[indices[3 * t + 1]]
		var c := points[indices[3 * t + 2]]
		probes[4 * t] = (a + b) * 0.5
		probes[4 * t + 1] = (b + c) * 0.5
		probes[4 * t + 2] = (c + a) * 0.5
		probes[4 * t + 3] = (a + b + c) / 3.0
	var heights: PackedVector3Array = drape.call(probes, 0.0)
	var extra := PackedFloat32Array()
	extra.resize(points.size())
	for t in count:
		var ia := indices[3 * t]
		var ib := indices[3 * t + 1]
		var ic := indices[3 * t + 2]
		var ha := ground[ia].y
		var hb := ground[ib].y
		var hc := ground[ic].y
		var dip := maxf(
			maxf(heights[4 * t].y - (ha + hb) * 0.5, heights[4 * t + 1].y - (hb + hc) * 0.5),
			maxf(
				heights[4 * t + 2].y - (hc + ha) * 0.5, heights[4 * t + 3].y - (ha + hb + hc) / 3.0
			)
		)
		var lift_t := 2.0 * maxf(dip, 0.0)
		extra[ia] = maxf(extra[ia], lift_t)
		extra[ib] = maxf(extra[ib], lift_t)
		extra[ic] = maxf(extra[ic], lift_t)
	var result := PackedVector3Array()
	result.resize(points.size())
	for i in points.size():
		result[i] = ground[i] + Vector3(0.0, lift + extra[i], 0.0)
	return result


## Matt grey-brown road; blue-grey river with a slight specular.
static func material(kind: FeatureRibbonPlanner.Kind) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.roughness = 1.0
	result.albedo_color = FeatureRibbonPlanner.ROAD_COLOR
	if kind == FeatureRibbonPlanner.Kind.RIVER:
		result.albedo_color = FeatureRibbonPlanner.RIVER_COLOR
		result.roughness = FeatureRibbonPlanner.RIVER_ROUGHNESS
		result.metallic_specular = FeatureRibbonPlanner.RIVER_SPECULAR
	return result
