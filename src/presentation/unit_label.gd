class_name UnitLabel
extends PanelContainer
## Compact tag floating above a unit: faction tab, abbreviation and HP bar (HUD Control).
## Style from docs/design (scene.js "units" labels). Positioned by the owner via place().

const BACKGROUND := Color(14 / 255.0, 16 / 255.0, 13 / 255.0, 0.82)
const BORDER := Color(1.0, 1.0, 1.0, 0.14)
const TRACK := Color(1.0, 1.0, 1.0, 0.15)
const TAB_SIZE := Vector2(4, 15)
const BAR_WIDTH := 26
const BAR_HEIGHT := 4
const GAP := 5
const DONE_OPACITY := 0.55

var _tab := ColorRect.new()
var _fill := ColorRect.new()
var _text := Label.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.set_border_width_all(1)
	style.border_color = BORDER
	style.content_margin_left = 2
	style.content_margin_top = 2
	style.content_margin_right = 5
	style.content_margin_bottom = 2
	add_theme_stylebox_override(&"panel", style)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", GAP)
	add_child(row)

	_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab.custom_minimum_size = TAB_SIZE
	row.add_child(_tab)

	_text.theme_type_variation = &"UnitTagLabel"
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(_text)

	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := ColorRect.new()
	track.color = TRACK
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(track)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar.add_child(_fill)
	row.add_child(bar)


func setup(short_name: String, faction_color: Color, hp: int, max_hp: int) -> void:
	_text.text = short_name
	_tab.color = faction_color
	set_hp(hp, max_hp)


func set_hp(hp: int, max_hp: int) -> void:
	_fill.size = Vector2(UnitStatus.hp_fill_width(hp, max_hp, BAR_WIDTH), BAR_HEIGHT)
	_fill.color = UiPalette.hp_color(hp, max_hp)
	size = get_combined_minimum_size()


func set_done(done: bool) -> void:
	modulate.a = DONE_OPACITY if done else 1.0


## Puts the label's bottom centre on the screen projection of `world_point`; hidden when the
## point is behind the camera (or there is no camera).
func place(camera: Camera3D, world_point: Vector3) -> void:
	if camera == null or camera.is_position_behind(world_point):
		visible = false
		return
	visible = true
	var screen := camera.unproject_position(world_point)
	position = (screen - Vector2(size.x / 2.0, size.y)).round()
