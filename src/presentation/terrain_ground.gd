class_name TerrainGround
extends RefCounted
## The terrain ground of MapView (TASK-055): the ShaderMaterial on assets/shaders/terrain.gdshader
## with the TerrainTextures arrays, and how the per-vertex TerrainSplat weights are stored in a
## mesh surface. Shared by the playable terrain mesh and the backdrop ring.

const SHADER := preload("res://assets/shaders/terrain.gdshader")
## Ground texture repeat: the layers' real-world size (TerrainTextures.SOURCE_METRES) at the
## game scale (METRES_PER_UNIT), enlarged by REPEAT_SCALE so the texture still reads at the
## default zoom (repeats: grass 0.73, dry grass / dirt / gravel 1.04, mud 0.68, rock 0.78
## world units).
const METRES_PER_UNIT := 7.7
const REPEAT_SCALE := 4.0
## Texture array size when no quality switches are set (GraphicsQuality "terrain_texture_size").
const DEFAULT_TEXTURE_SIZE := 1024
## Linear albedo tint per ground layer (TerrainSplat order) towards the game's olive palette:
## a touch greener grass, olive instead of beige dry grass, darker forest-floor dirt, slightly
## greyer gravel and rock (the sources are warm brown).
const LAYER_TINTS: Array[Vector3] = [
	Vector3(1.0, 1.15, 1.0),
	Vector3(0.8, 1.0, 0.5),
	Vector3(0.42, 0.46, 0.4),
	Vector3(1.0, 1.0, 1.0),
	Vector3(0.9, 0.97, 1.05),
	Vector3(1.0, 1.15, 1.3),
]
## Added to each 8-bit colour level so the truncating conversion keeps the intended level.
const COLOR_QUANT_BIAS := 0.25


## Adds the triangle surface of `arrays` with the per-vertex ground weights `weights`
## (TerrainSplat.LAYER_COUNT per vertex): layers 0-3 in ARRAY_COLOR, 4-5 in ARRAY_CUSTOM0
## (RGBA float; z and w stay free for TASK-035).
static func add_surface(mesh: ArrayMesh, arrays: Array, weights: PackedFloat32Array) -> void:
	var layers := TerrainSplat.LAYER_COUNT
	var count := weights.size() / layers
	var colors := PackedColorArray()
	colors.resize(count)
	var custom := PackedFloat32Array()
	custom.resize(count * 4)
	for v in count:
		var o := v * layers
		# Vertex colours are stored as 8-bit unorm (truncated): quantise the running sum so the
		# four channels together stay within half a step of their true sum.
		var q := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		var exact := 0.0
		var stored := 0.0
		for c in 4:
			exact += weights[o + c]
			var level := roundf(exact * 255.0)
			q[c] = (level - stored + COLOR_QUANT_BIAS) / 255.0
			stored = level
		colors[v] = Color(q[0], q[1], q[2], q[3])
		custom[v * 4] = weights[o + 4]
		custom[v * 4 + 1] = weights[o + 5]
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	var format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)


## Texture array size for the graphics quality switches `quality` (GraphicsQuality.features).
static func texture_size(quality: Dictionary) -> int:
	return quality.get("terrain_texture_size", DEFAULT_TEXTURE_SIZE)


## terrain.gdshader with the TerrainTextures arrays; anti-tiling and triplanar rock follow
## `quality` (GraphicsQuality.features).
static func material(quality: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var maps := TerrainTextures.arrays(texture_size(quality))
	material.set_shader_parameter(&"albedo_height", maps["albedo_height"])
	material.set_shader_parameter(&"normal_maps", maps["normal"])
	material.set_shader_parameter(&"roughness_ao", maps["roughness_ao"])
	var repeats := PackedFloat32Array()
	for metres in TerrainTextures.SOURCE_METRES:
		repeats.append(metres / METRES_PER_UNIT * REPEAT_SCALE)
	material.set_shader_parameter(&"layer_repeat", repeats)
	material.set_shader_parameter(
		&"layer_tint", PackedVector3Array(LookPreset.layer_tints(LAYER_TINTS))
	)
	material.set_shader_parameter(&"anti_tiling", quality.get("terrain_anti_tiling", true))
	material.set_shader_parameter(&"triplanar", quality.get("terrain_triplanar", true))
	material.set_shader_parameter(&"water_level", TerrainSurface.WATER_SURFACE)
	return material
