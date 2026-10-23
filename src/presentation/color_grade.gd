class_name ColorGrade
extends RefCounted
## Colour grade of the battle scene (TASK-051): muted, slightly olive military palette.
## `grade()` is a pure per-colour function; `lut()` bakes it into 3D LUT slices that
## `Environment.adjustment_color_correction` applies after tonemapping (the HUD is not graded).

const DEFAULT := {
	"saturation": 0.92,
	"contrast": 1.06,
	"shadow_tint": Color("#1e2a2c"),
	"shadow_weight": 0.06,
	"highlight_tint": Color("#fff1dc"),
	"highlight_weight": 0.05,
	# Hue shift (0..1 wheel) applied to greens only; negative = toward yellow/olive.
	"green_shift": -0.02,
}

const LUT_SIZE := 17
const GREEN_HUE := 0.28
const GREEN_HUE_RANGE := 0.16

static var _cached: ImageTexture3D


static func _luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Order: contrast around 0.5 -> saturation toward luminance -> green shift -> split tint -> clamp.
static func grade(c: Color, p: Dictionary) -> Color:
	var contrast: float = p["contrast"]
	var out := Color(
		(c.r - 0.5) * contrast + 0.5, (c.g - 0.5) * contrast + 0.5, (c.b - 0.5) * contrast + 0.5
	)
	var lum := _luminance(out)
	var sat: float = p["saturation"]
	out = Color(lerpf(lum, out.r, sat), lerpf(lum, out.g, sat), lerpf(lum, out.b, sat)).clamp()
	var shift: float = p["green_shift"]
	if shift != 0.0 and out.s > 0.001:
		var weight := clampf(1.0 - absf(out.h - GREEN_HUE) / GREEN_HUE_RANGE, 0.0, 1.0)
		out.h = fposmod(out.h + shift * weight, 1.0)
	lum = clampf(_luminance(out), 0.0, 1.0)
	var shadow: Color = p["shadow_tint"]
	var highlight: Color = p["highlight_tint"]
	var sw: float = float(p["shadow_weight"]) * (1.0 - lum)
	var hw: float = float(p["highlight_weight"]) * lum
	out = out.lerp(shadow, sw).lerp(highlight, hw)
	return Color(clampf(out.r, 0.0, 1.0), clampf(out.g, 0.0, 1.0), clampf(out.b, 0.0, 1.0), 1.0)


## `size` slices (blue axis) of size x size images (x = red, y = green) for ImageTexture3D.create.
static func lut(size: int, p: Dictionary) -> Array[Image]:
	var slices: Array[Image] = []
	var last := float(size - 1)
	for b in size:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for g in size:
			for r in size:
				img.set_pixel(r, g, grade(Color(r / last, g / last, b / last), p))
		slices.append(img)
	return slices


## The default grade as a 3D texture, built once.
static func cached_texture() -> ImageTexture3D:
	if _cached == null:
		var tex := ImageTexture3D.new()
		var slices := lut(LUT_SIZE, LookPreset.grade(DEFAULT))
		tex.create(Image.FORMAT_RGBA8, LUT_SIZE, LUT_SIZE, LUT_SIZE, false, slices)
		_cached = tex
	return _cached


## Drops the baked texture (the active LookPreset changed).
static func reset_cache() -> void:
	_cached = null


static func apply_to(env: Environment) -> void:
	env.adjustment_enabled = true
	env.adjustment_color_correction = cached_texture()
