class_name TerrainGround
extends RefCounted
## The terrain ground of MapView (TASK-055): the ShaderMaterial on assets/shaders/terrain.gdshader
## with the TerrainTextures arrays, and how the per-vertex TerrainSplat weights are stored in a
## mesh surface. Shared by the playable terrain mesh and the backdrop ring.

const SHADER := preload("res://assets/shaders/terrain.gdshader")
## Ground texture repeat (TASK-134): one repeat of a layer covers its scanned real size
## (TerrainTextures.SOURCE_METRES, 1.3-3 m), in world units through MapScale – real metres, not the
## former 7.7 m / unit x 4: close up it is real grass, gravel, soil.
## Farther than SCALE_FADE (view distance, world units: from x to y) the layers cross-fade to a
## pattern FAR_PATTERN_FACTOR x their real size (~100 m for grass, the former look), which still
## reads from the default zoom, where a real-size repeat is under a pixel.
const FAR_PATTERN_FACTOR := 75.0
const SCALE_FADE := Vector2(2.5, 6.0)
## The ground detail texture: a tileable procedural height / normal map (DetailTexture) repeating
## every DETAIL_METRES (a second, rotated sample at DETAIL_SECOND x that size), which brightens /
## darkens the albedo and tilts the normal between the scanned texel scale and the mesh – faded in
## by view distance (world units): none beyond DETAIL_FADE.y, full below DETAIL_FADE.x.
const DETAIL_METRES := 24.0
const DETAIL_SECOND := 0.3
const DETAIL_FADE := Vector2(4.0, 6.0)
const DETAIL_SIZE := 128
const DETAIL_PERIODS: Array[int] = [4, 8, 16, 32]
const DETAIL_SEED := 1341
const DETAIL_NORMAL_STRENGTH := 3.0
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
	Vector3(0.85, 0.85, 0.8),
]
## Added to each 8-bit colour level so the truncating conversion keeps the intended level.
const COLOR_QUANT_BIAS := 0.25

## Generated once per run: the ground detail texture.
static var _detail: ImageTexture


## Adds the triangle surface of `arrays` with the per-vertex ground weights `weights`
## (TerrainSplat.LAYER_COUNT per vertex): layers 0-3 in ARRAY_COLOR, 4-6 in ARRAY_CUSTOM0
## (RGBA float: x = layer 4, y = layer 5, z = layer 6 soil; w stays free for TASK-035).
static func add_surface(mesh: ArrayMesh, arrays: Array, weights: PackedFloat32Array) -> void:
	var packed := pack_weights(weights)
	arrays[Mesh.ARRAY_COLOR] = packed[0]
	arrays[Mesh.ARRAY_CUSTOM0] = packed[1]
	var format := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)


## The ground weights as add_surface stores them: [PackedColorArray (layers 0-3),
## PackedFloat32Array (custom0, 4 floats per vertex)]. Pure, so chunk plans run it on the worker
## threads (TerrainChunks).
static func pack_weights(weights: PackedFloat32Array) -> Array:
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
		custom[v * 4 + 2] = weights[o + TerrainSplat.SOIL]
	return [colors, custom]


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
	material.set_shader_parameter(&"normal_rough_ao", maps["normal_rough_ao"])
	material.set_shader_parameter(&"layer_repeat", layer_repeats())
	material.set_shader_parameter(&"layer_repeat_far", layer_repeats(FAR_PATTERN_FACTOR))
	material.set_shader_parameter(&"scale_fade", SCALE_FADE)
	material.set_shader_parameter(&"detail_on", quality.get("terrain_detail", true))
	material.set_shader_parameter(&"detail_map", detail_texture())
	material.set_shader_parameter(&"detail_repeat", MapScale.to_units(DETAIL_METRES))
	material.set_shader_parameter(&"detail_second", DETAIL_SECOND)
	material.set_shader_parameter(&"detail_fade", DETAIL_FADE)
	material.set_shader_parameter(
		&"layer_tint", PackedVector3Array(LookPreset.layer_tints(LAYER_TINTS))
	)
	material.set_shader_parameter(&"anti_tiling", quality.get("terrain_anti_tiling", true))
	material.set_shader_parameter(&"triplanar", quality.get("terrain_triplanar", true))
	material.set_shader_parameter(&"water_level", TerrainSurface.WATER_SURFACE)
	return material


