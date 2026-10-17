extends Node3D
## Battle scene: connects the simulation (GameSimulation) with the 3D view and player input.
## Rule: this script only translates input into commands and events into animations – no game rules.

const HUMAN_PLAYER := 0
const MAP_SEED := 12345
const MAP_WIDTH := 12
const MAP_HEIGHT := 10
const INFANTRY := preload("res://data/units/infantry.tres")
const CAVALRY := preload("res://data/units/cavalry.tres")
const INFO_PANEL_MARGIN := 16
const HUD_FONT_SIZE := 18

var _sim: GameSimulation
var _ai := AiPlayer.new()
var _unit_views: Dictionary = {}  # unit id -> UnitView
var _selected_unit_id := -1
var _info_panel: PanelContainer
var _info_label: Label
var _hovered_hex: Variant = null  # Vector2i of the tile under the cursor, or null
var _last_camera_transform := Transform3D()
# Event playback: the simulation runs ahead synchronously, the view replays its events one by one.
var _event_queue := EventQueue.new()
var _playback_scheduled := false  # _start_burst() is deferred to the end of the frame
var _playing := false  # an event animation is running
var _burst_speed := 1.0  # fixed from _start_burst() until the queue drains

@onready var _map_view: MapView = $MapView
@onready var _units_root: Node3D = $Units
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _status_label: Label = $HUD/StatusLabel


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = MAP_SEED
	var state := GameState.new(MapGenerator.generate(MAP_WIDTH, MAP_HEIGHT, rng), 2, MAP_SEED)
	_spawn_start_units(state)

	_sim = GameSimulation.new(state)
	_sim.event_emitted.connect(_on_event)
	_sim.command_rejected.connect(_on_command_rejected)

	_build_info_panel()
	_map_view.build(state.grid)
	_camera_rig.position = _map_view.center()
	for unit: Unit in state.units.values():
		_create_unit_view(unit)
	_update_status()
	_refresh_selection_ui()


