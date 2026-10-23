class_name ScreenDecor
extends ColorRect
## Full-screen decoration of the HUD v3 look: vignette, scanlines and amber corner brackets,
## drawn by one canvas_item shader (assets/shaders/screen_decor.gdshader) on a single quad.
## Sits above the 3D view and below the HUD panels; ignores the mouse and never takes layout space.

const SHADER := preload("res://assets/shaders/screen_decor.gdshader")

var _material: ShaderMaterial


func _init() -> void:
	name = "ScreenDecor"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	color = Color.WHITE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"vignette_alpha", UiPalette.VIGNETTE_EDGE.a)
	_material.set_shader_parameter(&"scanline_alpha", UiPalette.SCANLINE.a)
	_material.set_shader_parameter(&"bracket_color", UiPalette.SCREEN_BRACKET)
	material = _material
	resized.connect(_on_resized)


func _ready() -> void:
	_on_resized()


func _on_resized() -> void:
	_material.set_shader_parameter(&"rect_size", size)
