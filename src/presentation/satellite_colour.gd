class_name SatelliteColour
extends RefCounted
## The satellite colour layer of a battle (TASK-192b, ADR 0031) as the terrain and canopy shaders
## read it (assets/shaders/satellite_colour.gdshaderinc): one sRGB texture over the battle's world
## rectangle, cut from the imported map's ColourRaster or the tactical layer's colour windows.
## Only under the `true` VisualScale preset and only for maps with a layer (`for_map` returns null
## otherwise, and `apply` turns the shader flag off): the `balanced` look is unchanged. The blend
## values are LookPreset.satellite() (metres, converted through MapScale). The static weight / tint
## functions are the GDScript twins of the shader include (tested).

const LUMA := Vector3(0.2126, 0.7152, 0.0722)

## The layer's pixels (sRGB, row 0 north) and the world rectangle (x, z) its outer edges span.
var image: Image
var rect: Rect2
var _texture: ImageTexture


## The layer of a battle's map (BattleSetup.map_id / map_region) with `margin` world units around
## a tactical layer's cut; null when the map has none or the `true` VisualScale preset is off.
static func for_map(map_id: StringName, region: Rect2i, margin: float) -> SatelliteColour:
	if not VisualScale.is_true_size() or map_id == BattleSetup.MAP_GENERATED_RIVER:
		return null
	var layer := TacticalLayer.find(map_id)
	if layer != null:
		return from_layer(layer, region, margin)
	var imported := ImportedMap.find(map_id)
	return from_imported(imported) if imported != null else null


## The whole colour raster of an imported map (world = metres from tile (0, 0)'s centre / scale).
static func from_imported(map: ImportedMap) -> SatelliteColour:
	var raster := map.colour_raster()
	if raster == null:
		return null
	var m := map.metres_per_world_unit()
	var result := SatelliteColour.new()
	result.image = raster.image
	var corner := (raster.origin - Vector2.ONE * raster.cell_m * 0.5) / m
	result.rect = Rect2(corner, Vector2(raster.size()) * raster.cell_m / m)
	return result


## The pixels of a tactical layer's colour raster under the cut `region` (offset tiles; the cut's
## tile (0, 0) is the world origin, as LandCover's cut) plus `margin` world units, clamped to the
## raster; null without a colour layer or for a region that cannot be cut.
static func from_layer(layer: TacticalLayer, region: Rect2i, margin: float) -> SatelliteColour:
	if not layer.has_colour_layer() or layer.region_problem(region) != "":
		return null
	var m := layer.metres_per_world_unit()
	var c := layer.colour_cell_m
	var corner := Hex.to_world(
		MapGenerator.offset_to_axial(region.position.x, region.position.y), TerrainField.HEX_SIZE
	)
	var half := Hex.SQRT3 * 0.5
	var world := Rect2(
		-half - margin,
		-1.0 - margin,
		Hex.SQRT3 * region.size.x + half + 2.0 * margin,
		1.5 * (region.size.y - 1) + 2.0 + 2.0 * margin
	)
	# Global raster pixel (i, j) centre in metres from the layer's tile (0, 0): (east, south).
	var east0 := layer.colour_origin_easting - layer.origin_easting
	var south0 := layer.origin_northing - layer.colour_origin_northing
	var i0 := clampi(
		floori(((corner.x + world.position.x) * m - east0) / c), 0, layer.colour_width - 1
	)
	var i1 := clampi(ceili(((corner.x + world.end.x) * m - east0) / c), i0, layer.colour_width - 1)
	var j0 := clampi(
		floori(((corner.z + world.position.y) * m - south0) / c), 0, layer.colour_height - 1
	)
	var j1 := clampi(
		ceili(((corner.z + world.end.y) * m - south0) / c), j0, layer.colour_height - 1
	)
	var size := Vector2i(i1 - i0 + 1, j1 - j0 + 1)
	var pixels := Image.create(size.x, size.y, false, Image.FORMAT_RGB8)
	for j in size.y:
		var z_m := south0 + (j0 + j) * c
		for i in size.x:
			pixels.set_pixel(i, j, layer.sample(east0 + (i0 + i) * c, z_m))
	var result := SatelliteColour.new()
	result.image = pixels
	var west_m := east0 + (i0 - 0.5) * c
	var north_m := south0 + (j0 - 0.5) * c
	result.rect = Rect2(
		Vector2(west_m / m - corner.x, north_m / m - corner.z), Vector2(size) * c / m
	)
	return result


