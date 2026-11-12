# gdlint: disable=max-public-methods
class_name StaffMapJournalWindow
extends StaffMapWindow
## The operational journal window (TASK-148b, docs/design/operational_map/operational_journal.html,
## variant A): a StaffMapWindow of the report width on the left dock, tab "JOURNAL · <side>" in the
## side colour, filter chips (ALL / STRIKES / BATTLES / MOVES / POLITICS), a scrolling list of
## turn headers (newest turn first, `NOW` on the current one, a sticky copy of the header on top
## while scrolling) and entry rows (side shape, tag, sentence, place line). Reads only
## `state.journal.entries_for(viewer)`; the words come from StaffMapJournalText. A click on a row
## emits `entry_chosen(coord)` (the owner centres the map and rings the hex); hover lights a row;
## entries added since the window was last closed carry a 3 px amber bar until hovered.
## Rows are built lazily (a page at a time, newest first) so a long operation opens at once, and
## only on `show_journal` / `refresh` – never per frame.

signal entry_chosen(coord: Vector2i)

const VIEWPORT_HEIGHT := 430.0
const PAGE := 20
const HEADER_HEIGHT := 28.0
const TEXT_WIDTH := 316.0
const BG := Color("#0a0d0a")

## (Vector2i) -> String place namer, set by the owner; "" = the hex number.
var place_namer: Callable

var _palette: StaffMapPalette
var _state: OperationalState
var _viewer := 0
var _filter: StringName = &""
var _chips: Dictionary = {}  # filter id -> Button
var _frame: Control
var _scroll: ScrollContainer
var _list: VBoxContainer
var _sticky: Control
var _sticky_title := -1
var _items: Array[Dictionary] = []  # {header: turn} or {entry: Entry, index: int}, newest first
var _built := 0
var _headers: Array[Control] = []
var _rows: Array[JournalRow] = []
var _seen: Dictionary = {}  # viewer -> entries_for(viewer).size() at the last close
var _focus: OperationalJournal.Entry
var _fit_pending := false


## One entry row: hover light, unseen bar, click.
class JournalRow:
	extends PanelContainer

	signal picked(entry: OperationalJournal.Entry)

	var entry: OperationalJournal.Entry
	var sentence := ""
	var unseen := false
	var lit := false
	var _hover := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		mouse_entered.connect(_on_enter)
		mouse_exited.connect(_on_exit)
		gui_input.connect(_on_input)
		_restyle()

	func set_lit(value: bool) -> void:
		lit = value
		_restyle()

	func _on_enter() -> void:
		_hover = true
		unseen = false
		_restyle()

	func _on_exit() -> void:
		_hover = false
		_restyle()

	func _on_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(entry)
			accept_event()

	func _restyle() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.07) if (_hover or lit) else Color(0, 0, 0, 0)
		box.border_color = Color(1, 1, 1, 0.05)
		box.border_width_bottom = 1
		if unseen and not _hover:
			box.border_width_left = 3
			box.border_color = UiPalette.AMBER
			# Only the left edge is amber: the divider keeps its own colour below.
			box.set_border_width(SIDE_BOTTOM, 0)
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		box.content_margin_left = 3
		add_theme_stylebox_override(&"panel", box)


func _init(palette: StaffMapPalette = null) -> void:
	super(" ", WIDTH_REPORT)
	_palette = palette if palette != null else StaffMapPalette.new()
	name = "JournalWindow"
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 6)
	add_child(column)
	column.add_child(_build_chips())
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.custom_minimum_size = Vector2(0, 60)
	column.add_child(_frame)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	_frame.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 0)
	_scroll.add_child(_list)
	_sticky = PanelContainer.new()
	_sticky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sticky.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_sticky.hide()
	_frame.add_child(_sticky)
	column.add_child(
		StaffMapWindow.hint_line(tr("J or ✕ closes · click an entry to find it on the map"))
	)


# --- API -------------------------------------------------------------------------------------


## Opens the list for `viewer` (rebuilt from the state). `focus` (an entry of the journal) is
## scrolled into view and lit; the window opens at the current turn otherwise.
func show_journal(
	state: OperationalState, viewer: int, focus: OperationalJournal.Entry = null
) -> void:
	_state = state
	_viewer = viewer
	_focus = focus
	_rebuild(true)


## Rebuilds the open list after new events (keeps the scroll position).
func refresh() -> void:
	if _state == null or not visible:
		return
	_rebuild(false)


