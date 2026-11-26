class_name CropLook
extends RefCounted
## The `true` farmland look of TASK-200 as GDScript twins of what assets/shaders/terrain.gdshader
## does per pixel (tested in tests/unit/test_crop_look.gd): the crop colour tinted towards the
## satellite colour layer, the row strength by camera distance, the headland strip. All distances in
## metres, values from LookPreset.fields(); colours linear unless noted.


## `crop` taken `strength` of the way towards `layer`'s hue at the crop's own luminance.
static func tinted(crop: Color, layer: Color, strength: float) -> Color:
	var target := SatelliteColour.hue(crop, layer)
	return Color(crop.r, crop.g, crop.b).lerp(target, strength)


## Row strength at a camera distance of `distance_m`: 1 below row_full_m, 0 from row_zero_m on
## (smooth between), so no row pattern is left to alias in the distance.
static func row_strength(distance_m: float, values: Dictionary) -> float:
	return 1.0 - smoothstep(values["row_full_m"], values["row_zero_m"], distance_m)


## The (full, zero) camera distances in metres of the crop rows: the preset's row_full_m /
## row_zero_m, with the zero distance capped at `cap_m` when that is > 0 (GraphicsQuality
## "crop_rows_max_m": LOW draws no rows beyond it, only the plain parcel colour). The full distance
## stays below the zero one so the shader's smoothstep keeps a ramp.
static func row_distances(values: Dictionary, cap_m := 0.0) -> Vector2:
	var zero := float(values["row_zero_m"])
	var full := float(values["row_full_m"])
	if cap_m > 0.0 and cap_m < zero:
		zero = cap_m
		full = minf(full, 0.5 * cap_m)
	return Vector2(full, zero)


## The headland darkening factor at `edge_distance_m` from a parcel edge and a camera distance of
## `distance_m`: headland_dark inside the strip (headland_m wide), 1 outside, fading out with the
## camera distance (by headland_fade_m).
static func headland_factor(edge_distance_m: float, distance_m: float, values: Dictionary) -> float:
	if edge_distance_m >= values["headland_m"]:
		return 1.0
	var fade := (
		1.0 - smoothstep(0.5 * values["headland_fade_m"], values["headland_fade_m"], distance_m)
	)
	return lerpf(1.0, values["headland_dark"], fade)


## The albedo of a parcel of the crop `kind_name` over the ground colour `ground`: the ground
## itself for the grass-look kinds (meadow, fallow), else the crop colour `crop`.
static func parcel_albedo(kind_name: StringName, ground: Color, crop: Color) -> Color:
	var entry: CropKind = CropCatalog.load_default().get_kind(kind_name)
	if entry != null and entry.ground_look:
		return ground
	return crop


## Linear luminance of an sRGB colour.
static func luminance(srgb: Color) -> float:
	return SatelliteColour.luma(srgb.srgb_to_linear())
