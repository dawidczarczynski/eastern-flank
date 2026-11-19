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
const TOOL_NAMES := ["Command (1)", "Place (2)", "Remove (3)"]

var _tool := Tool.COMMAND
var _side := 0
var _tool_buttons: Array[Button] = []
var _faction_pickers: Array[OptionButton] = []
var _unit_picker: OptionButton
var _status: Label
var _side_button: Button


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
	await super._ready()
	if is_built:
		_build_panel()


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


func _after_edit() -> void:
	_sim.state.record_starting_hp()
	_refresh_hud()
	_refresh_selection_ui()
	_sync_panel()


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
	var panel := PanelContainer.new()
	panel.name = "ArenaPanel"
	panel.position = Vector2(12.0, 96.0)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "ARENA (dev bench)"
	box.add_child(title)
	for i in TOOL_NAMES.size():
		var button := Button.new()
		button.text = TOOL_NAMES[i]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_set_tool.bind(i))
		box.add_child(button)
		_tool_buttons.append(button)
	_side_button = Button.new()
	_side_button.focus_mode = Control.FOCUS_NONE
	_side_button.pressed.connect(func() -> void: _pick_side(1 - _side))
	box.add_child(_side_button)
	var ids := FactionRegistry.ids()
	for side in 2:
		var picker := OptionButton.new()
		picker.focus_mode = Control.FOCUS_NONE
		for id in ids:
			picker.add_item(String(id))
		picker.select(ids.find(_sim.state.player_factions[side]))
		picker.item_selected.connect(_on_faction_picked.bind(side))
		box.add_child(picker)
		_faction_pickers.append(picker)
	_unit_picker = OptionButton.new()
	_unit_picker.focus_mode = Control.FOCUS_NONE
	box.add_child(_unit_picker)
	var refill := Button.new()
	refill.text = "Refill all (4)"
	refill.focus_mode = Control.FOCUS_NONE
	refill.pressed.connect(_refill_all)
	box.add_child(refill)
	var clear := Button.new()
	clear.text = "Clear all"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(_clear_all)
	box.add_child(clear)
	_status = Label.new()
	box.add_child(_status)
	$HUD.add_child(panel)
	_fill_units()
	_sync_panel()


func _sync_panel() -> void:
	if _status == null:
		return
	for i in _tool_buttons.size():
		_tool_buttons[i].button_pressed = i == _tool
	_side_button.text = "Side %d: %s (Tab)" % [_side, _sim.state.player_factions[_side]]
	_status.text = (
		"Turn %d, side %d commands.\nPlace: left click on a tile,\nright click leaves the tool."
		% [_sim.state.turn, _sim.state.current_player]
	)
