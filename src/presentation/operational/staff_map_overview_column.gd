class_name StaffMapOverviewColumn
extends VBoxContainer
## The read-only politics overview in the right column of the Politics screen (TASK-119b): ladder
## table with the caused counts, countries list and event log, all from StaffMapOverviewModel.
## Built from the Chip / Shape parts of the Decisions panel and the ladder window's colours; no
## input, no state changes. Rebuilt by the panel on open and on a state change only.

signal ladder_toggled

const LOG_SHOWN := 60
const ROW_SEPARATION := 2

## Whether the ladder table shows all levels (else only the current one); the panel keeps it.
var ladder_expanded := false


func _init() -> void:
	name = "Overview"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size.x = StaffMapDecisionsPanel.OVERVIEW_WIDTH
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 10)


## Fills the column for `viewer`.
func show_state(state: OperationalState, palette: StaffMapPalette, viewer: int) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var model := StaffMapOverviewModel.build(state, viewer)
	add_child(_caption(tr("Escalation ladder")))
	add_child(_ladder(model["ladder"], state, palette))
	add_child(_ladder_toggle())
	add_child(_footer(model["footer"]))
	add_child(_collapse_strip(state, palette, viewer))
	add_child(_caption(tr("Countries")))
	add_child(_countries(model["countries"], palette))
	add_child(_caption(tr("Event log")))
	add_child(_log(model["log"]))


func _caption(text: String) -> Label:
	return MenuStyle.label(text.to_upper(), HudTheme.display(700, 2), 11, UiPalette.HUD_MUTED)


func _box(separation := ROW_SEPARATION) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Block"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", separation)
	return box


func _ladder(rows: Array, state: OperationalState, palette: StaffMapPalette) -> Control:
	var box := _box()
	box.name = "Ladder"
	var top := state.ladder.top()
	for row: Dictionary in rows:
		if not ladder_expanded and not row["current"]:
			continue
		var colour := (
			palette.ui_alert
			if row["nuclear"]
			else StaffMapEscalation.level_colour(row["level"], top, palette)
		)
		var chip := StaffMapDecisionParts.Chip.new()
		chip.name = "Level%d" % row["level"]
		chip.edge = colour if row["current"] else Color(0, 0, 0, 0)
		chip.wash = Color(colour, 0.14) if row["current"] else Color(0, 0, 0, 0)
		var line := VBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override(&"separation", 0)
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_theme_constant_override(&"separation", 8)
		head.add_child(MenuStyle.label(str(row["level"]), HudTheme.mono(700, 0), 12, colour))
		var name_label := MenuStyle.label(
			String(row["name"]).to_upper(),
			HudTheme.display(700, 1),
			12,
			palette.ui_alert if row["nuclear"] else UiPalette.HUD_TEXT
		)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_label)
		if row["event"] != "":
			head.add_child(
				MenuStyle.label(
					String(row["event"]).to_upper(),
					HudTheme.mono(500, 0),
					9,
					palette.ui_alert if row["nuclear"] else UiPalette.AMBER
				)
			)
		line.add_child(head)
		var roe := MenuStyle.label(
			"%s: %s" % [tr("ESC_ROE"), row["roe"]], HudTheme.mono(500, 0), 10, UiPalette.HUD_MUTED
		)
		roe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(roe)
		chip.add_child(line)
		box.add_child(chip)
	return box


func _footer(rows: Array) -> Control:
	var box := _box(0)
	box.name = "Footer"
	for row: Dictionary in rows:
		var text := (
			tr("%s: caused %d, de-escalated %d, net %d")
			% [row["name"], row["caused"], row["deescalated"], row["net"]]
		)
		var label := MenuStyle.label(text, HudTheme.mono(500, 0), 10, UiPalette.HUD_TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
	return box


func _countries(rows: Array, palette: StaffMapPalette) -> Control:
	var box := _box()
	box.name = "Countries"
	for row: Dictionary in rows:
		var line := HBoxContainer.new()
		line.name = String(row["id"])
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override(&"separation", 6)
		var relation: StringName = &"neutral"
		if row["stance"] == &"own" or row["stance"] == &"allied":
			relation = &"own"
		elif row["stance"] == &"hostile" or row["stance"] == &"enemy":
			relation = &"hostile"
		line.add_child(StaffMapDecisionParts.Shape.new(relation, palette))
		var name_label := MenuStyle.label(
			row["name"], HudTheme.mono(500, 0), 11, UiPalette.HUD_TEXT
		)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var access := tr("open") if row["open"] else tr("closed")
		var text := "%s · %s · %d / %d" % [row["stance_text"], access, row["own"], row["enemy"]]
		if row["pending"] > 0:
			text += " · " + tr("%d formations when it joins") % row["pending"]
		line.add_child(
			MenuStyle.label(text.to_upper(), HudTheme.mono(500, 0), 9, UiPalette.HUD_MUTED)
		)
		box.add_child(line)
	return box


func _log(rows: Array) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Log"
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 60.0
	var box := _box()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	if rows.is_empty():
		box.add_child(
			MenuStyle.label(tr("Nothing yet"), HudTheme.mono(500, 0), 11, UiPalette.HUD_MUTED)
		)
	for row: Dictionary in rows.slice(0, LOG_SHOWN):
		var label := MenuStyle.label(
			"T%d  %s" % [row["turn"], row["text"]], HudTheme.mono(500, 0), 11, UiPalette.HUD_TEXT
		)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(label)
	return scroll


func _ladder_toggle() -> Control:
	var text := tr("Hide levels") if ladder_expanded else tr("All levels")
	var button := MenuStyle.button(("▴ " if ladder_expanded else "▾ ") + text)
	button.name = "LadderToggle"
	button.add_theme_font_size_override(&"font_size", 10)
	button.custom_minimum_size.y = 22.0
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(
		func() -> void:
			ladder_expanded = not ladder_expanded
			ladder_toggled.emit()
	)
	return button


## The viewer's army collapse line (TASK-140): strength, readiness and the collapse threshold.
func _collapse_strip(state: OperationalState, palette: StaffMapPalette, viewer: int) -> Control:
	var strip := StaffMapEscalation.collapse_strip(state, viewer)
	var colour: Color = palette.ui_alert if strip["collapse"] else UiPalette.HUD_MUTED
	var label := MenuStyle.label(
		String(strip["text"]) + (" · " + tr("ESC_COLLAPSE") if strip["collapse"] else ""),
		HudTheme.mono(500, 0),
		10,
		colour
	)
	label.name = "CollapseStrip"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
