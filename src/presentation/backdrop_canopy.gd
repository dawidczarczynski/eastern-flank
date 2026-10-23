class_name BackdropCanopy
extends RefCounted
## Distant forest of the backdrop: a shell over the backdrop lattice (BackdropMesh) drawn by
## assets/shaders/canopy.gdshader as tree crowns, instead of individual trees. Vertex colour r is
## the forest cover; the shell is lifted by HEIGHT x tree scale where it is forest, and fades in
## with the distance from the playable mesh over FADE_FROM..FADE_TO (MapView keeps real trees
## closer than that).

const SHADER := preload("res://assets/shaders/canopy.gdshader")
const SPECIES: Array[StringName] = [&"pine", &"spruce", &"birch", &"oak", &"alder"]
const HEIGHT := 0.22
const FADE_FROM := 1.5
const FADE_TO := 5.0


## The crown material in the species colours of the active look.
static func material() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	for species in SPECIES:
		result.set_shader_parameter(
			StringName("%s_color" % species),
			LookPreset.leaf_color(species, TreeField.LEAF_COLORS[species])
		)
	return result


## BackdropMesh surface callback: cover (the first weight of each vertex) goes to the vertex
## colour and lifts the vertex by `lift`.
static func add_surface(
	mesh: ArrayMesh, arrays: Array, weights: PackedFloat32Array, lift: float
) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	for i in vertices.size():
		var cover := weights[i * TerrainSplat.LAYER_COUNT]
		vertices[i].y += lift * cover
		colors.append(Color(cover, 0.0, 0.0, 1.0))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
