class_name LoadingScreen
extends ColorRect
## Full-screen loading notice (HUD v3 "06 Notices"): `OPERACJA` amber, the operation name at
## 34 px, a 220×6 progress bar (amber hatch filling a dim track, never moving backwards) and a
## mono status line. The battle scene shows it while it builds, reports set_progress() per stage
## and calls finish() when done; finish() frees it at once. Blocks nothing after that.

const NAME_SIZE := 34
const HATCH_SIZE := Vector2(220, 6)
const TRACK_ALPHA := 0.16
## The share of the whole bar the scene load (SceneLoader) covers; the battle's own build
## continues from here, so the hand-over does not make the bar jump back.
const SCENE_LOAD_SHARE := 0.08

var _operation: Label
var _status: Label
var _fill: Control
var _progress := 0.0


func _init() -> void:
	name = "LoadingScreen"
	z_index = 100  # HUD widgets are added while it is up and must not draw over it
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind may be clicked while loading
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	color = UiPalette.BG_APP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 12)
	centre.add_child(column)
	var caption := _label(HudTheme.mono(600, 5), 11, UiPalette.AMBER)
	caption.text = tr("OPERATION").to_upper()
	column.add_child(caption)
	_operation = _label(HudTheme.display(700, 3), NAME_SIZE, UiPalette.HUD_TEXT)
	_operation.name = "OperationName"
	column.add_child(_operation)
	var bar := Control.new()
	bar.name = "ProgressBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = HATCH_SIZE
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bar)
	var track := ColorRect.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.color = Color(UiPalette.AMBER, TRACK_ALPHA)
	track.size = HATCH_SIZE
	bar.add_child(track)
	_fill = Control.new()
	_fill.name = "Fill"
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.clip_contents = true
	_fill.size = Vector2(0.0, HATCH_SIZE.y)
	bar.add_child(_fill)
	_fill.add_child(HatchBar.new(UiPalette.AMBER, HATCH_SIZE, true))
	_status = _label(HudTheme.mono(500, 1), 10, UiPalette.HUD_MUTED)
	_status.name = "Status"
	column.add_child(_status)


## `operation_name` is an untranslated name ("" falls back to the game title).
func set_operation(operation_name: String) -> void:
	var text := operation_name if operation_name != "" else "Eastern Flank"
	_operation.text = tr(text).to_upper()


## `status` is a translation key.
func set_status(status: String) -> void:
	_status.text = tr(status).to_upper()


## Fills the bar to `fraction` (0..1) of its width. The bar never moves backwards: a stage that
## discovers more work than it counted just stalls it.
func set_progress(fraction: float) -> void:
	_progress = maxf(_progress, clampf(fraction, 0.0, 1.0))
	_fill.size.x = HATCH_SIZE.x * _progress


func progress() -> float:
	return _progress


func operation_text() -> String:
	return _operation.text


func status_text() -> String:
	return _status.text


## The scene is built: remove the screen.
func finish() -> void:
	hide()
	queue_free()


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label