## Hides the window; remembers what has been seen. True when it was open.
func close() -> bool:
	var was_open := visible
	if was_open:
		mark_seen()
	hide()
	return was_open


## Everything now in the journal of `viewer` (both sides when -1) counts as seen.
func mark_seen(viewer := -1) -> void:
	if _state == null:
		return
	for side in [viewer] if viewer >= 0 else [0, 1]:
		_seen[side] = _state.journal.entries_for(side).size()


func set_filter(id: StringName) -> void:
	if not StaffMapJournalText.FILTERS.has(id):
		return
	_filter = id
	if _state != null:
		_rebuild(true)
	else:
		_sync_chips()


func filter() -> StringName:
	return _filter


func chip(id: StringName) -> Button:
	return _chips.get(id) as Button


## Entry rows built so far (the first PAGE entries at least).
func row_count() -> int:
	return _rows.size()


## Entries the current filter lists (built or not).
func entry_count() -> int:
	var n := 0
	for item in _items:
		if item.has("entry"):
			n += 1
	return n


func row(index: int) -> JournalRow:
	return _rows[index]


func row_text(index: int) -> String:
	return _rows[index].sentence


func header_count() -> int:
	return _headers.size()


func header_title(index: int) -> String:
	return String(_headers[index].get_meta(&"title", ""))


func header_text(index: int) -> String:
	return String(_headers[index].get_meta(&"text", ""))


## The empty-state text shown instead of the list ("" while there are entries).
func empty_text() -> String:
	var label := _list.get_node_or_null("Empty") as Label
	return label.text if label != null else ""


func unseen_count() -> int:
	var n := 0
	for r in _rows:
		if r.unseen:
			n += 1
	return n


func click_row(index: int) -> void:
	_rows[index].picked.emit(_rows[index].entry)


func scroll_container() -> ScrollContainer:
	return _scroll


func sticky_header() -> Control:
	return _sticky


## Sizes the viewport to the real content (the owner calls it a frame after a rebuild).
func fit() -> void:
	_fit_pending = false
	if not visible or _list.get_child_count() == 0:
		return
	var wanted := clampf(_list.get_combined_minimum_size().y, 60.0, VIEWPORT_HEIGHT)
	if absf(wanted - _frame.custom_minimum_size.y) > 2.0:
		_frame.custom_minimum_size.y = wanted
		dock_again()


## Re-docks after the content size changed.
func dock_again() -> void:
	if is_inside_tree():
		dock(get_viewport().get_visible_rect().size.x)


# --- building --------------------------------------------------------------------------------


func _build_chips() -> Control:
	var box := HBoxContainer.new()
	box.name = "Chips"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 4)
	for id in StaffMapJournalText.FILTERS:
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.text = tr(StaffMapJournalText.FILTER_LABELS[id]).to_upper()
		button.name = "Chip_" + (String(id) if id != &"" else "all")
		button.add_theme_font_override(&"font", HudTheme.mono(600, 0))
		button.add_theme_font_size_override(&"font_size", 10)
		var off := MenuStyle.box(Color(0, 0, 0, 0), Color("#3a3f33"))
		var on := MenuStyle.box(Color(UiPalette.AMBER, 0.12), Color(UiPalette.AMBER, 0.6))
		for style in [&"normal", &"hover", &"disabled"]:
			button.add_theme_stylebox_override(style, off)
		for style in [&"pressed", &"hover_pressed"]:
			button.add_theme_stylebox_override(style, on)
		button.add_theme_color_override(&"font_color", UiPalette.HUD_MUTED)
		button.add_theme_color_override(&"font_hover_color", UiPalette.HUD_TEXT)
		button.add_theme_color_override(&"font_pressed_color", UiPalette.AMBER)
		button.add_theme_color_override(&"font_hover_pressed_color", UiPalette.AMBER)
		button.pressed.connect(set_filter.bind(id))
		box.add_child(button)
		_chips[id] = button
	_sync_chips()
	return box


func _sync_chips() -> void:
	for id: StringName in _chips:
		(_chips[id] as Button).set_pressed_no_signal(id == _filter)


