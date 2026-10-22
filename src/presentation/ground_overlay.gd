class_name GroundOverlay
extends RefCounted
## The material of every ground overlay draped on the terrain (unit marker rings and fills,
## reach / range / attack / hover washes; TASK-057). Rings and outlines are pulled towards the
## camera so they draw over the grass (assets/shaders/ground_overlay.gdshader); fills are not
## (they lie under the unit models, and a pull would tint the lower half of a model) – instead
## they tint only the terrain, not the wheels, tracks, boots or grass standing in them.
## Colour and alpha are the `albedo` uniform: use `set_color` / `color_of`.

const SHADER := preload("res://assets/shaders/ground_overlay.gdshader")


## A new overlay material with `color` (alpha included); `pulled` = false for fills.
static func material(color: Color, pulled := true) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter(&"depth_pull", depth_pull() if pulled else 0.0)
	result.set_shader_parameter(&"ground_only", not pulled)
	result.set_shader_parameter(&"albedo", color)
	return result


static func set_color(overlay: ShaderMaterial, color: Color) -> void:
	overlay.set_shader_parameter(&"albedo", color)


static func color_of(overlay: ShaderMaterial) -> Color:
	return overlay.get_shader_parameter(&"albedo")


## View-ray distance that lifts an overlay above the tallest grass clump at the lowest default
## camera pitch (CameraMath.PITCH_CLOSE; a player tilt towards the horizon can let grass poke
## through slightly): the vertical gain of pulling by d along the ray is d * sin(pitch).
static func depth_pull() -> float:
	return GrassField.max_clump_height() / sin(CameraMath.PITCH_CLOSE)
