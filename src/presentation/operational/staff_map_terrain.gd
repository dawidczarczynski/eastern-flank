class_name StaffMapTerrain
extends RefCounted
## The staff map's terrain from real geography (TASK-126, ADR 0018 "Graphic layers"): the map's
## water / cover / relief layers as GPU textures, built once at load, and the material that
## combines them (assets/shaders/staff_map_terrain.gdshader). Nothing here reads the hex terrain.
## `mask_at` is the CPU mirror of the shader's bilinear mask (tests sample the drawn coast with it).

const SHADER := preload("res://assets/shaders/staff_map_terrain.gdshader")

var water_texture: ImageTexture
var cover_texture: ImageTexture
var relief_texture: ImageTexture
var material: ShaderMaterial
## World rectangles (x east, y = world z south) of the water / cover and of the relief pixels.
var layer_rect := Rect2()
var relief_rect := Rect2()
var _water: Image


## Null when the map has no graphic layers or one does not decode (the caller falls back to the
## v0 hex look).
static func from_map(map: ImportedMap, palette: StaffMapPalette) -> StaffMapTerrain:
	if map == null or not map.has_graphic_layers():
		return null
	var water := map.layer_image(ImportedMap.LAYER_WATER)
	var cover := map.layer_image(ImportedMap.LAYER_COVER)
	var relief := map.layer_image(ImportedMap.LAYER_RELIEF)
	if water == null or cover == null or relief == null:
		return null
	var terrain := StaffMapTerrain.new()
	terrain._water = water
	terrain.layer_rect = map.layer_world_rect(ImportedMap.LAYER_WATER)
	terrain.relief_rect = map.layer_world_rect(ImportedMap.LAYER_RELIEF)
	terrain.water_texture = ImageTexture.create_from_image(water)
	terrain.cover_texture = ImageTexture.create_from_image(cover)
	terrain.relief_texture = ImageTexture.create_from_image(relief)
	terrain.material = terrain._material(palette)
	return terrain


## The water mask at a world point as the shader samples it (four bilinear taps half a pixel
## apart, 0 land .. 1 water); the drawn shoreline is its 0.5 contour.
func water_at(world: Vector2) -> float:
	var o := layer_rect.size / Vector2(_water.get_width(), _water.get_height()) * 0.5
	var sum := 0.0
	for offset in [Vector2(-o.x, -o.y), Vector2(o.x, -o.y), Vector2(-o.x, o.y), o]:
		sum += mask_at(_water, layer_rect, world + offset)
	return sum * 0.25


## Bilinear value (0..1) of an L8 `image` covering world rectangle `rect` at `world`, clamped to
## the edge pixels like the shader's repeat_disable sampler.
static func mask_at(image: Image, rect: Rect2, world: Vector2) -> float:
	var size := Vector2(image.get_width(), image.get_height())
	var p := (world - rect.position) / rect.size * size - Vector2(0.5, 0.5)
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	var top := lerpf(_texel(image, i), _texel(image, i + Vector2i(1, 0)), f.x)
	var bottom := lerpf(_texel(image, i + Vector2i(0, 1)), _texel(image, i + Vector2i(1, 1)), f.x)
	return lerpf(top, bottom, f.y)


static func _texel(image: Image, at: Vector2i) -> float:
	var x := clampi(at.x, 0, image.get_width() - 1)
	var y := clampi(at.y, 0, image.get_height() - 1)
	return image.get_pixel(x, y).r


func _material(palette: StaffMapPalette) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"water_tex", water_texture)
	m.set_shader_parameter(&"cover_tex", cover_texture)
	m.set_shader_parameter(&"relief_tex", relief_texture)
	m.set_shader_parameter(
		&"layer_rect",
		Vector4(layer_rect.position.x, layer_rect.position.y, layer_rect.size.x, layer_rect.size.y)
	)
	m.set_shader_parameter(
		&"relief_rect",
		Vector4(
			relief_rect.position.x, relief_rect.position.y, relief_rect.size.x, relief_rect.size.y
		)
	)
	m.set_shader_parameter(&"land_color", palette.map_land)
	m.set_shader_parameter(&"forest_color", palette.map_forest)
	m.set_shader_parameter(&"forest_edge_color", palette.map_forest_edge)
	m.set_shader_parameter(&"urban_color", palette.map_urban)
	m.set_shader_parameter(&"urban_edge_color", palette.map_urban_edge)
	m.set_shader_parameter(&"water_color", palette.water_lake)
	m.set_shader_parameter(&"shore_color", palette.water_shore)
	m.set_shader_parameter(&"marsh_color", palette.map_marsh)
	m.set_shader_parameter(&"cover_urban", ImportedMap.COVER_URBAN)
	m.set_shader_parameter(&"cover_forest", ImportedMap.COVER_FOREST)
	m.set_shader_parameter(&"cover_marsh", ImportedMap.COVER_MARSH)
	m.set_shader_parameter(&"relief_flat", ImportedMap.RELIEF_FLAT / 255.0)
	m.set_shader_parameter(&"shade_strength", palette.hillshade_strength)
	m.set_shader_parameter(&"hatch_tile_px", palette.marsh_hatch_tile)
	return m
