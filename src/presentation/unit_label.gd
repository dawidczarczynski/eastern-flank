class_name UnitLabel
extends PanelContainer
## The unit marker (TASK-111): a compact fixed-pixel tag – faction tab, class icon
## (UnitClassIcon), abbreviation and HP bar (HUD Control) – anchored ANCHOR_OFFSET px above the
## screen position of the unit's ground point, so it reads at every zoom and does not move with the
## model scale. Style from docs/design (scene.js "units" labels). Positioned by the owner via
## place(); overlap_shifts / pick are the owner's layout and click helpers.

const BACKGROUND := Color(14 / 255.0, 16 / 255.0, 13 / 255.0, 0.82)
const BORDER := Color(1.0, 1.0, 1.0, 0.14)
const TRACK := Color(1.0, 1.0, 1.0, 0.15)
const TAB_SIZE := Vector2(4, 15)
const BAR_WIDTH := 26
const BAR_HEIGHT := 4
const GAP := 5
const ICON_GAP := 4
const DONE_OPACITY := 0.55
## Pixels between the ground point's screen position and the marker's bottom edge.
const ANCHOR_OFFSET := 18.0

## Pixels the owner moved this marker up to clear a closer one (overlap_shifts), kept by place().
var shift := 0.0

var _tab := ColorRect.new()
var _icon := UnitClassIcon.new()
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

	# The icon sits ICON_GAP after the tab (the row's GAP is the separation of the other parts).
	var lead := HBoxContainer.new()
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lead.add_theme_constant_override(&"separation", ICON_GAP)
	lead.add_child(_icon)
	_text.theme_type_variation = &"UnitTagLabel"
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lead.add_child(_text)
	row.add_child(lead)

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


func setup(
	short_name: String, faction_color: Color, hp: int, max_hp: int, unit_class := &""
) -> void:
	_text.text = short_name
	_tab.color = faction_color
	_icon.setup(unit_class, faction_color)
	set_hp(hp, max_hp)


func class_icon() -> UnitClassIcon:
	return _icon


func set_hp(hp: int, max_hp: int) -> void:
	_fill.size = Vector2(UnitStatus.hp_fill_width(hp, max_hp, BAR_WIDTH), BAR_HEIGHT)
	_fill.color = UiPalette.hp_color(hp, max_hp)
	size = get_combined_minimum_size()


func set_done(done: bool) -> void:
	modulate.a = DONE_OPACITY if done else 1.0


## Screen point of the marker's bottom centre for a unit whose ground point projects to
## `ground_screen` (Camera3D.unproject_position).
static func anchor(ground_screen: Vector2) -> Vector2:
	return ground_screen - Vector2(0.0, ANCHOR_OFFSET)


## The marker's screen rectangle (before the overlap shift) for that anchor.
func rect_at(anchor_point: Vector2) -> Rect2:
	return Rect2(anchor_point - Vector2(size.x / 2.0, size.y), size)


## Puts the label ANCHOR_OFFSET px above the screen projection of `ground_point` (moved up by
## `shift`); hidden when the point is behind the camera (or there is no camera).
func place(camera: Camera3D, ground_point: Vector3) -> void:
	if camera == null or camera.is_position_behind(ground_point):
		visible = false
		return
	place_at(camera.unproject_position(ground_point))


## place() for a ground point already projected to `ground_screen`.
func place_at(ground_screen: Vector2) -> void:
	visible = true
	position = (rect_at(anchor(ground_screen)).position - Vector2(0.0, shift)).round()


## Overlap layout: markers in order of `depths` (distance to the camera, closest first) keep their
## place unless they overlap a closer one (where it is drawn); then they move up by their height,
## once (at most one shift step, so a crowd may still overlap, but no marker is ever hidden).
## Returns the upward shift in pixels per rect.
static func overlap_shifts(rects: Array[Rect2], depths: Array) -> PackedFloat32Array:
	var order: Array[int] = []
	for i in rects.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return depths[a] < depths[b])
	var shifts := PackedFloat32Array()
	shifts.resize(rects.size())
	var kept: Array[Rect2] = []
	for i in order:
		var hit := false
		for other in kept:
			if rects[i].intersects(other):
				hit = true
				break
		if hit:
			shifts[i] = rects[i].size.y
		# Where the marker ends up blocks the farther ones (they test their own unshifted place).
		kept.append(rects[i].grow_side(SIDE_TOP, shifts[i]).grow_side(SIDE_BOTTOM, -shifts[i]))
	return shifts


## Index of the marker under `point` (the closest to the camera when several are), or -1.
static func pick(rects: Array[Rect2], depths: Array, point: Vector2) -> int:
	var best := -1
	for i in rects.size():
		if rects[i].has_point(point) and (best < 0 or depths[i] < depths[best]):
			best = i
	return best