func _rebuild(reset_scroll: bool) -> void:
	var keep := _scroll.scroll_vertical
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_headers.clear()
	_rows.clear()
	_items.clear()
	_built = 0
	_sticky.hide()
	_sticky_title = -1
	_sync_chips()
	var side_colour := StaffMapFormations.side_colour(_palette, _viewer)
	tab_text = (
		"%s · %s"
		% [tr("JOURNAL").to_upper(), StaffMapTurnBar.side_name(_state, _viewer).to_upper()]
	)
	tab_color = side_colour
	_collect_items()
	if _items.is_empty():
		_show_empty()
	else:
		_build_until(PAGE, _focus_item())
	_frame.custom_minimum_size.y = _estimate_height()
	reset_size()
	if visible or not reset_scroll:
		dock_again()
	_scroll.scroll_vertical = 0 if reset_scroll else keep
	if reset_scroll and _focus != null:
		_reveal_focus()
	_queue_fit()


func _collect_items() -> void:
	var all := _state.journal.entries_for(_viewer)
	var seen_from: int = _seen.get(_viewer, all.size())
	var groups: Array = []  # [[turn, [items]]], oldest first
	for i in all.size():
		var e := all[i]
		if not StaffMapJournalText.matches(e, _filter):
			continue
		if groups.is_empty() or groups[groups.size() - 1][0] != e.turn:
			groups.append([e.turn, []])
		groups[groups.size() - 1][1].append({"entry": e, "index": i, "unseen": i >= seen_from})
	groups.reverse()
	for group in groups:
		_items.append({"header": group[0]})
		_items.append_array(group[1])


func _focus_item() -> int:
	if _focus == null:
		return -1
	for i in _items.size():
		if _items[i].get("entry") == _focus:
			return i
	return -1


## Builds items until `count` are built and the item `need` (when >= 0) is among them.
func _build_until(count: int, need := -1) -> void:
	var target := maxi(count, need + 1)
	while _built < _items.size() and _built < target:
		_build_item(_items[_built])
		_built += 1
	# A page never ends on a header without its rows.
	while _built < _items.size() and _items[_built - 1].has("header"):
		_build_item(_items[_built])
		_built += 1


func _build_item(item: Dictionary) -> void:
	if item.has("header"):
		var header := _header_row(int(item["header"]))
		_list.add_child(header)
		_headers.append(header)
		return
	var entry: OperationalJournal.Entry = item["entry"]
	var model := StaffMapJournalText.line(entry, _viewer, _state, place_namer)
	var r := JournalRow.new()
	r.entry = entry
	r.sentence = StaffMapJournalText.plain(model["parts"])
	r.unseen = item["unseen"]
	r.set_lit(entry == _focus)
	r.picked.connect(_on_row_picked)
	r.add_child(_row_content(model))
	_list.add_child(r)
	_rows.append(r)


