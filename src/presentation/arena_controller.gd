class_name ArenaController
extends BattleController
## Dev arena (devtools, not part of the game): an empty flat battlefield where the human places
## units of both sides, removes them, refills their HP / moves and commands them freely – a test
## bench for animations and effects. Both sides are played by the human (hot seat: End turn passes
## the command to the other side), there is no AI, no objectives and the battle never ends.
## Placing and removing units edit the state directly (bench only, nothing is recorded); every
## order given to a unit still goes through the normal commands.
## Keys: 1 command, 2 place, 3 remove, 4 refill all, Tab other side; right click leaves a tool.

enum Tool { COMMAND, PLACE, REMOVE }

const ARENA_WIDTH := 18
const ARENA_HEIGHT := 11
const ARENA_FACTIONS: Array[StringName] = [&"poland", &"russia"]
const TOOL_NAMES := ["Command", "Place", "Remove"]
const PANEL_WIDTH := 292.0
const ROW_LABEL_WIDTH := 104.0
## Editable stats of the selected unit: [UnitDefinition property, label, min, max, step]. Ranges
## are metres, one step = one hex (UnitDefinition.HEX_METRES).
const STAT_SPECS: Array = [
	[&"max_hp", "Max HP", 1, 99, 1],
	[&"move_points", "Move points", 0, 30, 1],
	[&"attack", "Attack", 0, 99, 1],
	[&"defense", "Defense", 0, 99, 1],
	[&"effective_range_m", "Full range", 0, 12000, 250],
	[&"max_range_m", "Max range", 0, 12000, 250],
	[&"min_range_m", "Min range", 0, 12000, 250],
]

var _tool := Tool.COMMAND
var _side := 0
var _tool_buttons: Array[Button] = []
var _faction_pickers: Array[OptionButton] = []
var _unit_picker: OptionButton
var _status: Label
var _side_button: Button
var _last_attack := {}  # the last non-counter unit_attacked event (Fire again replays it)
var _fire_again_button: Button
var _effects_box: VBoxContainer
var _stats_box: VBoxContainer
var _los_check: CheckBox
var _stat_spins := {}  # UnitDefinition property -> SpinBox
var _fire_mode_picker: OptionButton
var _reset_stats_button: Button
var _original_definitions := {}  # unit id -> the shared definition before its first stat edit
var _sliders := {}  # DevTunables key (or &"slow_motion") -> {slider, value label}
var _hp_spin: SpinBox
var _moves_spin: SpinBox
var _dug_check: CheckBox
var _ambush_check: CheckBox
var _editor_box: VBoxContainer
var _switch_boxes := {}  # &"grid" / &"fps" / &"camera" -> CheckBox


## Flat plains of ARENA_WIDTH x ARENA_HEIGHT tiles, two sides, no units, no victory conditions.
func _initial_state() -> GameState:
	scenario_name = ""
	var rng := RandomNumberGenerator.new()
	rng.seed = MAP_SEED
	var grid := MapGenerator.generate(ARENA_WIDTH, ARENA_HEIGHT, rng)
	for c in grid.coords():
		MapGenerator.force_terrain(grid, c, Terrain.Type.PLAINS)
	var state := GameState.new(grid, 2, MAP_SEED)
	state.player_factions = ARENA_FACTIONS.duplicate()
	state.operation_name = "Arena"
	state.set_objectives(BattleObjectives.new())
	state.record_starting_hp()
	return state


func _ready() -> void:
	DevTunables.activate()
	await super._ready()
	if is_built:
		_build_panel()
		add_child(FpsOverlay.new())
		_apply_switches()


## Leaving the arena: tunables stop counting and the slow motion ends.
func _exit_tree() -> void:
	DevTunables.deactivate()


## Remembers the last attack for Fire again, then plays the event as usual.
func _on_event(event: Dictionary) -> void:
	if event["type"] == &"unit_attacked" and not event.get("counter", false):
		_last_attack = event.duplicate()
	super(event)
	_sync_panel()


func _on_queue_drained() -> void:
	super()
	_sync_panel()


## True when the last attack can be shown again: both units are still there and nothing plays.
func can_fire_again() -> bool:
	if _last_attack.is_empty() or _is_playing_events():
		return false
	var state := _sim.state
	for key in ["attacker_id", "target_id"]:
		var unit := state.get_unit(_last_attack[key])
		if unit == null or not unit.is_alive() or not _unit_views.has(unit.id):
			return false
	return true


