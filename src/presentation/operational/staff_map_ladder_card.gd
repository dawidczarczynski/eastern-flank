class_name StaffMapLadderCard
extends FramedPanel
## Ladder card of the staff map (TASK-115, opened from the escalation chip): the levels of the
## shared escalation ladder as a table (top first), the current one marked, with what may be struck
## there (rules of engagement) and the sanctuary / allies / cap / end markers; below them one
## collapse strip per side with a red COLLAPSE tag (TASK-140, StaffMapEscalation.collapse_strip).
## Read-only, all from the data.

const WIDTH := 460.0

var _rows := VBoxContainer.new()
var _strips: Array[Dictionary] = []  # per player: {text, collapse} as shown (tests)


func _init() -> void:
	super()
	name = "LadderCard"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 12, 0, 12)
	padding = Vector2(14, 10)
	fill = UiPalette.PANEL_STRONG
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override(&"separation", 6)
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
	var rule := ColorRect.new()
	rule.name = "StripRule"
	rule.color = UiPalette.LINE
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_child(rule)
	_strips.clear()
	for player in state.player_sides.size():
		var strip := StaffMapEscalation.collapse_strip(state, player)
		_strips.append(strip)
		_rows.add_child(_strip(strip, palette, player))
	show()
	reset_size()


## One text per level as shown, top level first (tests).
func row_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for row in _rows.get_children():
		if not String(row.name).begins_with("Level"):
			continue
		texts.append((row.get_child(0) as Label).text + " | " + (row.get_child(1) as Label).text)
	return texts


## Collapse strip texts as shown, per player (tests).
func strip_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for strip in _strips:
		texts.append(String(strip["text"]))
	return texts


## Whether the COLLAPSE tag is lit for `player` (tests).
func collapse_tagged(player: int) -> bool:
	var row := _rows.get_node_or_null("Strip%d" % player)
	return row != null and row.get_node_or_null("Collapse") != null


func _strip(strip: Dictionary, palette: StaffMapPalette, player: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Strip%d" % player
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	var collapse: bool = strip["collapse"]
	var text := MenuStyle.label(
		String(strip["text"]),
		HudTheme.mono(500, 0),
		11,
		palette.ui_alert if collapse else UiPalette.HUD_DESC
	)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true  # one line; the card is wide enough for both languages
	row.add_child(text)
	if collapse:
		var tag := StaffMapDecisionParts.chip(
			"▲ " + tr("ESC_COLLAPSE").to_upper(),
			HudTheme.mono(700, 1),
			10,
			UiPalette.INK,
			palette.ui_alert,
			palette.ui_alert
		)
		tag.name = "Collapse"
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
	return row


## The lowest level with the same strike classes as `level` (contiguous below it).
static func _same_roe_from(state: OperationalState, level: int) -> int:
	var classes := state.ladder.strike_classes_at(level)
	var from := level
	while from > 0 and state.ladder.strike_classes_at(from - 1) == classes:
		from -= 1
	return from


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
	var same := _same_roe_from(state, level)
	if same < level:  # seven levels: repeat the long class list only where it changes
		detail = tr("May strike: as level %d") % same
	var opened: Array[String] = []
	# Markers only where they start: the sanctuary / allies line is the level that introduces it.
	if level == state.ladder.sanctuary_open_level:
		opened.append(tr("ESC_MARK_SANCTUARY"))
	if level == state.ladder.allies_join_level:
		opened.append(tr("ESC_MARK_ALLIES"))
	if level == state.ladder.cap():
		opened.append(tr("ESC_MARK_CAP"))
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
