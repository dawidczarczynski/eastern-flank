class_name StaffMapStrikeRow
extends Button
## One weapon row of the strike panel (TASK-141b, docs/design/operational_map/strike_panel.html
## variant A): 46 px, a chamfered glyph tile, the name (Chakra 700 15 caps), the sub-line
## "designation · CLASS · range" (mono 500 10.5 caps, the class in the intercepted blue) and the
## stock (mono 700 18 amber over "STOCK"). Hover = white 7 %, picked = amber 10 % and a 3 px amber
## bar with an amber glyph, stock 0 = 45 % opacity with "ALLIES ONLY" instead of the range.

signal hovered(id: StringName)
signal unhovered(id: StringName)

const HEIGHT := 46.0
const TILE := 34.0
const CHAMFER := 7.0
const TILE_FILL := Color("#171b14")
const SEPARATOR := Color(46 / 255.0, 51 / 255.0, 41 / 255.0, 0.7)
const OFF_OPACITY := 0.45

var means_id: StringName = &""
var enabled_row := true
var picked := false:
	set(value):
		picked = value
		queue_redraw()
		_tint()

var _tile: Control
var _glyph: StaffMapWeaponGlyph
var _name: Label
var _sub: Array[Label] = []
var _stock: Label
var _stock_caption: Label


func _init() -> void:
	toggle_mode = true
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var empty := StyleBoxEmpty.new()
	for style in [&"normal", &"hover", &"pressed", &"disabled", &"focus", &"hover_pressed"]:
		add_theme_stylebox_override(style, empty)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8.0
	line.offset_right = -8.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", 10)
	add_child(line)
	_tile = Control.new()
	_tile.custom_minimum_size = Vector2(TILE, TILE)
	_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tile.draw.connect(_draw_tile)
	line.add_child(_tile)
	_glyph = StaffMapWeaponGlyph.new()
	_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tile.add_child(_glyph)
	var texts := VBoxContainer.new()
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override(&"separation", 1)
	line.add_child(texts)
	_name = MenuStyle.label("", HudTheme.display(700, 0), 15, UiPalette.HUD_TEXT)
	_name.name = "Name"
	texts.add_child(_name)
	var sub := HBoxContainer.new()
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_theme_constant_override(&"separation", 4)
	texts.add_child(sub)
	for i in 3:
		var part := MenuStyle.label("", HudTheme.mono(500, 0), 10, UiPalette.HUD_MUTED)
		part.name = "Sub%d" % i
		sub.add_child(part)
		_sub.append(part)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(spacer)
	var stock := VBoxContainer.new()
	stock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stock.add_theme_constant_override(&"separation", 2)
	line.add_child(stock)
	_stock = MenuStyle.label("", HudTheme.mono(700, 0), 18, UiPalette.AMBER)
	_stock.name = "Stock"
	_stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stock.add_child(_stock)
	_stock_caption = MenuStyle.label("", HudTheme.display(600, 1), 9, UiPalette.HUD_MUTED)
	_stock_caption.name = "StockCaption"
	_stock_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stock.add_child(_stock_caption)
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)


## Fills the row from a StaffMapStrike.means_list entry; `class_colour` colours the class word.
func setup(entry: Dictionary, class_colour: Color) -> void:
	means_id = entry["id"]
	name = String(means_id).capitalize().replace(" ", "")
	enabled_row = entry["enabled"]
	_glyph.glyph = entry["glyph"]
	_name.text = (entry["name"] as String).to_upper()
	var designation: String = entry["designation"]
	_sub[0].text = designation.to_upper() + (" ·" if designation != "" else "")
	_sub[0].visible = designation != ""
	_sub[1].text = (entry["class_text"] as String).to_upper()
	_sub[1].add_theme_color_override(&"font_color", class_colour)
	var tail := tr("ALLIES ONLY") if not enabled_row else (entry["range_text"] as String)
	_sub[2].text = "· " + tail.to_upper()
	_stock.text = str(entry["stock"])
	_stock_caption.text = tr("ALLIES") if not enabled_row else tr("STOCK")
	_stock.add_theme_color_override(
		&"font_color", UiPalette.AMBER if enabled_row else UiPalette.HUD_MUTED
	)
	modulate.a = 1.0 if enabled_row else OFF_OPACITY
	_tint()
	queue_redraw()


## The row's text as shown, for tests and tooltips: "NAME | DESIGNATION · CLASS · RANGE | STOCK".
func summary() -> String:
	var parts: Array[String] = []
	for part in _sub:
		if part.visible:
			parts.append(part.text)
	return "%s | %s | %s %s" % [_name.text, " ".join(parts), _stock.text, _stock_caption.text]


func _tint() -> void:
	if _glyph != null:
		_glyph.colour = UiPalette.AMBER if picked else UiPalette.HUD_TEXT
	if _tile != null:
		_tile.queue_redraw()


func _on_enter() -> void:
	queue_redraw()
	hovered.emit(means_id)


func _on_exit() -> void:
	queue_redraw()
	unhovered.emit(means_id)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if picked:
		draw_rect(rect, Color(UiPalette.AMBER, 0.10))
		draw_rect(Rect2(0, 0, 3, size.y), UiPalette.AMBER)
	elif is_hovered():
		draw_rect(rect, Color(UiPalette.HUD_TEXT, 0.07))
	draw_line(Vector2(0, size.y - 0.5), Vector2(size.x, size.y - 0.5), SEPARATOR, 1.0)


func _draw_tile() -> void:
	var c := CHAMFER
	var s := _tile.size
	var poly := PackedVector2Array(
		[
			Vector2(0, 0),
			Vector2(s.x - c, 0),
			Vector2(s.x, c),
			Vector2(s.x, s.y),
			Vector2(c, s.y),
			Vector2(0, s.y - c),
		]
	)
	_tile.draw_colored_polygon(poly, TILE_FILL)