## World units per texture repeat of each ground layer: its real size (x `factor`) through
## MapScale.
static func layer_repeats(factor := 1.0) -> PackedFloat32Array:
	var repeats := PackedFloat32Array()
	for metres in TerrainTextures.SOURCE_METRES:
		repeats.append(MapScale.to_units(metres * factor))
	return repeats


## The ground detail texture (RGBA8, mipmapped): tangent-space normal (OpenGL) in RGB, height in A.
static func detail_texture() -> ImageTexture:
	if _detail == null:
		var heights := DetailTexture.height_map(DETAIL_SIZE, DETAIL_PERIODS, DETAIL_SEED)
		# The octave sum clusters around 0.5: stretch it to the full range (contrast).
		var low := 1.0
		var high := 0.0
		for h in heights:
			low = minf(low, h)
			high = maxf(high, h)
		for i in heights.size():
			heights[i] = (heights[i] - low) / maxf(high - low, 1e-6)
		var image := DetailTexture.normal_image(heights, DETAIL_SIZE, DETAIL_NORMAL_STRENGTH)
		image.clear_mipmaps()
		image.convert(Image.FORMAT_RGBA8)
		for y in DETAIL_SIZE:
			for x in DETAIL_SIZE:
				var c := image.get_pixel(x, y)
				c.a = heights[y * DETAIL_SIZE + x]
				image.set_pixel(x, y, c)
		image.generate_mipmaps()
		_detail = ImageTexture.create_from_image(image)
	return _detail