## Fire again: replays the last attack as a view event (same shooter, target and visuals; the
## scatter differs, it is seeded by the event serial). No command runs and the rules and the state
## stay untouched; the target's HP bar first goes back up by the old damage, so it steps down again
## to what the state says now.
func fire_again() -> void:
	if not can_fire_again():
		return
	var target := _sim.state.get_unit(_last_attack["target_id"])
	var view: UnitView = _unit_views[target.id]
	var event := _last_attack.duplicate()
	view.set_shown_hp(mini(target.definition.max_hp, target.hp + int(event["damage"])))
	event["target_hp"] = target.hp
	_on_event(event)


## No AI: the human plays every side.
func _run_ai_turns() -> void:
	pass


## The turn passes and the human takes over the side that is on turn now.
func _end_human_turn() -> void:
	cancel_fire_support()
	_target_ring.close()
	_sim.execute(EndTurnCommand.new())
	human_player = _sim.state.current_player
	_side = human_player
	_sync_panel()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and is_built and _panel_key(key.keycode):
		return
	super._unhandled_input(event)


func _on_camera_clicked(screen_position: Vector2, button: MouseButton) -> void:
	if _tool != Tool.COMMAND and button == MOUSE_BUTTON_RIGHT:
		_set_tool(Tool.COMMAND)
		return
	super._on_camera_clicked(screen_position, button)


func _on_hex_clicked(coord: Vector2i) -> void:
	match _tool:
		Tool.PLACE:
			_place_at(coord)
		Tool.REMOVE:
			_remove_at(coord)
		_:
			super._on_hex_clicked(coord)


## Adds the picked unit type of the current side on the free land tile `coord`.
func _place_at(coord: Vector2i, picked: UnitDefinition = null) -> void:
	var state := _sim.state
	if state.unit_at(coord) != null or state.grid.get_terrain(coord) == Terrain.Type.WATER:
		return
	var definition := picked if picked != null else _picked_definition()
	if definition == null:
		return
	var unit := state.add_unit(_side, definition, coord)
	if _side == state.current_player:
		unit.moves_left = definition.move_points
	else:
		unit.moves_left = 0
	_create_unit_view(unit)
	_after_edit()


## Screenshot hook (SCREENSHOT_ARENA): puts a unit of `unit_type` for `owner` on offset tile
## (`col`, `row`), whatever the side on turn.
func debug_place(owner: int, unit_type: String, col: int, row: int) -> void:
	var faction := _sim.state.faction_of(owner)
	var definition := faction.find_unit(StringName(unit_type)) if faction != null else null
	if definition == null:
		push_error("debug_place: side %d has no unit '%s'" % [owner, unit_type])
		return
	var side := _side
	_side = owner
	_place_at(MapGenerator.offset_to_axial(col, row), definition)
	_side = side
	_sync_panel()


func _remove_at(coord: Vector2i) -> void:
	var unit := _sim.state.unit_at(coord)
	if unit == null:
		return
	if unit.id == _selected_unit_id:
		_select(-1)
	_sim.state.units.erase(unit.id)
	var view: UnitView = _unit_views.get(unit.id)
	_unit_views.erase(unit.id)
	if view != null:
		view.queue_free()
	_after_edit()


## Full HP, moves and attacks of every unit again (the orders' bookkeeping reset too).
func _refill_all() -> void:
	for unit: Unit in _sim.state.units.values():
		unit.hp = unit.definition.max_hp
		unit.moves_left = unit.definition.move_points
		unit.has_attacked = false
		unit.activated = false
		unit.dug = false
		unit.ambush = false
		unit.scoot_used = false
		unit.slot_order = &""
		var view: UnitView = _unit_views.get(unit.id)
		if view != null:
			view.set_shown_hp(unit.hp)
	_after_edit()


func _clear_all() -> void:
	_select(-1)
	for id: int in _sim.state.units.keys():
		var view: UnitView = _unit_views.get(id)
		if view != null:
			view.queue_free()
	_unit_views.clear()
	_sim.state.units.clear()
	_after_edit()


## Bench switch: direct fire ignores line of sight (orders, forecast and range overlay).
func set_ignore_line_of_sight(on: bool) -> void:
	_sim.state.ignore_line_of_sight = on
	if is_built:
		_refresh_selection_ui()


