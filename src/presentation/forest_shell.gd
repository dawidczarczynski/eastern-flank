class_name ForestShell
extends RefCounted
## The canopy shell of the real-scale forest (TASK-135, ADR 0026; `true` VisualScale preset only):
## beyond the tree impostors' range a forest tile is one surface lifted to the crown tops, painted
## as closed crowns by assets/shaders/canopy.gdshader (as BackdropCanopy is for the backdrop) and
## faded in crown by crown with the camera distance where the impostors end (`near_fade`), so a
## zoomed-out forest reads as a closed canopy at the cost of a few triangles per cell.
## The mesh is a regular grid of STEP cells over the map: a vertex's cover is 1 on a forest tile
## and 0 elsewhere (the shader drops crowns where the interpolated cover is low, so the edges are
## ragged), its height the drawn ground plus `lift` x cover, its normal the drawn ground's
## (TASK-191: the dome normals of the crowns stand on it, so a slope facing away from the sun is
## darker). Only cells touching the forest are emitted.

const STEP := 0.125
const NODE := "ForestShell"


## The shell over the forest tiles of `grid` within `rect`, or null without forest.
## `height_fn` is Callable(x, z) -> float (the drawn ground). `look` (TASK-108g): the vertex cover
## is the land-cover raster's soft forest share instead of the forest tiles.
static func build_mesh(
	grid: HexGrid, rect: Rect2, height_fn: Callable, lift: float, look: CoverLook = null
) -> ArrayMesh:
	var cells := Vector2i((rect.size / STEP).ceil())
	var row := cells.x + 1
	var cover := PackedFloat32Array()
	cover.resize(row * (cells.y + 1))
	var any := false
	for j in cells.y + 1:
		for i in row:
			var p := Vector3(rect.position.x + i * STEP, 0.0, rect.position.y + j * STEP)
			if look != null:
				cover[j * row + i] = look.forest_k(p.x, p.z)
			else:
				var c := Hex.from_world(p, TerrainField.HEX_SIZE)
				if grid.has_tile(c) and grid.get_terrain(c) == Terrain.Type.FOREST:
					cover[j * row + i] = 1.0
			any = any or cover[j * row + i] > 0.0
	if not any:
		return null
	var vertices := PackedVector3Array()
	var ground := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var index_of: Dictionary = {}
	for j in cells.y:
		for i in cells.x:
			var corners: Array[int] = [
				j * row + i, j * row + i + 1, (j + 1) * row + i, (j + 1) * row + i + 1
			]
			var touches := false
			for k in corners:
				touches = touches or cover[k] > 0.0
			if not touches:
				continue
			var ids: Array[int] = []
			for k in corners:
				if not index_of.has(k):
					var x := rect.position.x + (k % row) * STEP
					var z := rect.position.y + floori(float(k) / row) * STEP
					var c := float(cover[k])
					var h: float = height_fn.call(x, z)
					index_of[k] = vertices.size()
					vertices.append(Vector3(x, h + lift * c, z))
					ground.append(Vector3(x, h, z))
					colors.append(Color(c, 0.0, 0.0, 1.0))
				ids.append(index_of[k])
			indices.append_array([ids[0], ids[1], ids[2], ids[1], ids[3], ids[2]])
	var normals := ground_normals(ground, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Vertex normals of the ground under the shell (the lift is left out: it would tilt the forest
## edges): area-weighted face normals of `indices` over `ground`, upwards.
static func ground_normals(
	ground: PackedVector3Array, indices: PackedInt32Array
) -> PackedVector3Array:
	var sums := PackedVector3Array()
	sums.resize(ground.size())
	for t in range(0, indices.size(), 3):
		var a := ground[indices[t]]
		var face := (ground[indices[t + 2]] - a).cross(ground[indices[t + 1]] - a)
		if face.y < 0.0:
			face = -face
		for k in 3:
			sums[indices[t + k]] += face
	for i in sums.size():
		sums[i] = sums[i].normalized() if sums[i].length_squared() > 0.0 else Vector3.UP
	return sums


## The shell node for the active look: canopy material in the species colours, the crown cell and
## the fade-in band of LookPreset.vegetation() (a share of the shortest species' impostor range),
## no shadow. Null without forest.
static func build(
	grid: HexGrid, rect: Rect2, height_fn: Callable, look: CoverLook = null
) -> MeshInstance3D:
	var values := LookPreset.vegetation()
	var tree_m: float = VisualScale.TRUE_HEIGHTS_M[&"tree"]
	var lift := MapScale.to_units(tree_m * float(values["shell_height_share"]))
	var mesh := build_mesh(grid, rect, height_fn, lift, look)
	if mesh == null:
		return null
	var material := BackdropCanopy.material()
	material.set_shader_parameter(&"crown_cell", MapScale.to_units(values["shell_crown_m"]))
	material.set_shader_parameter(&"brightness", values["shell_brightness"])
	material.set_shader_parameter(&"lit_domes", 1.0)
	material.set_shader_parameter(&"slope_share", values["impostor_slope_share"])
	material.set_shader_parameter(&"view_share", values["shell_view_share"])
	# The species colours of the impostors' unlit albedo (the shader's colour uniforms are sRGB);
	# the sun and ambient light the shell as they light the impostors.
	TreeImpostors.prime()
	for species in BackdropCanopy.SPECIES:
		material.set_shader_parameter(
			StringName("%s_color" % species), TreeImpostors.base_color(species)
		)
	# In before the shortest species' impostors end (taller ones overlap it a little longer).
	var reach := INF
	for species in TreeSpecies.all():
		reach = minf(
			reach,
			VegetationRanges.impostor_range(VegetationRanges.species_height_m(species), values)
		)
	var fade: Vector2 = values["shell_fade"]
	material.set_shader_parameter(&"near_fade", fade * reach)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = NODE
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
