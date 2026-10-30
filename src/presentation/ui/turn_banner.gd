class_name TurnBanner
extends Control
## Turn / result banner (HUD v3 "06 Notices"): a full-width horizontal fade band
## rgba(8,11,8,.88) between two 420 px wide-hatch bars, a mono caption (`TURN 03 // ...`) and the
## faction name in its colour (40 px). Starts at 36 % of the screen height, ignores the mouse.
## A timed banner hides itself after `SECONDS`; a held one (the result) stays until released.

const SECONDS := 1.5
const TOP_ANCHOR := 0.36
const BAR_SIZE := Vector2(420, 4)
const NAME_SIZE := 40
const CAPTION_SIZE := 12
const SUBTITLE_SIZE := 13

var held := false
var _remaining := 0.0
var _caption: Label
var _name: Label
var _subtitle: Label  # the result's reason (TASK-088); hidden when empty


func _init() -> void:
	name = "TurnBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = TOP_ANCHOR
	anchor_bottom = TOP_ANCHOR
	grow_vertical = Control.GROW_DIRECTION_END
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 0)
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(column)
	column.add_child(_bar("TopBar"))
	var band := PanelContainer.new()
	band.name = "Band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxTexture.new()
	style.texture = _band_texture()
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	band.add_theme_stylebox_override(&"panel", style)
	column.add_child(band)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_theme_constant_override(&"separation", 4)
	band.add_child(texts)
	_caption = _label(HudTheme.mono(500, 3), CAPTION_SIZE, UiPalette.HUD_MUTED)
	_caption.name = "Caption"
	texts.add_child(_caption)
	_name = _label(HudTheme.display(700, 4), NAME_SIZE, UiPalette.HUD_TEXT)
	_name.name = "FactionName"
	texts.add_child(_name)
	_subtitle = _label(HudTheme.mono(600, 3), SUBTITLE_SIZE, UiPalette.HUD_DESC)
	_subtitle.name = "Subtitle"
	_subtitle.hide()
	texts.add_child(_subtitle)
	column.add_child(_bar("BottomBar"))
	set_process(false)
	hide()


## Shows the banner for SECONDS (a running countdown restarts). Texts are already translated.
func show_timed(caption: String, title: String, color: Color) -> void:
	held = false
	_set_texts(caption, title, color, "")
	_remaining = SECONDS
	show()
	set_process(true)


## Shows the banner until release() (the victory / defeat / draw banner); `subtitle` (already
## translated, "" = none) is a line under the title.
func show_held(caption: String, title: String, color: Color, subtitle := "") -> void:
	_set_texts(caption, title, color, subtitle)
	held = true
	_remaining = 0.0
	show()
	set_process(false)


## Hides a held banner (a new match / state); a timed one is left to its countdown.
func release() -> void:
	if held:
		held = false
		hide()


## Seconds the timed banner has left (0 when hidden or held).
func remaining() -> float:
	return _remaining


func caption_text() -> String:
	return _caption.text


func title_text() -> String:
	return _name.text


func subtitle_text() -> String:
	return _subtitle.text if _subtitle.visible else ""


func advance(delta: float) -> void:
	if held or _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_remaining = 0.0
		hide()
		set_process(false)


func _process(delta: float) -> void:
	advance(delta)


func _set_texts(caption: String, title: String, color: Color, subtitle: String) -> void:
	_caption.text = caption
	_name.text = title
	_name.add_theme_color_override(&"font_color", color)
	_subtitle.text = subtitle
	_subtitle.visible = subtitle != ""


func _bar(bar_name: String) -> Control:
	var bar := HatchBar.new(UiPalette.AMBER, BAR_SIZE, true)
	bar.name = bar_name
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return bar


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label


static func _band_texture() -> GradientTexture2D:
	var edge := Color(UiPalette.BANNER_BAND, 0.0)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	gradient.colors = PackedColorArray([edge, UiPalette.BANNER_BAND, UiPalette.BANNER_BAND, edge])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0)
	texture.width = 256
	texture.height = 4
	return texture
