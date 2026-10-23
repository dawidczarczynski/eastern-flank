class_name UnitPopup
extends FramedPanel
## HUD v3 unit hover card (TASK-078, docs/design/hud_v3/README.md "02 Unit card"), built in code.
## Content comes from UnitPopupModel (untranslated English keys); this widget translates and
## lays it out. Ignores the mouse. Hidden while `suppressed` (radial menu open).

const WIDTH := 320
const SIDE_MARGIN := 11  # + the 1 px frame = 12 px, so the portrait is 296 px wide
const PORTRAIT_SIZE := Vector2(296, 160)
const PORTRAIT_BG := Color("#1b1f1a")
const SEGMENT_HEIGHT := 8.0
const SEGMENT_GAP := 2.0
const BAR_HEIGHT := 4.0
const BAR_TICK_PERIOD := 10.0
const NAME_SIZE := 21
const FRAME_ALPHA := 0.6

## While true the card stays hidden (the radial menu is open); it reappears on the next
## show_model() after the flag is cleared.
var suppressed := false:
	set(value):
		suppressed = value
		if suppressed:
			hide()

var _portrait: _PortraitView
var _name_label: Label
var _designation_label: Label
var _hp_label: Label
var _segments: _Segments
var _stats: GridContainer
var _tags: HFlowContainer
var _tags_wrap: Control
var _note_wrap: Control
var _note_label: Label
var _dot: _HexDot
var _status_label: Label


## Portrait area: texture covered into the box, scanlines, crosshair and corner brackets.
class _PortraitView:
	extends Control
	var texture: Texture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = PORTRAIT_SIZE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), PORTRAIT_BG)
		if texture != null:
			draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), _cover_region())
		var lines := PackedVector2Array()
		var y := 2.5
		while y < size.y:
			lines.append(Vector2(0, y))
			lines.append(Vector2(size.x, y))
			y += 3.0
		draw_multiline(lines, Color(0, 0, 0, 0.12), 1.0)
		var center := size * 0.5
		var crosshair := Color(UiPalette.AMBER, 0.55)
		draw_arc(center, 23.0, 0.0, TAU, 40, crosshair, 1.0, true)
		var cross := Color(UiPalette.AMBER, 0.4)
		draw_line(center - Vector2(34, 0), center + Vector2(34, 0), cross, 1.0)
		draw_line(center - Vector2(0, 34), center + Vector2(0, 34), cross, 1.0)
		var box := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		for corner in 4:
			var pts := HudShapes.corner_bracket(corner, box.size, 9.0)
			for i in pts.size():
				pts[i] += box.position
			draw_polyline(pts, UiPalette.AMBER, 1.0)

	## Source rect that fills the box without distortion (CSS object-fit: cover).
	func _cover_region() -> Rect2:
		var tex := texture.get_size()
		var scale := maxf(size.x / tex.x, size.y / tex.y)
		var shown := size / scale
		return Rect2((tex - shown) * 0.5, shown)


## One skewed segment per HP point, `colors` left to right.
class _Segments:
	extends Control
	var colors: Array[Color] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, SEGMENT_HEIGHT)

	func _draw() -> void:
		var count := colors.size()
		if count == 0:
			return
		var width := (size.x - SEGMENT_GAP * (count - 1)) / count
		for i in count:
			var poly := HudShapes.skewed_segment(Vector2(width, size.y))
			var dx := i * (width + SEGMENT_GAP)
			for j in poly.size():
				poly[j].x += dx
			draw_colored_polygon(poly, colors[i])


## A 4 px stat bar: track, fill (0..1 of the width) and the 10 px tick gaps over both.
class _Bar:
	extends Control
	var fill := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, BAR_HEIGHT)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.TRACK)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * fill, size.y)), UiPalette.HUD_TEXT)
		var x := BAR_TICK_PERIOD - 1.0
		while x < size.x:
			draw_rect(Rect2(x, 0, 1, size.y), UiPalette.TICK_GAP)
			x += BAR_TICK_PERIOD


## The 8 px hexagon status dot.
class _HexDot:
	extends Control
	var color := UiPalette.HUD_MUTED

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(9, 8)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		draw_colored_polygon(HudShapes.hex_badge(size), color)


func _init() -> void:
	super()
	name = "UnitPopup"
	custom_minimum_size = Vector2(WIDTH, 0)
	# Text is translated here; keep Labels from translating the composed strings again.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	chamfers = Vector4(0, 16, 0, 16)
	fill = UiPalette.PANEL_STRONG
	padding = Vector2.ZERO
	tab_text = " "  # reserves the tab row; the real text is set per unit
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 0)
	add_child(column)
	column.add_child(_build_title())
	column.add_child(_margin(_build_portrait(), SIDE_MARGIN, 0, SIDE_MARGIN, 0))
	column.add_child(_margin(_build_strength(), SIDE_MARGIN, 9, SIDE_MARGIN, 0))
	_stats = GridContainer.new()
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.columns = 2
	_stats.add_theme_constant_override(&"h_separation", 8)
	_stats.add_theme_constant_override(&"v_separation", 14)
	column.add_child(_margin(_stats, SIDE_MARGIN, 11, SIDE_MARGIN, 0))
	_tags = HFlowContainer.new()
	_tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tags.add_theme_constant_override(&"h_separation", 8)
	_tags.add_theme_constant_override(&"v_separation", 3)
	_tags_wrap = _margin(_tags, SIDE_MARGIN, 11, SIDE_MARGIN, 0)
	column.add_child(_tags_wrap)
	column.add_child(_build_note())
	column.add_child(_build_footer())
	hide()