func _after_edit() -> void:
	_sim.state.record_starting_hp()
	_refresh_hud()
	_refresh_selection_ui()
	_sync_panel()


## The unit editor's target: the selected unit, null without a selection.
func _edited_unit() -> Unit:
	if _sim == null:
		return null
	return _sim.state.get_unit(_selected_unit_id)


## Unit editor (bench only, nothing recorded, like Place / Remove): HP clamped to 1..max HP.
func set_selected_hp(value: int) -> void:
	var unit := _edited_unit()
	if unit == null:
		return
	unit.hp = clampi(value, 1, unit.definition.max_hp)
	var view: UnitView = _unit_views.get(unit.id)
	if view != null:
		view.set_shown_hp(unit.hp)
	_finish_unit_edit()


## Moves left clamped to 0..the unit's move points.
func set_selected_moves(value: int) -> void:
	var unit := _edited_unit()
	if unit == null:
		return
	unit.moves_left = clampi(value, 0, unit.definition.move_points)
	_finish_unit_edit()


func set_selected_dug(on: bool) -> void:
	var unit := _edited_unit()
	if unit == null:
		return
	unit.dug = on
	_finish_unit_edit()


func set_selected_ambush(on: bool) -> void:
	var unit := _edited_unit()
	if unit == null:
		return
	unit.ambush = on
	_finish_unit_edit()


## Sets a stat of the selected unit (bench only, nothing recorded). The unit gets its own copy of
## its definition on the first edit, so the data file and the other units of the type stay as they
## are; values are clamped to STAT_SPECS and the ranges keep min <= full <= max.
func set_selected_stat(value: int, property: StringName) -> void:
	var unit := _edited_unit()
	if unit == null:
		return
	for spec: Array in STAT_SPECS:
		if spec[0] == property:
			value = clampi(value, spec[2], spec[3])
	_own_definition(unit)
	var definition := unit.definition
	definition.set(property, value)
	match property:
		&"effective_range_m":
			definition.max_range_m = maxi(definition.max_range_m, value)
		&"max_range_m":
			definition.effective_range_m = mini(definition.effective_range_m, value)
			definition.min_range_m = mini(definition.min_range_m, value)
		&"min_range_m":
			definition.max_range_m = maxi(definition.max_range_m, value)
			definition.effective_range_m = maxi(definition.effective_range_m, value)
	_after_stat_edit(unit)


## Direct (line of sight) or indirect fire for the selected unit.
func set_selected_fire_mode(mode: StringName) -> void:
	var unit := _edited_unit()
	if unit == null:
		return
	_own_definition(unit)
	unit.definition.fire_mode = mode
	_after_stat_edit(unit)


## Gives the selected unit back the shared definition of its type.
func reset_selected_stats() -> void:
	var unit := _edited_unit()
	if unit == null or not _original_definitions.has(unit.id):
		return
	unit.definition = _original_definitions[unit.id]
	_original_definitions.erase(unit.id)
	_after_stat_edit(unit)


func _own_definition(unit: Unit) -> void:
	if not _original_definitions.has(unit.id):
		_original_definitions[unit.id] = unit.definition
		unit.definition = unit.definition.duplicate()


func _after_stat_edit(unit: Unit) -> void:
	unit.hp = clampi(unit.hp, 1, unit.definition.max_hp)
	unit.moves_left = clampi(unit.moves_left, 0, unit.definition.move_points)
	var view: UnitView = _unit_views.get(unit.id)
	if view != null:
		view.set_shown_hp(unit.hp, unit.definition.max_hp)
	_finish_unit_edit()
	_sync_editor()


func _on_fire_mode_picked(index: int) -> void:
	set_selected_fire_mode(
		UnitDefinition.FIRE_INDIRECT if index == 1 else UnitDefinition.FIRE_DIRECT
	)


func _finish_unit_edit() -> void:
	if not is_built:
		return
	var view: UnitView = _unit_views.get(_selected_unit_id)
	if view != null:
		view.refresh_label()
	_after_edit()


## The selection changed: the editor follows it.
func _refresh_selection_ui() -> void:
	super()
	_sync_editor()