## The sRGB layer colour at world (x, z), bilinear between pixel centres (the shader samples the
## same texture; tests and tools read it here).
func sample_world(x: float, z: float) -> Color:
	var cell := rect.size.x / image.get_width()
	var raster := ColourRaster.from_image(image, cell, rect.position + Vector2.ONE * cell * 0.5)
	return raster.sample(x, z)


## The mipmapped texture of the layer (built once).
func texture() -> ImageTexture:
	if _texture == null:
		var mipmapped := image.duplicate() as Image
		mipmapped.generate_mipmaps()
		_texture = ImageTexture.create_from_image(mipmapped)
	return _texture


## GPU bytes of the texture: RGBA8 (RGB8 is padded on upload) with its mip chain.
func gpu_bytes() -> int:
	var total := 0
	var w := image.get_width()
	var h := image.get_height()
	while true:
		total += w * h * 4
		if w == 1 and h == 1:
			break
		w = maxi(w / 2, 1)
		h = maxi(h / 2, 1)
	return total


## Turns the satellite blend of a terrain or canopy material on with `colour` and the values of
## LookPreset.satellite() (metres through MapScale), or off for null / outside the `true`
## VisualScale preset (the shader then renders exactly as without the layer).
static func apply(material: ShaderMaterial, colour: SatelliteColour) -> void:
	var on := colour != null and VisualScale.is_true_size()
	material.set_shader_parameter(&"satellite_on", on)
	if not on:
		return
	var values := LookPreset.satellite()
	material.set_shader_parameter(&"satellite_map", colour.texture())
	var r := colour.rect
	material.set_shader_parameter(
		&"satellite_rect", Vector4(r.position.x, r.position.y, 1.0 / r.size.x, 1.0 / r.size.y)
	)
	var edge := MapScale.to_units(values["edge_m"])
	material.set_shader_parameter(
		&"satellite_edge", Vector2(maxf(edge / r.size.x, 1e-6), maxf(edge / r.size.y, 1e-6))
	)
	material.set_shader_parameter(&"satellite_near_tint", values["near_tint"])
	material.set_shader_parameter(
		&"satellite_blend",
		Vector2(
			MapScale.to_units(values["blend_start_m"]), MapScale.to_units(values["blend_end_m"])
		)
	)
	material.set_shader_parameter(&"satellite_gain", values["gain"])
	material.set_shader_parameter(&"satellite_saturation", values["saturation"])
	material.set_shader_parameter(&"satellite_canopy_hue", values["canopy_hue"])


## satellite_far: how far the layer has taken over at a view distance of `distance_m`.
static func far_share(distance_m: float, values: Dictionary) -> float:
	return smoothstep(values["blend_start_m"], values["blend_end_m"], distance_m)


## satellite_weight: the layer's weight at `distance_m` (the near tint up to the blend start, 1
## beyond its end).
static func weight(distance_m: float, values: Dictionary) -> float:
	return lerpf(values["near_tint"], 1.0, far_share(distance_m, values))


static func luma(c: Color) -> float:
	return Vector3(c.r, c.g, c.b).dot(LUMA)


## satellite_hue: `layer`'s hue and saturation at `base`'s luminance (linear colours).
static func hue(base: Color, layer: Color) -> Color:
	var k := luma(base) / maxf(luma(layer), 1e-4)
	return Color(layer.r * k, layer.g * k, layer.b * k)


## satellite_ground: the ground colour (linear) at `distance_m` for the splat / parcel colour
## `base` and the layer colour `layer` of coverage `coverage`.
static func ground(
	base: Color, layer: Color, distance_m: float, values: Dictionary, coverage := 1.0
) -> Color:
	var far := far_share(distance_m, values)
	var target := hue(base, layer).lerp(Color(layer.r, layer.g, layer.b), far)
	return Color(base.r, base.g, base.b).lerp(target, weight(distance_m, values) * coverage)


## The canopy crown colour (canopy.gdshader): `base` taken towards the layer's hue by its weight
## at `distance_m` x `canopy_hue`, at the crown's own luminance.
static func canopy(base: Color, layer: Color, distance_m: float, values: Dictionary) -> Color:
	var w := weight(distance_m, values) * float(values["canopy_hue"])
	return Color(base.r, base.g, base.b).lerp(hue(base, layer), w)