## The camera can move under a still cursor (keys, wheel) – re-pick the hovered tile then.
func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.global_transform == _last_camera_transform:
		return
	_last_camera_transform = camera.global_transform
	_on_mouse_motion(get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_on_mouse_motion(motion.position)
		return
	if _is_playing_events():
		return  # clicks and Enter are dropped (not buffered) while animations play
	if _sim.state.winner != -1 or _sim.state.current_player != HUMAN_PLAYER:
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		var coord: Variant = _pick_hex(mouse.position)
		if coord != null:
			_on_hex_clicked(coord)
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ENTER:
		_end_human_turn()


func _spawn_start_units(state: GameState) -> void:
	var spawns := [
		[0, INFANTRY, 1, 3],
		[0, CAVALRY, 1, 5],
		[0, INFANTRY, 1, 7],
		[1, INFANTRY, MAP_WIDTH - 2, 2],
		[1, CAVALRY, MAP_WIDTH - 2, 4],
		[1, INFANTRY, MAP_WIDTH - 2, 6],
	]
	for spawn: Array in spawns:
		var coord := MapGenerator.offset_to_axial(spawn[2], spawn[3])
		state.grid.set_terrain(coord, Terrain.Type.PLAINS)
		state.add_unit(spawn[0], spawn[1], coord)


func _create_unit_view(unit: Unit) -> void:
	var view := UnitView.new()
	_units_root.add_child(view)
	view.setup(unit, _map_view.tile_top_position(unit.coord))
	_unit_views[unit.id] = view


## Returns the Vector2i of the tile under the cursor, or null.
func _pick_hex(screen_position: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var hit: Variant = Plane(Vector3.UP, MapView.PICK_HEIGHT).intersects_ray(origin, direction)
	if hit == null:
		return null
	var coord := Hex.from_world(hit, _map_view.hex_size)
	if not _sim.state.grid.has_tile(coord):
		return null
	return coord


## Tracks the hovered tile; the path preview is recomputed only when it changes.
func _on_mouse_motion(screen_position: Vector2) -> void:
	_set_hovered_hex(_pick_hex(screen_position))


func _set_hovered_hex(coord: Variant) -> void:
	if typeof(coord) == typeof(_hovered_hex) and coord == _hovered_hex:
		return
	_hovered_hex = coord
	_refresh_path_preview()


## Path and cost come from HexGrid.path_to()/reachable() – the view only draws them.
func _refresh_path_preview() -> void:
	var state := _sim.state
	var unit := state.get_unit(_selected_unit_id)
	if (
		_hovered_hex == null
		or unit == null
		or not unit.is_alive()
		or unit.owner_id != HUMAN_PLAYER
		or _is_playing_events()
		or state.current_player != HUMAN_PLAYER
		or state.winner != -1
	):
		_map_view.clear_path()
		return
	var target: Vector2i = _hovered_hex
	var blocked := state.occupied()
	var path := state.grid.path_to(unit.coord, target, unit.moves_left, blocked)
	if path.is_empty():
		_map_view.clear_path()
		return
	var cost: int = state.grid.reachable(unit.coord, unit.moves_left, blocked)[target]
	_map_view.show_path(path, "%d/%d" % [cost, unit.moves_left])


func _on_hex_clicked(coord: Vector2i) -> void:
	var clicked := _sim.state.unit_at(coord)
	if clicked != null and clicked.owner_id == HUMAN_PLAYER:
		_select(clicked.id)
	elif clicked != null and _selected_unit_id != -1:
		_sim.execute(AttackCommand.new(_selected_unit_id, clicked.id))
	elif _selected_unit_id != -1:
		_sim.execute(MoveUnitCommand.new(_selected_unit_id, coord))
	# The selection UI is refreshed when the resulting events have been played (_on_queue_drained).


## Runs the end of the human turn and every AI turn synchronously; their events are queued in
## _on_event and replayed afterwards as one burst.
func _end_human_turn() -> void:
	_sim.execute(EndTurnCommand.new())
	while _sim.state.winner == -1 and _sim.state.current_player != HUMAN_PLAYER:
		_ai.take_turn(_sim)


func _select(unit_id: int) -> void:
	if _unit_views.has(_selected_unit_id):
		(_unit_views[_selected_unit_id] as UnitView).set_selected(false)
	_selected_unit_id = unit_id
	if _unit_views.has(unit_id):
		(_unit_views[unit_id] as UnitView).set_selected(true)
	_refresh_selection_ui()


## Everything that depends on the selected unit: move highlights, the info panel
## and the path preview (recomputed for the hovered tile; it hides itself when there is
## no valid target, e.g. after a move, on turn end or game over).
func _refresh_selection_ui() -> void:
	_refresh_path_preview()
	_refresh_highlights()
	_refresh_unit_info()


func _refresh_highlights() -> void:
	var unit := _sim.state.get_unit(_selected_unit_id)
	if unit == null:
		_map_view.clear_highlights()
		return
	var reach := _sim.state.grid.reachable(unit.coord, unit.moves_left, _sim.state.occupied())
	reach.erase(unit.coord)
	var coords: Array[Vector2i] = []
	coords.assign(reach.keys())
	_map_view.show_highlights(coords)
	_refresh_attack_targets(unit)


## Red markers on enemies the selected unit can attack now (ids from AttackCommand, tiles here).
## valid_targets is empty on the AI's turn and after game over, so no extra guards are needed.
func _refresh_attack_targets(unit: Unit) -> void:
	var state := _sim.state
	var coords: Array[Vector2i] = []
	for id: int in AttackCommand.valid_targets(state, unit.id):
		coords.append(state.get_unit(id).coord)
	_map_view.show_attack_targets(coords)


## Bottom-left HUD panel with the selected unit's stats (text from UnitInfo).
func _build_info_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.name = "UnitInfoPanel"
	# Clicks over the panel must still reach the map (_unhandled_input).
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_label = Label.new()
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_label.add_theme_font_size_override(&"font_size", HUD_FONT_SIZE)
	_info_panel.add_child(_info_label)
	$HUD.add_child(_info_panel)
	_info_panel.hide()


func _refresh_unit_info() -> void:
	var unit := _sim.state.get_unit(_selected_unit_id)
	if unit == null or not unit.is_alive():
		_info_panel.hide()
		return
	_info_label.text = "\n".join(UnitInfo.lines(unit))
	_info_panel.show()
	# Re-anchor after the text changes so the panel hugs the bottom-left corner.
	_info_panel.reset_size()
	_info_panel.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, INFO_PANEL_MARGIN
	)


## Events are only queued here; playback starts deferred, so everything emitted in this frame
## (e.g. a whole AI turn) is queued before the burst speed is computed.
func _on_event(event: Dictionary) -> void:
	_event_queue.push(event)
	if not _playing and not _playback_scheduled:
		_playback_scheduled = true
		_start_burst.call_deferred()


func _is_playing_events() -> bool:
	return _playing or _playback_scheduled or not _event_queue.is_empty()


func _start_burst() -> void:
	_playback_scheduled = false
	_playing = true
	_burst_speed = _event_queue.begin_burst()
	# Highlights and the path preview describe the state before the burst – hide them meanwhile.
	_map_view.clear_highlights()
	_map_view.clear_path()
	_play_next_event()


## Plays queued events until one of them starts an animation; that animation's `finished`
## calls this again. Instant events are handled in the loop (no recursion).
func _play_next_event() -> void:
	while not _event_queue.is_empty():
		var tween := _play_event(_event_queue.pop())
		if tween != null:
			tween.set_speed_scale(_burst_speed)
			tween.finished.connect(_play_next_event, CONNECT_ONE_SHOT)
			return
	_playing = false
	_burst_speed = 1.0
	_on_queue_drained()


## Starts the animation of one event and returns its tween, or null for instant events.
## Uses only event fields (the simulation state may already be further ahead).
func _play_event(event: Dictionary) -> Tween:
	match event["type"]:
		&"unit_moved":
			var view: UnitView = _unit_views.get(event["unit_id"])
			if view != null:
				return view.move_to(_map_view.tile_top_position(event["to"]))
		&"unit_attacked":
			var target: UnitView = _unit_views.get(event["target_id"])
			if target != null:
				return target.play_hit(event["target_hp"])
		&"unit_died":
			return _on_unit_died(event["unit_id"])
		&"turn_ended":
			if event["player"] == HUMAN_PLAYER:
				_select(-1)
		&"turn_started":
			_show_turn_status(event["turn"], event["player"])
		&"game_over":
			_select(-1)
	return null


func _on_unit_died(unit_id: int) -> Tween:
	if unit_id == _selected_unit_id:
		_select(-1)
	var view: UnitView = _unit_views.get(unit_id)
	if view == null:
		return null
	# Forget the view right away: it frees itself at the end of the death tween.
	_unit_views.erase(unit_id)
	return view.play_death()


## The view has caught up with the simulation: refresh everything derived from the state.
func _on_queue_drained() -> void:
	var selected := _sim.state.get_unit(_selected_unit_id)
	if selected != null and (not selected.is_alive() or not _unit_views.has(selected.id)):
		_select(-1)
	_update_status()
	_refresh_selection_ui()


func _on_command_rejected(command: Command, reason: String) -> void:
	print("Rejected %s: %s" % [command.get_script().get_global_name(), reason])


func _update_status() -> void:
	var state := _sim.state
	if state.winner != -1:
		var result := "Victory!" if state.winner == HUMAN_PLAYER else "Defeat!"
		_status_label.text = "%s\nTurn %d" % [result, state.turn]
		return
	_show_turn_status(state.turn, state.current_player)


## Status text for an ongoing game; called with event data during playback.
func _show_turn_status(turn: int, player: int) -> void:
	var who := "Your turn" if player == HUMAN_PLAYER else "AI turn"
	_status_label.text = (
		"Turn %d · %s\nLMB – select/move/attack · Enter – end turn · WASD/QE/wheel – camera"
		% [turn, who]
	)
