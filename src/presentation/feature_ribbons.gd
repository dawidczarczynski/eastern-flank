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

const ROAD_SHADER := preload("res://assets/shaders/road.gdshader")
const RIVER_SHADER := preload("res://assets/shaders/river.gdshader")
## Ripple normal map size (texels) of the river shader.
const RIVER_NORMAL_SIZE := 256
## Downstream speed of the river's ripples, metres per second (GraphicsQuality `river_flow`).
const RIVER_FLOW_SPEED_M := 0.4
## Draw order: the river (transparent) below the road ribbon.
const RIVER_RENDER_PRIORITY := -1


## Adds the road and river ribbons and the bridges of `grid` to `parent` (nothing on maps without
## links); `quality` is GraphicsQuality.features (river_flow, shadows).
## `crest` false: `drape` already gives the exact drawn ground (MapView._ribbon_drape), so the
## corners are only lifted by `FeatureRibbonPlanner.lift` (no crest lift for the coarse mesh).
static func add_to(
	parent: Node3D,
	grid: HexGrid,
	drape: Callable,
	ground: ShaderMaterial,
	quality: Dictionary,
	crest := true
) -> void:
	for kind: FeatureRibbonPlanner.Kind in FeatureRibbonPlanner.Kind.values():
		var ribbon := build(grid, kind, drape, ground, quality.get("river_flow", true), crest)
		if ribbon != null:
			parent.add_child(ribbon)
	var bridges := Bridges.build(
		FeatureRibbonPlanner.bridges(grid), drape, quality.get("shadows", true)
	)
	if bridges != null:
		parent.add_child(bridges)


## The ribbon of `kind` as one flat mesh; `drape` is Callable(points: PackedVector2Array,
## lift: float) -> PackedVector3Array (MapView._drape, the terrain mesh height). Null when the
## grid has no links of `kind` (generated maps).
static func build(
	grid: HexGrid,
	kind: FeatureRibbonPlanner.Kind,
	drape: Callable,
	ground: ShaderMaterial = null,
	river_flow := true,
	crest := true
) -> MeshInstance3D:
	var indexed := FeatureRibbonPlanner.mesh(grid, kind)
	var points: PackedVector2Array = indexed["points"]
	if points.is_empty():
		return null
	var indices: PackedInt32Array = indexed["indices"]
	var lift := FeatureRibbonPlanner.lift(kind)
	var vertices: PackedVector3Array = (
		drape_lifted(points, indices, lift, drape) if crest else drape.call(points, lift)
	)
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	# Across value in UV.y, UV.x the river's flow coordinate (metres from the upstream end),
	# widening direction in CUSTOM0.xy (road and river shaders).
	var across: PackedFloat32Array = indexed["across"]
	var dirs: PackedVector2Array = indexed["across_dirs"]
	var uvs := PackedVector2Array()
	var custom := PackedFloat32Array()
	uvs.resize(across.size())
	custom.resize(across.size() * 2)
	var is_river := kind == FeatureRibbonPlanner.Kind.RIVER
	var along: PackedFloat32Array = indexed.get("along", PackedFloat32Array())
	for i in across.size():
		uvs[i] = Vector2(along[i] if is_river else 0.0, across[i])
		custom[2 * i] = dirs[i].x
		custom[2 * i + 1] = dirs[i].y
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if is_river:
		# The water edge's across value in COLOR.r, the end fade in COLOR.g; tangents along +x
		# for the normal map.
		var colors := PackedColorArray()
		var tangents := PackedFloat32Array()
		var edge: PackedFloat32Array = indexed["water_edge"]
		var fade: PackedFloat32Array = indexed["fade"]
		colors.resize(across.size())
		tangents.resize(across.size() * 4)
		for i in across.size():
			colors[i] = Color(edge[i], fade[i], 0.0, 1.0)
			tangents[4 * i] = 1.0
			tangents[4 * i + 3] = 1.0
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	var format := Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
	if kind == FeatureRibbonPlanner.Kind.ROAD and ground != null:
		mesh.surface_set_material(0, road_material(ground))
	elif is_river and ground != null:
		mesh.surface_set_material(0, river_material(ground, river_flow))
	else:
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


## The road shader fed with the ground textures, repeats and tints of the terrain material
## `ground` (TerrainGround.material), at the current MapScale.
static func road_material(ground: ShaderMaterial) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = ROAD_SHADER
	for key: StringName in [&"albedo_height", &"layer_tint"]:
		result.set_shader_parameter(key, ground.get_shader_parameter(key))
	# One sample per pixel, no distance cross-fade: the ground's far pattern (TASK-134), which
	# reads at every zoom of a 14 m road.
	result.set_shader_parameter(&"layer_repeat", ground.get_shader_parameter(&"layer_repeat_far"))
	result.set_shader_parameter(
		&"half_width", FeatureRibbonPlanner.width(FeatureRibbonPlanner.Kind.ROAD) / 2.0
	)
	result.set_shader_parameter(&"carriageway", FeatureRibbonPlanner.carriageway_across())
	return result


## The river shader fed with the ground textures of `ground` (the mud layer of the banks) and the
## water normal map; `flow` off (GraphicsQuality `river_flow`): static ripples.
static func river_material(ground: ShaderMaterial, flow: bool) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = RIVER_SHADER
	result.render_priority = RIVER_RENDER_PRIORITY
	for key: StringName in [&"albedo_height", &"layer_tint"]:
		result.set_shader_parameter(key, ground.get_shader_parameter(key))
	result.set_shader_parameter(&"layer_repeat", ground.get_shader_parameter(&"layer_repeat_far"))
	result.set_shader_parameter(&"normal_map", WaterPlane.normal_texture(RIVER_NORMAL_SIZE))
	result.set_shader_parameter(&"units_per_m", MapScale.to_units(1.0))
	result.set_shader_parameter(&"bank_m", FeatureRibbonPlanner.RIVER_BANK_M)
	result.set_shader_parameter(&"bank_k", FeatureRibbonPlanner.BANK_PER_WATER)
	result.set_shader_parameter(&"flow_speed", RIVER_FLOW_SPEED_M if flow else 0.0)
	return result


## Fallback matt grey-brown road (no ground material); blue-grey river with a slight specular.
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
