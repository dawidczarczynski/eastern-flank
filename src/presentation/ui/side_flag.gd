class_name SideFlag
extends Control
## Flat flag of a side (TASK-127) with a 1 px frame in the side colour; drawn from
## `SideDefinition.flag`. Hidden and out of the layout when the side has no flag.

const SMALL := Vector2(24, 18)
const LARGE := Vector2(40, 30)
## Turn bar: replaces the faction badge.
const BAR := Vector2(48, 36)

## Flags are rasterised from their SVG at this multiple of the display size (with mipmaps and
## linear filtering) – the import's single big raster aliases when scaled down.
const OVERSAMPLE := 2.0

static var _baked: Dictionary = {}

var texture: Texture2D
var frame_colour := UiPalette.LINE
var _shown: Texture2D


func _init(p_size := SMALL) -> void:
	name = "Flag"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = p_size
	hide()


## Shows `side`'s flag framed in `colour`; hides when there is none.
func setup(side: SideDefinition, colour := UiPalette.LINE) -> void:
	texture = side.flag if side != null else null
	_shown = _bake(texture, custom_minimum_size)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	frame_colour = colour
	visible = texture != null
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	draw_texture_rect(_shown, Rect2(Vector2.ZERO, size), false)
	draw_rect(Rect2(Vector2.ZERO, size), frame_colour, false, 1.0)


## `source` drawn from its SVG at OVERSAMPLE × `display` px with mipmaps; `source` itself when it
## is not an SVG or cannot be rasterised. Cached per file and size.
static func _bake(source: Texture2D, display: Vector2) -> Texture2D:
	if source == null:
		return null
	var path := source.resource_path
	var key := "%s@%d" % [path, int(display.x)]
	if _baked.has(key):
		return _baked[key]
	var baked := source
	if path.ends_with(".svg"):
		var text := FileAccess.get_file_as_string(path)
		var image := Image.new()
		var wide := float(source.get_width())
		if not text.is_empty() and wide > 0.0:
			var scale := display.x * OVERSAMPLE / wide
			if image.load_svg_from_string(text, scale) == OK:
				image.generate_mipmaps()
				baked = ImageTexture.create_from_image(image)
	_baked[key] = baked
	return baked
