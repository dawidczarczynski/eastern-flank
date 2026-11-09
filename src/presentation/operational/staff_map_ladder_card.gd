class_name StaffMapLadderCard
extends FramedPanel
## Ladder card of the staff map (TASK-115, opened from the escalation chip): the five levels of
## the shared escalation ladder as a table, the current one marked, with what may be struck there
## (rules of engagement) and the sanctuary / allies / end markers. Read-only, all from the data.

const WIDTH := 400.0

var _rows := VBoxContainer.new()


func _init() -> void:
	super()
	name = "LadderCard"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 12, 0, 12)
	padding = Vector2(14, 10)
	fill = UiPalette.PANEL_STRONG
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override(&"separation", 8)
	add_child(_rows)
	hide()


func show_state(state: OperationalState, palette: StaffMapPalette) -> void:
	tab_text = tr("ESC_CARD_TITLE").to_upper()
	tab_color = StaffMapEscalation.level_colour(state.escalation_level, state.ladder.top(), palette)
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var top := state.ladder.top()
	for level in range(top, -1, -1):
		_rows.add_child(_row(state, palette, level))
	show()
	reset_size()


## One text per level as shown, top level first (tests).
func row_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for row in _rows.get_children():
		texts.append((row.get_child(0) as Label).text + " | " + (row.get_child(1) as Label).text)
	return texts


func _row(state: OperationalState, palette: StaffMapPalette, level: int) -> Control:
	var current := level == state.escalation_level
	var colour := StaffMapEscalation.level_colour(level, state.ladder.top(), palette)
	var column := VBoxContainer.new()
	column.name = "Level%d" % level
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	var title := (
		"%s%d · %s"
		% ["▸ " if current else "  ", level, StaffMapEscalation.level_name(state, level)]
	)
	var head := MenuStyle.label(
		title.to_upper(), HudTheme.display(700, 1), 14, colour if current else UiPalette.HUD_MUTED
	)
	column.add_child(head)
	var detail := "%s: %s" % [tr("ESC_ROE"), StaffMapEscalation.roe_text(state, level)]
	var opened: Array[String] = []
	# Markers only where they start: the sanctuary / allies line is the level that introduces it.
	if level == state.ladder.sanctuary_open_level:
		opened.append(tr("ESC_MARK_SANCTUARY"))
	if level == state.ladder.allies_join_level:
		opened.append(tr("ESC_MARK_ALLIES"))
	if level == state.ladder.top():
		opened.append(tr("ESC_MARK_END"))
	if not opened.is_empty():
		detail += "\n" + " · ".join(opened)
	var body := MenuStyle.label(
		detail, HudTheme.mono(500, 0), 11, UiPalette.HUD_TEXT if current else UiPalette.HUD_DESC
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = WIDTH - 28.0
	column.add_child(body)
	return column