func _sync_editor() -> void:
	if _hp_spin == null or _fire_mode_picker == null:
		return
	var unit := _edited_unit()
	_editor_box.modulate.a = 1.0 if unit != null else 0.45
	_stats_box.modulate.a = 1.0 if unit != null else 0.45
	var controls: Array = [_hp_spin, _moves_spin, _dug_check, _ambush_check, _fire_mode_picker]
	controls.append_array(_stat_spins.values())
	for control: Control in controls:
		if control is SpinBox:
			(control as SpinBox).editable = unit != null
		elif control is OptionButton:
			(control as OptionButton).disabled = unit == null
		else:
			(control as CheckBox).disabled = unit == null
	_reset_stats_button.disabled = unit == null or not _original_definitions.has(unit.id)
	if unit == null:
		return
	for property: StringName in _stat_spins:
		(_stat_spins[property] as SpinBox).set_value_no_signal(unit.definition.get(property))
	_fire_mode_picker.select(1 if unit.definition.is_indirect() else 0)
	_hp_spin.max_value = unit.definition.max_hp
	_moves_spin.max_value = unit.definition.move_points
	_hp_spin.set_value_no_signal(unit.hp)
	_moves_spin.set_value_no_signal(unit.moves_left)
	_dug_check.set_pressed_no_signal(unit.dug)
	_ambush_check.set_pressed_no_signal(unit.ambush)


## Quality, scale and look changed: re-reads the switches and rebuilds the map and the unit views
## in place (placed units, their HP and the camera stay). Selection is dropped.
func rebuild_view() -> void:
	DevTunables.apply_look()
	_setup_graphics_quality()
	_wrecks.quality = quality
	_select(-1)
	for view: UnitView in _unit_views.values():
		view.queue_free()
	_unit_views.clear()
	_map_view.build(_sim.state.grid)
	for unit: Unit in _sim.state.units.values():
		_create_unit_view(unit)
	_apply_switches()
	_after_edit()


## Grid and the other view switches of the store onto the scene.
func _apply_switches() -> void:
	_map_view.set_grid_auto(DevTunables.grid_on)
	if _hud != null:
		_hud.action_bar().set_active(BattleHud.ACTION_GRID, DevTunables.grid_on)
	for key: StringName in _switch_boxes:
		var box: CheckBox = _switch_boxes[key]
		match key:
			&"grid":
				box.set_pressed_no_signal(DevTunables.grid_on)
			&"fps":
				box.set_pressed_no_signal(DevTunables.fps_overlay)
			&"camera":
				box.set_pressed_no_signal(DevTunables.unlock_camera)


func _on_quality_picked(index: int) -> void:
	DevTunables.quality_choice = index as DevTunables.QualityChoice
	rebuild_view()


func _on_scale_picked(index: int) -> void:
	DevTunables.true_size = index == 1
	rebuild_view()


func _on_look_picked(index: int) -> void:
	DevTunables.look_name = LookPreset.PRESETS.keys()[index]
	rebuild_view()


func _on_switch_toggled(on: bool, key: StringName) -> void:
	match key:
		&"grid":
			DevTunables.grid_on = on
		&"fps":
			DevTunables.fps_overlay = on
		&"camera":
			DevTunables.unlock_camera = on
	_apply_switches()


func _picked_definition() -> UnitDefinition:
	if _unit_picker == null or _unit_picker.item_count == 0:
		return null
	return _unit_picker.get_item_metadata(maxi(_unit_picker.selected, 0)) as UnitDefinition


func _panel_key(keycode: Key) -> bool:
	match keycode:
		KEY_1:
			_set_tool(Tool.COMMAND)
		KEY_2:
			_set_tool(Tool.PLACE)
		KEY_3:
			_set_tool(Tool.REMOVE)
		KEY_4:
			_refill_all()
		KEY_TAB:
			_pick_side(1 - _side)
		_:
			return false
	return true


func _set_tool(tool: Tool) -> void:
	_tool = tool
	if tool != Tool.COMMAND:
		_select(-1)
	_sync_panel()


func _pick_side(side: int) -> void:
	_side = side
	_fill_units()
	_sync_panel()


## Lists the roster of the current side's faction in the unit picker.
func _fill_units() -> void:
	_unit_picker.clear()
	var faction := _sim.state.faction_of(_side)
	if faction == null:
		return
	for definition in faction.roster:
		_unit_picker.add_item(definition.display_name)
		_unit_picker.set_item_metadata(_unit_picker.item_count - 1, definition)