func _row_content(model: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override(&"separation", 8)
	var shape := _Shape.new(model["side"], _palette)
	shape.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(shape)
	var tag := MenuStyle.label(model["tag"], HudTheme.mono(700, 1), 9, UiPalette.HUD_MUTED)
	tag.custom_minimum_size = Vector2(34, 0)
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(tag)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override(&"separation", 1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(text)
	text.add_child(_sentence(model["parts"]))
	if model["place"] != "":
		var place := MenuStyle.label(
			(model["place"] as String).to_upper(),
			HudTheme.font("IBMPlexSansCondensed-Medium", 0),
			11,
			UiPalette.HUD_MUTED
		)
		place.name = "Place"
		text.add_child(place)
	return h


func _sentence(parts: Array) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.name = "Sentence"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var medium := HudTheme.font("IBMPlexSansCondensed-Medium", 0)
	label.add_theme_font_override(&"normal_font", medium)
	label.add_theme_font_override(&"bold_font", HudTheme.font("IBMPlexSansCondensed-Bold", 0))
	label.add_theme_font_size_override(&"normal_font_size", 12)
	label.add_theme_font_size_override(&"bold_font_size", 12)
	label.add_theme_color_override(&"default_color", UiPalette.HUD_TEXT)
	label.text = (
		StaffMapJournalText
		. bbcode(
			parts,
			{
				StaffMapJournalText.HIT: _palette.outcome_hit,
				StaffMapJournalText.ICPT: _palette.outcome_intercepted,
				StaffMapJournalText.BAD: _palette.ui_alert,
			}
		)
	)
	return label


func _header_row(turn: int) -> Control:
	var info := StaffMapJournalText.turn_header(turn, _state)
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = Color(UiPalette.AMBER, 0.3)
	style.border_width_bottom = 1
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	box.add_theme_stylebox_override(&"panel", style)
	box.set_meta(&"turn", turn)
	box.set_meta(&"title", info["title"])
	box.set_meta(&"text", info["text"])
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override(&"separation", 8)
	box.add_child(h)
	var title := MenuStyle.label(
		(info["title"] as String).to_upper(), HudTheme.display(700, 1), 11, UiPalette.AMBER
	)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(title)
	if turn == _state.turn:
		var now := MenuStyle.label(tr("NOW"), HudTheme.mono(700, 0), 9, Color("#0a0c09"))
		now.name = "Now"
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = UiPalette.AMBER
		fill.content_margin_left = 5
		fill.content_margin_right = 5
		fill.content_margin_top = 1
		fill.content_margin_bottom = 1
		badge.add_theme_stylebox_override(&"panel", fill)
		badge.add_child(now)
		h.add_child(badge)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var date := MenuStyle.label(
		(info["text"] as String).to_upper(), HudTheme.mono(600, 0), 10, UiPalette.HUD_MUTED
	)
	date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(date)
	return box


func _show_empty() -> void:
	var text := (
		StaffMapJournalText.empty_text()
		if _filter == &""
		else StaffMapJournalText.filtered_empty_text()
	)
	var label := MenuStyle.label(text, HudTheme.mono(500, 0), 11, UiPalette.HUD_MUTED)
	label.name = "Empty"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(TEXT_WIDTH + 60.0, 0)
	_list.add_child(label)


## A first guess of the list height before the layout knows the wrapped text.
func _estimate_height() -> float:
	if _items.is_empty():
		return 48.0
	if _built < _items.size():
		return VIEWPORT_HEIGHT
	var total := 0.0
	var row_index := 0
	for item in _items:
		if item.has("header"):
			total += HEADER_HEIGHT + 6.0
			continue
		var length := _rows[row_index].sentence.length()
		row_index += 1
		total += 14.0 + 17.0 * ceilf(float(length) * 5.8 / TEXT_WIDTH) + 12.0
	return clampf(total, 60.0, VIEWPORT_HEIGHT)


func _queue_fit() -> void:
	if _fit_pending or not is_inside_tree():
		return
	_fit_pending = true
	get_tree().process_frame.connect(fit, CONNECT_ONE_SHOT)


func _reveal_focus() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	for r in _rows:
		if r.entry == _focus and is_instance_valid(r):
			_scroll.ensure_control_visible(r)
			return


func _on_row_picked(entry: OperationalJournal.Entry) -> void:
	if entry.has_coord:
		entry_chosen.emit(entry.coord)


func _on_scrolled(value: float) -> void:
	var bar := _scroll.get_v_scroll_bar()
	if _built < _items.size() and value + bar.page > bar.max_value - 240.0:
		var before := _list.get_combined_minimum_size().y
		_build_until(_built + PAGE)
		if before > 0.0:
			_scroll.scroll_vertical = int(value)
	_update_sticky(value)


## Shows a copy of the header of the turn at the top of the viewport once its own header is gone.
func _update_sticky(value: float) -> void:
	var current: Control = null
	for header in _headers:
		if header.position.y <= value + 0.5:
			current = header
		else:
			break
	if current == null or absf(current.position.y - value) < 1.0:
		_sticky.hide()
		_sticky_title = -1
		return
	var turn: int = current.get_meta(&"turn")
	if _sticky_title != turn:
		for child in _sticky.get_children():
			_sticky.remove_child(child)
			child.queue_free()
		_sticky.add_child(_header_row(turn))
		_sticky_title = turn
	_sticky.show()


## The side shape of a row: rectangle (own), diamond (enemy) or circle (neutral).
class _Shape:
	extends Control

	var _kind: StringName
	var _palette: StaffMapPalette

	func _init(kind: StringName, palette: StaffMapPalette) -> void:
		_kind = kind
		_palette = palette
		custom_minimum_size = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func kind() -> StringName:
		return _kind

	func _draw() -> void:
		var c := size / 2.0
		match _kind:
			StaffMapJournalText.OWN:
				draw_rect(Rect2(Vector2.ZERO, size), _palette.side_own)
			StaffMapJournalText.ENEMY:
				var r := 7.0
				draw_colored_polygon(
					PackedVector2Array(
						[
							c + Vector2(0, -r),
							c + Vector2(r, 0),
							c + Vector2(0, r),
							c + Vector2(-r, 0)
						]
					),
					_palette.side_enemy
				)
			_:
				draw_circle(c, 7.0, _palette.ui_muted)