## Fills the card from a UnitPopupModel.build() result. Does nothing while suppressed.
func show_model(model: Dictionary) -> void:
	if suppressed:
		return
	var color: Color = model["color"]
	line_color = Color(color, FRAME_ALPHA)
	tab_color = color
	tab_text = tr(model["type"] as String).to_upper()
	tab_right_text = tr(model["faction"] as String).to_upper()
	tab_right_color = color
	_name_label.text = tr(model["name"] as String).to_upper()
	var designation: String = model.get("designation", "")
	_designation_label.text = tr(designation)
	_designation_label.visible = designation != ""
	_hp_label.text = "%d/%d" % [model["hp"], model["max_hp"]]
	_segments.colors = model["segments"]
	_segments.queue_redraw()
	_fill_stats(model["stats"])
	_fill_tags(model.get("tags", []))
	var note: String = model.get("note", "")
	_note_wrap.visible = note != ""
	_note_label.text = tr(note)
	var status_color: Color = model["status_color"]
	_status_label.text = tr(model["status"] as String).to_upper()
	_dot.color = status_color
	_dot.queue_redraw()
	show()
	reset_size()


## The unit's rendered portrait; null while it is not ready (plain background).
func set_portrait(portrait: Texture2D) -> void:
	_portrait.texture = portrait
	_portrait.queue_redraw()


## Real card size for UnitPopupModel.placement() (layout is deferred, so ask the minimum).
func card_size() -> Vector2:
	var minimum := get_combined_minimum_size()
	return Vector2(maxf(minimum.x, WIDTH), minimum.y)


func _fill_stats(stats: Array) -> void:
	_clear(_stats)
	for stat: Dictionary in stats:
		var cell := VBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override(&"separation", 4)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption := _label(HudTheme.display(400), 12, UiPalette.HUD_MUTED)
		caption.text = tr(stat["label"] as String)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.clip_text = true
		var value := _label(HudTheme.mono(600), 12, UiPalette.HUD_TEXT)
		value.text = stat["value"]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(caption)
		line.add_child(value)
		var bar := _Bar.new()
		bar.fill = stat["fill"]
		cell.add_child(line)
		cell.add_child(bar)
		_stats.add_child(cell)


func _fill_tags(tags: Array) -> void:
	_clear(_tags)
	for tag: String in tags:
		_tags.add_child(Bracketed.new(tr(tag).to_upper()))
	_tags_wrap.visible = not tags.is_empty()


func _build_title() -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 1)
	_name_label = _label(HudTheme.display(700, 1), NAME_SIZE, UiPalette.HUD_TEXT)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label reports its height for the width it has: give it the real one up front.
	_name_label.custom_minimum_size.x = PORTRAIT_SIZE.x - 2.0
	_designation_label = _label(HudTheme.mono(500), 11, UiPalette.HUD_MUTED)
	box.add_child(_name_label)
	box.add_child(_designation_label)
	return _margin(box, 12, 9, 12, 8)


func _build_portrait() -> Control:
	_portrait = _PortraitView.new()
	_portrait.name = "Portrait"
	# The rank chip (3 diamond pips, bottom-left) stays hidden until ranks exist.
	return _portrait


func _build_strength() -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 5)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption := _label(HudTheme.mono(500, 1), 10, UiPalette.HUD_MUTED)
	caption.text = tr("STRENGTH").to_upper()
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_label = _label(HudTheme.mono(600), 12, UiPalette.HUD_TEXT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(caption)
	row.add_child(_hp_label)
	_segments = _Segments.new()
	box.add_child(row)
	box.add_child(_segments)
	return box


func _build_note() -> Control:
	var box := StyleBoxFlat.new()
	box.bg_color = UiPalette.NOTE_BG
	box.border_color = UiPalette.AMBER
	box.set_border_width(SIDE_LEFT, 3)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", box)
	_note_label = _label(HudTheme.display(400), 12, UiPalette.NOTE_TEXT)
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.custom_minimum_size.x = PORTRAIT_SIZE.x - 21.0
	panel.add_child(_margin(_note_label, 8, 5, 8, 5))
	_note_wrap = _margin(panel, SIDE_MARGIN, 11, SIDE_MARGIN, 0)
	_note_wrap.name = "NoteWrap"
	return _note_wrap


func _build_footer() -> Control:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = UiPalette.LINE
	line.custom_minimum_size = Vector2(0, 1)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	_dot = _HexDot.new()
	_status_label = _label(HudTheme.mono(600, 1), 10, UiPalette.HUD_TEXT)
	row.add_child(_dot)
	row.add_child(_status_label)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 0)
	box.add_child(_margin(line, SIDE_MARGIN, 0, SIDE_MARGIN, 0))
	box.add_child(_margin(row, 12, 8, 12, 9))
	var wrap := _margin(box, 0, 11, 0, 0)
	wrap.name = "Footer"
	return wrap


static func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _label(font: Font, size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	return label


func _margin(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", left)
	margin.add_theme_constant_override(&"margin_top", top)
	margin.add_theme_constant_override(&"margin_right", right)
	margin.add_theme_constant_override(&"margin_bottom", bottom)
	margin.add_child(child)
	return margin