func _on_faction_picked(index: int, side: int) -> void:
	var ids := FactionRegistry.ids()
	_sim.state.player_factions[side] = ids[index]
	_fill_units()
	_sync_panel()


func _build_panel() -> void:
	var frame := FramedPanel.new()
	frame.name = "ArenaPanel"
	frame.chamfers = Vector4(0.0, 12.0, 0.0, 12.0)
	frame.fill = UiPalette.PANEL_STRONG
	frame.tab_text = "ARENA"
	frame.tab_right_text = "DEV BENCH"
	frame.padding = Vector2(10.0, 8.0)
	frame.position = Vector2(12.0, 96.0)
	frame.theme = _panel_theme()
	var scroll := ScrollContainer.new()
	var height := get_viewport().get_visible_rect().size.y - 96.0 - 130.0
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH, clampf(height, 240.0, 760.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_right", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	margin.add_child(box)
	_build_tools(_section(box, "Tools", true))
	_build_armies(_section(box, "Armies", true))
	_build_editor(_section(box, "Selected unit", true))
	_build_stats(_section(box, "Unit stats", true))
	_build_view_switches(_section(box, "View", false))
	_build_effects(_section(box, "Effects", false))
	_status = MenuStyle.label("", HudTheme.mono(400), 11, UiPalette.HUD_MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	$HUD.add_child(frame)
	_fill_units()
	_sync_panel()


## Theme of the panel: the HUD theme plus dark inputs (spin boxes, pickers) in the HUD look.
func _panel_theme() -> Theme:
	var theme := HudTheme.build()
	var input := MenuStyle.box(Color(UiPalette.PANEL, 1.0), UiPalette.LINE)
	input.content_margin_top = 3
	input.content_margin_bottom = 3
	for kind: StringName in [&"LineEdit", &"OptionButton"]:
		theme.set_stylebox(&"normal", kind, input)
		theme.set_stylebox(&"read_only", kind, input)
		theme.set_stylebox(
			&"hover", kind, MenuStyle.box(Color(UiPalette.AMBER, 0.12), UiPalette.AMBER)
		)
		theme.set_stylebox(&"pressed", kind, input)
		theme.set_stylebox(&"focus", kind, MenuStyle.box(Color(0, 0, 0, 0), UiPalette.AMBER))
		theme.set_color(&"font_color", kind, UiPalette.HUD_TEXT)
		theme.set_font(&"font", kind, HudTheme.mono(500))
		theme.set_font_size(&"font_size", kind, 12)
	theme.set_font(&"font", &"CheckBox", HudTheme.mono(400))
	theme.set_font_size(&"font_size", &"CheckBox", 12)
	theme.set_color(&"font_color", &"CheckBox", UiPalette.HUD_TEXT)
	return theme


## A collapsible section: an amber caption bar that folds the returned body. Divider line above.
func _section(parent: VBoxContainer, title: String, open: bool) -> VBoxContainer:
	var line := ColorRect.new()
	line.color = UiPalette.LINE
	line.custom_minimum_size = Vector2(0.0, 1.0)
	parent.add_child(line)
	var head := Button.new()
	head.toggle_mode = true
	head.button_pressed = open
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_override(&"font", HudTheme.mono(600, 3))
	head.add_theme_font_size_override(&"font_size", 11)
	for state in [
		&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color"
	]:
		head.add_theme_color_override(state, UiPalette.AMBER)
	parent.add_child(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 4)
	body.visible = open
	parent.add_child(body)
	head.text = ("v  " if open else ">  ") + title.to_upper()
	head.toggled.connect(
		func(on: bool) -> void:
			body.visible = on
			head.text = ("v  " if on else ">  ") + title.to_upper()
	)
	return body


## A HUD button, compact for the panel.
func _button(text: String, toggle := false) -> Button:
	var button := MenuStyle.button(text, toggle)
	button.custom_minimum_size = Vector2(0.0, 28.0)
	button.add_theme_font_size_override(&"font_size", 12)
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


## A row "label | control": the label in muted mono, then the control filling the rest.
func _row(parent: Control, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var title := MenuStyle.label(label, HudTheme.mono(400), 11, UiPalette.HUD_MUTED)
	title.custom_minimum_size = Vector2(ROW_LABEL_WIDTH, 0.0)
	row.add_child(title)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


## Tool buttons, side switch and the bench actions.
func _build_tools(box: VBoxContainer) -> void:
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override(&"separation", 4)
	box.add_child(tools)
	for i in TOOL_NAMES.size():
		var button := _button(TOOL_NAMES[i], true)
		button.tooltip_text = "Key %d" % (i + 1)
		button.pressed.connect(_set_tool.bind(i))
		tools.add_child(button)
		_tool_buttons.append(button)
	_side_button = _button("")
	_side_button.pressed.connect(func() -> void: _pick_side(1 - _side))
	box.add_child(_side_button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 4)
	box.add_child(actions)
	var refill := _button("Refill (4)")
	refill.pressed.connect(_refill_all)
	actions.add_child(refill)
	var clear := _button("Clear all")
	clear.pressed.connect(_clear_all)
	actions.add_child(clear)
	_fire_again_button = _button("Fire again")
	_fire_again_button.pressed.connect(fire_again)
	box.add_child(_fire_again_button)
	_los_check = _add_check(box, "Ignore line of sight", set_ignore_line_of_sight)


## Factions of both sides and the unit to place.
func _build_armies(box: VBoxContainer) -> void:
	var ids := FactionRegistry.ids()
	for side in 2:
		var picker := OptionButton.new()
		picker.focus_mode = Control.FOCUS_NONE
		for id in ids:
			picker.add_item(String(id))
		picker.select(ids.find(_sim.state.player_factions[side]))
		picker.item_selected.connect(_on_faction_picked.bind(side))
		_row(box, "Side %d" % side, picker)
		_faction_pickers.append(picker)
	_unit_picker = OptionButton.new()
	_unit_picker.focus_mode = Control.FOCUS_NONE
	_row(box, "Place", _unit_picker)


## Unit editor: HP and moves spin boxes, dug-in and ambush check boxes for the selected unit.
func _build_editor(box: VBoxContainer) -> void:
	_editor_box = box
	_hp_spin = _add_spin(box, "HP", set_selected_hp, 1)
	_moves_spin = _add_spin(box, "Moves left", set_selected_moves, 0)
	_dug_check = _add_check(box, "Dug in", set_selected_dug)
	_ambush_check = _add_check(box, "Ambush", set_selected_ambush)
	_sync_editor()


## Stat editor: the selected unit gets its own copy of the definition (the shared data file and
## the other units of the type stay untouched); ranges are in metres, one step = one hex.
func _build_stats(box: VBoxContainer) -> void:
	_stats_box = box
	for spec: Array in STAT_SPECS:
		var property: StringName = spec[0]
		var spin := _add_spin(
			box, spec[1], set_selected_stat.bind(property), spec[2], spec[3], spec[4]
		)
		if spec[4] > 1:
			spin.suffix = "m"
		_stat_spins[property] = spin
	_fire_mode_picker = OptionButton.new()
	_fire_mode_picker.focus_mode = Control.FOCUS_NONE
	_fire_mode_picker.add_item("Direct")
	_fire_mode_picker.add_item("Indirect")
	_fire_mode_picker.item_selected.connect(_on_fire_mode_picked)
	_row(box, "Fire mode", _fire_mode_picker)
	_reset_stats_button = _button("Reset unit stats")
	_reset_stats_button.pressed.connect(reset_selected_stats)
	box.add_child(_reset_stats_button)
	_sync_editor()


func _add_spin(
	parent: Control, label: String, handler: Callable, low := 0, high := 99, step := 1
) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value_changed.connect(func(value: float) -> void: handler.call(int(value)))
	_row(parent, label, spin)
	return spin


func _add_check(parent: Control, label: String, handler: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = label
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool) -> void: handler.call(on))
	parent.add_child(check)
	return check


## The "View" section body: quality, unit scale, look, grid, FPS overlay, camera limits.
func _build_view_switches(inner: VBoxContainer) -> void:
	_add_picker(
		inner, "Quality", ["Auto", "LOW", "HIGH"], DevTunables.quality_choice, _on_quality_picked
	)
	_add_picker(
		inner,
		"Scale",
		["Current", "True size"],
		1 if DevTunables.true_size else 0,
		_on_scale_picked
	)
	var looks: Array = LookPreset.PRESETS.keys()
	var names: Array = []
	for look in looks:
		names.append(String(look))
	_add_picker(inner, "Look", names, looks.find(DevTunables.look_name), _on_look_picked)
	for entry in [
		[&"grid", "Grid"], [&"fps", "FPS overlay"], [&"camera", "Unlock camera distance"]
	]:
		var key: StringName = entry[0]
		var check := _add_check(inner, entry[1], _on_switch_toggled.bind(key))
		_switch_boxes[key] = check
	_apply_switches()


func _add_picker(
	parent: Control, label: String, items: Array, selected: int, handler: Callable
) -> void:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	for item in items:
		picker.add_item(item)
	picker.select(selected)
	picker.item_selected.connect(handler)
	_row(parent, label, picker)


## The "Effects" section body: slow motion and one slider per DevTunables key.
func _build_effects(box: VBoxContainer) -> void:
	_effects_box = box
	_add_slider(
		&"slow_motion",
		"Slow motion",
		DevTunables.SLOW_MOTION_MIN,
		DevTunables.SLOW_MOTION_MAX,
		0.05
	)
	for key: StringName in DevTunables.keys():
		var spec: Dictionary = DevTunables.SPECS[key]
		_add_slider(key, spec["label"], spec["min"], spec["max"], spec["step"])
	var reset_all := _button("Reset all effects")
	reset_all.pressed.connect(_reset_all_effects)
	_effects_box.add_child(reset_all)


func _add_slider(key: StringName, label: String, low: float, high: float, step: float) -> void:
	var head := HBoxContainer.new()
	var title := MenuStyle.label(label, HudTheme.mono(400), 11, UiPalette.HUD_MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var readout := MenuStyle.label("", HudTheme.mono(600), 11, UiPalette.AMBER)
	readout.custom_minimum_size = Vector2(44.0, 0.0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var reset := Button.new()
	reset.text = "x"
	reset.flat = true
	reset.tooltip_text = "Reset to default"
	reset.focus_mode = Control.FOCUS_NONE
	reset.add_theme_color_override(&"font_color", UiPalette.HUD_MUTED)
	reset.add_theme_color_override(&"font_hover_color", UiPalette.AMBER)
	reset.pressed.connect(_reset_one.bind(key))
	head.add_child(title)
	head.add_child(readout)
	head.add_child(reset)
	_effects_box.add_child(head)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = _slider_value(key)
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout.text = _format_value(slider.value)
	slider.value_changed.connect(_on_slider_changed.bind(key, readout))
	_effects_box.add_child(slider)
	_sliders[key] = {"slider": slider, "readout": readout}


func _slider_value(key: StringName) -> float:
	if key == &"slow_motion":
		return DevTunables.slow_motion()
	return DevTunables.get_value(key)


func _on_slider_changed(value: float, key: StringName, readout: Label) -> void:
	if key == &"slow_motion":
		DevTunables.set_slow_motion(value)
	else:
		DevTunables.set_value(key, value)
	readout.text = _format_value(value)


## The per-value reset button: back to the default, slider and readout follow.
func _reset_one(key: StringName) -> void:
	if key == &"slow_motion":
		DevTunables.set_slow_motion(1.0)
	else:
		DevTunables.reset(key)
	_show_value(key)


func _reset_all_effects() -> void:
	DevTunables.reset_all()
	DevTunables.set_slow_motion(1.0)
	for key: StringName in _sliders:
		_show_value(key)


## Moves the slider of `key` to the stored value without storing it again.
func _show_value(key: StringName) -> void:
	var slider: HSlider = _sliders[key]["slider"]
	slider.set_value_no_signal(_slider_value(key))
	_sliders[key]["readout"].text = _format_value(slider.value)


static func _format_value(value: float) -> String:
	return "%d" % int(value) if is_equal_approx(value, roundf(value)) else "%.3g" % value


func _sync_panel() -> void:
	if _status == null:
		return
	_fire_again_button.disabled = not can_fire_again()
	for i in _tool_buttons.size():
		_tool_buttons[i].button_pressed = i == _tool
	_side_button.text = (
		("Side %d: %s (Tab)" % [_side, _sim.state.player_factions[_side]]).to_upper()
	)
	_status.text = (
		"Turn %d, side %d commands.\nPlace: left click on a tile,\nright click leaves the tool."
		% [_sim.state.turn, _sim.state.current_player]
	)