## Turns the farmland parcels of the shader on with the baked `parcels` (FieldParcels.bake) and
## the crop colours of LookPreset.fields(), or off for null (a map without fields).
static func set_parcels(material: ShaderMaterial, parcels: ParcelMap) -> void:
	material.set_shader_parameter(&"parcels_on", parcels != null)
	var edges := parcels.edges_texture() if parcels != null else null
	material.set_shader_parameter(&"parcel_edges_on", edges != null)
	material.set_shader_parameter(&"parcel_real", edges != null)
	if edges != null:
		material.set_shader_parameter(&"parcel_edges", edges)
		material.set_shader_parameter(&"parcel_mpp", parcels.metres_per_pixel)
		material.set_shader_parameter(
			&"parcel_balk_half_m",
			Vector4(
				0.0,
				RealParcels.balk_half_m(1),
				RealParcels.balk_half_m(2),
				RealParcels.balk_half_m(3)
			)
		)
	material.set_shader_parameter(&"cover_on", parcels != null and parcels.look != null)
	if parcels == null:
		return
	if parcels.look != null:
		var cover := parcels.look.cover
		var codes := Image.create_from_data(
			cover.width, cover.height, false, Image.FORMAT_R8, cover.cells()
		)
		material.set_shader_parameter(&"land_cover", ImageTexture.create_from_image(codes))
		material.set_shader_parameter(
			&"cover_frame", Vector4(cover.origin.x, cover.origin.y, cover.cell_size, 0.0)
		)
	var look := LookPreset.fields()
	var plant := PackedVector3Array()
	var furrow := PackedVector3Array()
	var rows := PackedVector2Array()
	var harvest := PackedVector3Array()
	var ground := PackedFloat32Array()
	var stripes := PackedVector2Array()
	for k in FieldParcels.CROPS.size():
		var entry: Dictionary = look["balk"]
		if k in FieldParcels.CROP_KINDS:
			entry = look["crops"][FieldParcels.CROPS[k]]
		plant.append(_linear(entry["plant"]))
		furrow.append(_linear(entry["furrow"]))
		rows.append(Vector2(entry.get("spacing_m", 1000.0), entry.get("plant_frac", 1.0)))
		harvest.append(_linear(entry.get("harvest", entry["plant"])))
		ground.append(1.0 if entry.get("ground_look", false) else 0.0)
		stripes.append(Vector2(entry.get("stripe_m", 0.0), entry.get("stripe_contrast", 0.0)))
	material.set_shader_parameter(&"parcel_map", parcels.texture())
	var rect := parcels.rect_units()
	material.set_shader_parameter(
		&"parcel_rect",
		Vector4(rect.position.x, rect.position.y, 1.0 / rect.size.x, 1.0 / rect.size.y)
	)
	material.set_shader_parameter(&"metres_per_unit", MapScale.metres_per_unit)
	material.set_shader_parameter(&"crop_plant", plant)
	material.set_shader_parameter(&"crop_furrow", furrow)
	material.set_shader_parameter(&"crop_row", rows)
	material.set_shader_parameter(&"crop_stripe", stripes)
	_set_true_look(material, look, rect, harvest, ground)
	material.set_shader_parameter(&"parcel_brightness", look["parcel_brightness"])
	material.set_shader_parameter(&"parcel_hue", look["parcel_hue"])
	material.set_shader_parameter(&"row_fade", Vector2(look["row_fade_from"], look["row_fade_to"]))
	# Same limit as the grass: ground steeper than GrassPlanner.MAX_SLOPE stays bare.
	var steep := 1.0 - 1.0 / sqrt(1.0 + GrassPlanner.MAX_SLOPE * GrassPlanner.MAX_SLOPE)
	material.set_shader_parameter(&"parcel_slope", Vector2(steep * 0.75, steep * 1.3))
	if edges != null and VisualScale.is_true_size():
		# Real parcels (TASK-215b): strong own colours, only a little of the satellite's hue.
		var real_look := RealParcelLook.load_default()
		material.set_shader_parameter(&"crop_tint", real_look.crop_tint)
		material.set_shader_parameter(&"crop_saturation", real_look.crop_saturation)
		material.set_shader_parameter(&"parcel_satellite_hue", real_look.satellite_hue)


## The `true` farmland look of TASK-200 (CropLook twins): off for `balanced`, where the shader
## branches stay out and the parcels render as before. Distances in metres through MapScale.
static func _set_true_look(
	material: ShaderMaterial,
	look: Dictionary,
	rect: Rect2,
	harvest: PackedVector3Array,
	ground: PackedFloat32Array
) -> void:
	var on := VisualScale.is_true_size()
	material.set_shader_parameter(&"crop_true", on)
	if not on:
		return
	material.set_shader_parameter(&"crop_harvest", harvest)
	material.set_shader_parameter(&"crop_ground", ground)
	material.set_shader_parameter(&"crop_tint", look["tint"])
	material.set_shader_parameter(&"crop_saturation", look["saturation"])
	material.set_shader_parameter(&"crop_mottle", look["mottle"])
	material.set_shader_parameter(
		&"crop_mottle_frequency", 1.0 / MapScale.to_units(look["mottle_period_m"])
	)
	material.set_shader_parameter(&"harvest_share", look["harvest_share"])
	material.set_shader_parameter(
		&"row_distance_m", Vector2(look["row_full_m"], look["row_zero_m"])
	)
	var headland := MapScale.to_units(look["headland_m"])
	material.set_shader_parameter(
		&"headland_uv", Vector2(headland / rect.size.x, headland / rect.size.y)
	)
	material.set_shader_parameter(&"headland_m", look["headland_m"])
	material.set_shader_parameter(&"headland_dark", look["headland_dark"])
	material.set_shader_parameter(&"headland_fade_m", look["headland_fade_m"])


static func _linear(color: Color) -> Vector3:
	var c := color.srgb_to_linear()
	return Vector3(c.r, c.g, c.b)
