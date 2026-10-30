class_name TargetTag
extends FramedPanel
## Compact attack forecast beside the cursor (TASK-089b) while the hovered enemy is a valid target
## of the selected unit: ATTACK ~4.0 (2–6) · DESTROY <1 % · COUNTER ~0.6 / NO COUNTER, from
## HudModel.attack_tag lines {label, value} (labels translated here). Replaces the hover card for
## a valid target. Ignores the mouse.

const OFFSET := Vector2(22, 18)
const EDGE := 8.0

var _grid: GridContainer


func _init() -> void:
	super()
	name = "TargetTag"
	chamfers = Vector4(8, 0, 8, 0)
	fill = UiPalette.PANEL_STRONG
	line_color = UiPalette.AMBER_BORDER
	padding = Vector2(9, 6)
	_grid = GridContainer.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.columns = 2
	_grid.add_theme_constant_override(&"h_separation", 12)
	_grid.add_theme_constant_override(&"v_separation", 2)
	add_child(_grid)
	hide()


## Top-left of a `tag` sized tag for the cursor at `mouse`: below-right of it, flipped left / up
## when it would leave the viewport.
static func placement(mouse: Vector2, viewport: Vector2, tag: Vector2) -> Vector2:
	var x := mouse.x + OFFSET.x
	if x + tag.x > viewport.x - EDGE:
		x = mouse.x - OFFSET.x - tag.x
	var y := mouse.y + OFFSET.y
	if y + tag.y > viewport.y - EDGE:
		y = mouse.y - OFFSET.y - tag.y
	return Vector2(maxf(x, EDGE), maxf(y, EDGE))


func show_lines(lines: Array[Dictionary]) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for line in lines:
		var value := String(line["value"])
		var caption := _label(HudTheme.mono(600, 1), 10, UiPalette.AMBER)
		caption.text = tr(String(line["label"])).to_upper()
		if value == "":
			caption.add_theme_color_override(&"font_color", UiPalette.HUD_MUTED)
		var text := _label(HudTheme.mono(600), 12, UiPalette.HUD_TEXT)
		text.text = value
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_grid.add_child(caption)
		_grid.add_child(text)
	reset_size()


func tag_size() -> Vector2:
	return get_combined_minimum_size()


func _label(font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label
