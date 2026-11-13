class_name StaffMapEndNotice
extends Control
## Full-screen notice when the operation ends (TASK-115, TASK-140): "Operation over", the side that
## used a nuclear weapon, "nobody wins" and a Back to menu button. A dim layer
## blocks the map; HUD v3 frame like the battle result notice.

signal menu_pressed
signal review_pressed

const WIDTH := 460.0

const GRAY_END := 2.0
const DARK_START := 1.0
const DARK_END := 3.5
const FRAME_AT := 3.2
const FRAME_FADE := 1.0

var _title: Label
var _dim: ColorRect
var _frame: FramedPanel
var _picture: StaffMapNuclearPictogram
var _time := 0.0
var _playing := false
var _lines: Array[Label] = []
var _menu: Button
var _review: Button
var _table: GridContainer


func _init() -> void:
	name = "EndNotice"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# The map first goes grey, then black (assets/shaders/nuclear_fade); the frame comes last.
	_dim = ColorRect.new()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/nuclear_fade.gdshader")
	_dim.material = material
	add_child(_dim)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	# The pictogram stands above the frame, outside it.
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override(&"separation", 18)
	centre.add_child(stack)
	_picture = StaffMapNuclearPictogram.new()
	_picture.colour = Color("#e07c5e")
	_picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.add_child(_picture)
	var frame := FramedPanel.new()
	_frame = frame
	frame.custom_minimum_size = Vector2(WIDTH, 0)
	frame.chamfers = Vector4(0, 16, 0, 16)
	frame.padding = Vector2(20, 18)
	frame.brackets = true
	frame.bracket_color = Color("#e07c5e")
	frame.tab_color = Color("#e07c5e")
	frame.fill = UiPalette.PANEL_STRONG
	stack.add_child(frame)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 10)
	frame.add_child(column)
	_title = MenuStyle.label("", HudTheme.display(700, 2), 28, UiPalette.HUD_TEXT)
	_title.name = "Title"
	column.add_child(_title)
	for index in 2:
		var line := MenuStyle.label("", HudTheme.mono(500, 0), 12, UiPalette.HUD_DESC)
		line.name = "Line%d" % index
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(line)
		_lines.append(line)
	_table = GridContainer.new()
	_table.name = "ScoreTable"
	_table.columns = 3
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.add_theme_constant_override(&"h_separation", 18)
	_table.add_theme_constant_override(&"v_separation", 4)
	column.add_child(_table)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	column.add_child(buttons)
	_review = MenuStyle.button("")
	_review.name = "ReviewMap"
	_review.focus_mode = Control.FOCUS_NONE
	_review.pressed.connect(_on_review)
	buttons.add_child(_review)
	_menu = MenuStyle.button("")
	_menu.name = "BackToMenu"
	_menu.focus_mode = Control.FOCUS_NONE
	_menu.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(_menu)
	hide()
	set_process(false)


## `lines` = StaffMapEscalation.end_lines; the nobody-wins line is red.
func present(lines: Array[String], palette: StaffMapPalette, headline := "") -> void:
	_frame.tab_text = tr("ESC_END_TAB").to_upper()
	_title.text = (headline if headline != "" else tr("ESC_END_TITLE")).to_upper()
	for index in _lines.size():
		_lines[index].text = lines[index].to_upper()
	_lines[0].add_theme_color_override(&"font_color", UiPalette.HUD_TEXT)
	_lines[1].add_theme_color_override(&"font_color", palette.ui_alert)
	_menu.text = tr("ESC_END_MENU").to_upper()
	_review.text = tr("ESC_END_REVIEW").to_upper()
	_review.hide()
	_table.hide()
	_picture.show()
	seek(FRAME_AT + FRAME_FADE)
	show()


## The notice of a scored ending (TASK-107b): headline, reason, rounds and the points table; the
## map stays visible under a light dim (no nuclear fade, no pictogram) and *Review map* hides it.
func present_result(
	title: String, lines: Array[String], rows: Array[PackedStringArray], _palette: StaffMapPalette
) -> void:
	_frame.tab_text = tr("ESC_END_TITLE").to_upper()
	_title.text = title.to_upper()
	for index in _lines.size():
		_lines[index].text = lines[index].to_upper()
		_lines[index].add_theme_color_override(&"font_color", UiPalette.HUD_DESC)
	_lines[0].add_theme_color_override(&"font_color", UiPalette.HUD_TEXT)
	for child in _table.get_children():
		_table.remove_child(child)
		child.queue_free()
	for row_index in rows.size():
		var last := row_index == rows.size() - 1
		for column_index in 3:
			var cell := MenuStyle.label(
				rows[row_index][column_index].to_upper(),
				HudTheme.mono(700 if last else 500, 0),
				12,
				UiPalette.HUD_TEXT if last else UiPalette.HUD_DESC
			)
			if column_index > 0:
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if column_index == 0 else 0
			_table.add_child(cell)
	_table.visible = not rows.is_empty()
	_menu.text = tr("ESC_END_MENU").to_upper()
	_review.text = tr("ESC_END_REVIEW").to_upper()
	_review.show()
	_picture.hide()
	_playing = false
	set_process(false)
	var material := _dim.material as ShaderMaterial
	material.set_shader_parameter(&"gray", 0.0)
	material.set_shader_parameter(&"dark", 0.0)
	_frame.modulate.a = 1.0
	show()


func _on_review() -> void:
	hide()
	review_pressed.emit()


func press_review() -> void:
	_review.pressed.emit()


func table_cell_texts() -> Array[String]:
	var texts: Array[String] = []
	for cell in _table.get_children():
		texts.append((cell as Label).text)
	return texts


## Plays the fade from the start: grey, black, then the frame (a resumed operation skips it).
func play() -> void:
	_time = 0.0
	_playing = true
	seek(0.0)
	set_process(true)


func _process(delta: float) -> void:
	seek(_time + delta)


## The notice as it looks `time` seconds after the start (a pure function of the time).
func seek(time: float) -> void:
	_time = time
	var material := _dim.material as ShaderMaterial
	material.set_shader_parameter(&"gray", smoothstep(0.0, GRAY_END, time))
	material.set_shader_parameter(&"dark", smoothstep(DARK_START, DARK_END, time))
	var shown := clampf((time - FRAME_AT) / FRAME_FADE, 0.0, 1.0)
	_frame.modulate.a = shown
	_picture.modulate.a = shown
	if _playing and time >= FRAME_AT + FRAME_FADE:
		_playing = false
		set_process(false)


func title_text() -> String:
	return _title.text


func line_text(index: int) -> String:
	return _lines[index].text


func press_menu() -> void:
	_menu.pressed.emit()
