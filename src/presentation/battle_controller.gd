extends Node3D
## Battle scene: connects the simulation (GameSimulation) with the 3D view and player input.
## Rule: this script only translates input into commands and events into animations – no game rules.

const HUMAN_PLAYER := 0
const MAP_SEED := 12345
const BOTTOM_LEFT_MARGIN := 16
## Time the launcher takes to turn towards its target before a volley (seconds at speed 1).
const AIM_DURATION := 0.5
## Turntable launchers (Homar-K) aim the launcher instead: the pod rises on its actuators, the
## turntable turns to the target, and after the salvo both return to the stowed pose
## (seconds at speed 1, each way).
const LAUNCHER_RAISE_DURATION := 0.9
const LAUNCHER_TRAVERSE_DURATION := 0.9

## Active graphics quality switches (GraphicsQuality.features); views read them before use.
var quality: Dictionary = {}
var _sim: GameSimulation
var _ai := AiPlayer.new()
var _unit_views: Dictionary = {}  # unit id -> UnitView
var _selected_unit_id := -1
var _hovered_unit_id := -1
var _hud_root: Control
var _unit_popup: UnitPopup
var _popup_unit_id := -1  # unit shown on the hover card, -1 = hidden
var _hud: BattleHud
var _terrain_panel: TerrainPanel
var _hovered_hex: Variant = null  # Vector2i of the tile under the cursor, or null
var _last_camera_transform := Transform3D()
# Event playback: the simulation runs ahead synchronously, the view replays its events one by one.
var _event_queue := EventQueue.new()
var _playback_scheduled := false  # _start_burst() is deferred to the end of the frame
var _playing := false  # an event animation is running
var _burst_speed := 1.0  # fixed from _start_burst() until the queue drains
var _fx_rng := RandomNumberGenerator.new()  # view-local (volley scatter), never GameState.rng

var _marks := GroundMarksView.new()  # ground decals (TASK-058), fed while animations play
var _event_serial := 0  # played events so far: the view-local seed of the marks

@onready var _map_view: MapView = $MapView
@onready var _units_root: Node3D = $Units
@onready var _camera_rig: CameraRig = $CameraRig


func _ready() -> void:
	Engine.max_fps = FramePacing.max_fps(true)
	_setup_graphics_quality()
	var state := Scenario.default_battle(MAP_SEED)
	_sim = GameSimulation.new(state)
	_sim.event_emitted.connect(_on_event)
	_sim.command_rejected.connect(_on_command_rejected)

	_build_hud_root()
	_build_bottom_left_stack()
	_map_view.build(state.grid)
	_marks.name = "GroundMarks"
	_marks.setup(quality.get("decals_max", 0))
	add_child(_marks)
	_camera_rig.set_bounds(_map_bounds())
	_camera_rig.set_ground_query(_map_view.visible_ground_height)
	var center := _map_view.center()
	_camera_rig.set_target(Vector2(center.x, center.z))
	_camera_rig.clicked.connect(_on_camera_clicked)
	for unit: Unit in state.units.values():
		_create_unit_view(unit)
	_refresh_hud()
	_refresh_selection_ui()


## Throttles the frame rate while the window is in the background.
func _notification(what: int) -> void:
	FramePacing.apply_notification(what)


## Picks LOW/HIGH (`--quality=` user argument, else detected from renderer and adapter) and applies
## the environment, sun and viewport switches this scene owns.
func _setup_graphics_quality() -> void:
	var override := GraphicsQuality.parse_override(OS.get_cmdline_user_args())
	var adapter := RenderingServer.get_video_adapter_name()
	var level: GraphicsQuality.Level
	var source: String
	if override >= 0:
		level = override as GraphicsQuality.Level
		source = "override"
	else:
		level = GraphicsQuality.detect(RenderingServer.get_current_rendering_method(), adapter)
		source = "auto: %s" % adapter
	quality = GraphicsQuality.features(level)
	print("Graphics quality: %s (%s)" % [GraphicsQuality.level_name(level), source])
	var world_env := $WorldEnvironment as WorldEnvironment
	# Own copy: the resource is shared and cached, runtime switches must not leak into it.
	world_env.environment = world_env.environment.duplicate() as Environment
	GraphicsQuality.apply_environment(world_env.environment, quality)
	GraphicsQuality.apply_sun($Sun as DirectionalLight3D, quality)
	GraphicsQuality.apply_viewport(get_viewport(), quality)
	_map_view.quality = quality


## The camera can move under a still cursor (keys, wheel) – re-pick the hovered tile then.
func _process(_delta: float) -> void:
	_update_unit_popup()
	_map_view.set_camera_distance(_camera_rig.distance())
	_map_view.set_camera_target(_camera_rig.target())
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
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F5:  # saving only reads the history, so it works at any time
		_save_match()
		return
	if (
		key.keycode == KEY_G
		and not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed)
		and not _text_input_has_focus()
	):  # view setting, like camera keys
		_map_view.cycle_grid_mode()
		return
	if not _input_allowed():
		return
	if key.keycode == KEY_ENTER:
		_end_human_turn()
	elif key.keycode == KEY_ESCAPE:
		_select(-1)


func _text_input_has_focus() -> bool:
	var viewport := get_viewport()
	var focus := viewport.gui_get_focus_owner() if viewport != null else null
	return focus is LineEdit or focus is TextEdit


## Screenshot debug hook (tools/screenshot.gd): selects a unit and hovers a tile near it.
func debug_select_and_hover(unit_id: int) -> void:
	_select(unit_id)
	var unit := _sim.state.get_unit(unit_id)
	if unit != null:
		_set_hovered_hex(unit.coord + Vector2i(2, 0))
	_update_unit_popup()  # _process is disabled in the screenshot tool


## Screenshot debug hook (tools/screenshot.gd): points the camera at a unit's tile.
func debug_focus_camera(
	unit_id: int, yaw: float, distance: float, pitch_offset: float = 0.0
) -> void:
	var unit := _sim.state.get_unit(unit_id)
	if unit == null:
		push_error("debug_focus_camera: no unit %d" % unit_id)
		return
	var focus := _map_view.tile_top_position(unit.coord)
	_camera_rig.set_view(Vector2(focus.x, focus.z), yaw, distance)
	_camera_rig.set_pitch_offset(pitch_offset)
	for view: UnitView in _unit_views.values():
		view.refresh_label()  # _process is disabled in the screenshot tool
	debug_build_grass()


## Screenshot debug hook (tools/screenshot.gd, SCREENSHOT_FOCUS): points the camera at a world
## point (XZ), e.g. the middle of a forest for the frame-time probe.
func debug_focus_point(target: Vector2, yaw: float, distance: float) -> void:
	_camera_rig.set_view(target, yaw, distance)
	for view: UnitView in _unit_views.values():
		view.refresh_label()  # _process is disabled in the screenshot tool
	debug_build_grass()


## Screenshot tool: _process is disabled, so build the grass chunks around the camera now.
func debug_build_grass() -> void:
	_map_view.set_camera_target(_camera_rig.target())
	_map_view.grass().update(1000)


## Writes the command history (+ seed) to MatchSaver.LAST_MATCH_PATH and prints where it went.
func _save_match() -> void:
	var record := MatchRecord.from_simulation(_sim, MAP_SEED)
	if MatchSaver.save(record) == OK:
		var path := ProjectSettings.globalize_path(MatchSaver.LAST_MATCH_PATH)
		print("Match saved (%d commands): %s" % [record.commands.size(), path])


## A click that never became a camera drag: LMB selects/moves/attacks, RMB deselects.
func _on_camera_clicked(screen_position: Vector2, button: MouseButton) -> void:
	if not _input_allowed():
		return
	if button == MOUSE_BUTTON_RIGHT:
		_select(-1)
		return
	var coord: Variant = _pick_hex(screen_position)
	if coord != null:
		_on_hex_clicked(coord)


## Clicks and keys are dropped (not buffered) while animations play or it isn't the human's turn.
func _input_allowed() -> bool:
	if _is_playing_events():
		return false
	return _sim.state.winner == -1 and _sim.state.current_player == HUMAN_PLAYER


func _map_bounds() -> Rect2:
	var centers: Array[Vector3] = []
	for c in _sim.state.grid.coords():
		centers.append(Hex.to_world(c, _map_view.hex_size))
	return CameraMath.map_bounds(centers, _map_view.hex_size)


func _create_unit_view(unit: Unit) -> void:
	var view := UnitView.new()
	_units_root.add_child(view)
	view.quality = quality
	view.terrain_at = _terrain_at
	view.setup(
		unit,
		_sim.state.faction_of(unit.owner_id),
		_map_view.tile_top_position(unit.coord),
		_hud_root,
		_map_view.mesh_height_at
	)
	_unit_views[unit.id] = view


## Terrain type of the tile under (x, z); plains off the map (the dust colour under a vehicle).
func _terrain_at(x: float, z: float) -> int:
	var grid := _sim.state.grid
	var coord := Hex.from_world(Vector3(x, 0.0, z), _map_view.hex_size)
	return int(grid.get_terrain(coord)) if grid.has_tile(coord) else Terrain.Type.PLAINS


## Returns the Vector2i of the tile under the cursor, or null.
func _pick_hex(screen_position: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	return _map_view.pick_coord(origin, direction)


## Tracks the hovered tile; the path preview is recomputed only when it changes.
func _on_mouse_motion(screen_position: Vector2) -> void:
	_set_hovered_hex(_pick_hex(screen_position))


func _set_hovered_hex(coord: Variant) -> void:
	if typeof(coord) == typeof(_hovered_hex) and coord == _hovered_hex:
		return
	_hovered_hex = coord
	_map_view.set_hover(coord)
	_refresh_hovered_unit()
	_refresh_path_preview()


## Path and cost come from HexGrid.path_to()/reachable() – the view only draws them.
## Also feeds the terrain panel (hovered tile + path cost, -1 without a valid path).
func _refresh_path_preview() -> void:
	var cost := _draw_path_preview()
	if _hovered_hex == null:
		_terrain_panel.hide()
		return
	var unit := _sim.state.get_unit(_selected_unit_id)
	var moves_left := unit.moves_left if unit != null else 0
	_terrain_panel.show_tile(
		TerrainPanelModel.build(_sim.state.grid, _hovered_hex, cost, moves_left)
	)


## Draws the path dots to the hovered tile; returns the path cost or -1 when there is none.
func _draw_path_preview() -> int:
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
		return -1
	var target: Vector2i = _hovered_hex
	var blocked := state.occupied()
	var path := state.grid.path_to(unit.coord, target, unit.moves_left, blocked)
	if path.is_empty():
		_map_view.clear_path()
		return -1
	var cost: int = state.grid.reachable(unit.coord, unit.moves_left, blocked)[target]
	_map_view.show_path(unit.coord, path)
	return cost


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
	_refresh_unit_markers()
	_refresh_path_preview()
	_refresh_highlights()


## Marks the unit under the cursor (brighter marker fill).
func _refresh_hovered_unit() -> void:
	var id := -1
	if _hovered_hex != null:
		var unit := _sim.state.unit_at(_hovered_hex)
		if unit != null and _unit_views.has(unit.id):
			id = unit.id
	if id == _hovered_unit_id:
		return
	if _unit_views.has(_hovered_unit_id):
		(_unit_views[_hovered_unit_id] as UnitView).set_hovered(false)
	_hovered_unit_id = id
	if _unit_views.has(id):
		(_unit_views[id] as UnitView).set_hovered(true)
	_refresh_range_overlay()


## Shows the attack range of the selected unit, or – with nothing selected – of the hovered unit
## (own or enemy), when its range is at least 2. Tiles come from AttackCommand.tiles_in_range.
func _refresh_range_overlay() -> void:
	var unit := _sim.state.get_unit(_selected_unit_id)
	if unit == null:
		unit = _sim.state.get_unit(_hovered_unit_id)
	if (
		unit == null
		or not unit.is_alive()
		or unit.definition.attack_range < 2
		or _is_playing_events()
		or _sim.state.winner != -1
	):
		_map_view.clear_attack_range()
		return
	_map_view.show_attack_range(AttackCommand.tiles_in_range(_sim.state, unit))


## "Done" dimming applies to units that have nothing left to do on their owner's turn.
func _refresh_unit_markers() -> void:
	var state := _sim.state
	for id: int in _unit_views:
		var unit := state.get_unit(id)
		var done := (
			unit != null
			and unit.is_alive()
			and unit.owner_id == state.current_player
			and UnitStatus.is_done(state, unit)
		)
		(_unit_views[id] as UnitView).set_done(done)


func _refresh_highlights() -> void:
	var unit := _sim.state.get_unit(_selected_unit_id)
	if unit == null:
		_map_view.clear_highlights()
		_refresh_range_overlay()
		return
	var reach := _sim.state.grid.reachable(unit.coord, unit.moves_left, _sim.state.occupied())
	reach.erase(unit.coord)
	var coords: Array[Vector2i] = []
	coords.assign(reach.keys())
	_map_view.show_reach(coords, UiPalette.faction_color(_sim.state, unit.owner_id), unit.coord)
	_refresh_attack_targets(unit)
	_refresh_range_overlay()


## Red markers on enemies the selected unit can attack now (ids from AttackCommand, tiles here).
## valid_targets is empty on the AI's turn and after game over, so no extra guards are needed.
func _refresh_attack_targets(unit: Unit) -> void:
	var state := _sim.state
	var coords: Array[Vector2i] = []
	for id: int in AttackCommand.valid_targets(state, unit.id):
		coords.append(state.get_unit(id).coord)
	_map_view.show_attack_targets(coords)


## Full-rect themed root under the HUD layer; HUD elements live below it and ignore the mouse.
func _build_hud_root() -> void:
	_hud_root = Control.new()
	_hud_root.name = "Root"
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.theme = HudTheme.build()
	$HUD.add_child(_hud_root)
	_hud = BattleHud.new()
	_hud_root.add_child(_hud)
	_hud.setup(HUMAN_PLAYER)
	_hud.end_turn_pressed.connect(_on_end_turn_pressed)
	_hud_root.add_child(FpsCounter.new())


## Bottom-left stack (VBox, bottom-anchored) holding the terrain panel, plus the unit hover
## card (positioned next to the cursor, drawn above everything else in the HUD).
func _build_bottom_left_stack() -> void:
	var stack := VBoxContainer.new()
	stack.name = "BottomLeftStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_END
	stack.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, BOTTOM_LEFT_MARGIN
	)
	stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud_root.add_child(stack)
	_terrain_panel = TerrainPanel.new()
	stack.add_child(_terrain_panel)
	_unit_popup = UnitPopup.new()
	_hud_root.add_child(_unit_popup)


## Shows the hover card while the hovered tile holds a living unit, follows the cursor and hides
## during a camera drag, event playback and after game over. The card is rebuilt when the shown
## unit changes (and after every event burst, because hiding resets it).
func _update_unit_popup() -> void:
	var state := _sim.state
	var unit: Unit = null
	if (
		_hovered_hex != null
		and state.winner == -1
		and not _camera_rig.is_dragging()
		and not _is_playing_events()
	):
		unit = state.unit_at(_hovered_hex)
	if unit == null or not unit.is_alive():
		_popup_unit_id = -1
		_unit_popup.hide()
		return
	if unit.id != _popup_unit_id or not _unit_popup.visible:
		_popup_unit_id = unit.id
		_unit_popup.show_model(UnitPopupModel.build(state, unit, HUMAN_PLAYER))
	_unit_popup.position = UnitPopupModel.placement(
		get_viewport().get_mouse_position(),
		get_viewport().get_visible_rect().size,
		_unit_popup.card_size()
	)


## Events are only queued here; playback starts deferred, so everything emitted in this frame
## (e.g. a whole AI turn) is queued before the burst speed is computed.
func _on_event(event: Dictionary) -> void:
	if event["type"] == &"game_over":
		_save_match()  # the winning command is already in the history
	_event_queue.push(_annotate(event))
	_hud.set_end_enabled(false)  # the queue is non-empty from now on
	if not _playing and not _playback_scheduled:
		_playback_scheduled = true
		_start_burst.call_deferred()


## Rocket volleys play longer than a plain hit: the queue learns the duration from the
## annotation (the simulation's event is copied, not modified).
func _annotate(event: Dictionary) -> Dictionary:
	if event["type"] == &"unit_attacked" and _fires_volley(event["attacker_id"]):
		var shooter: UnitView = _unit_views.get(event["attacker_id"])
		var launcher := shooter != null and shooter.has_launcher()
		var annotated := EventQueue.with_view_duration(event, _volley_event_duration(launcher))
		annotated[EventQueue.VIEW_FX_KEY] = EventQueue.FX_ROCKET_VOLLEY
		return annotated
	return event


func _fires_volley(attacker_id: int) -> bool:
	var attacker := _sim.state.get_unit(attacker_id)
	return attacker != null and UnitModels.fires_volley(attacker.definition)


## Aim + salvo + impact; the hit reaction starts with the last impact and ends with the flashes.
## A turntable `launcher` raises and traverses before the salvo and stows after it.
static func _volley_event_duration(launcher: bool) -> float:
	if launcher:
		return (
			2.0 * (LAUNCHER_RAISE_DURATION + LAUNCHER_TRAVERSE_DURATION)
			+ RocketVolley.total_duration()
		)
	return AIM_DURATION + RocketVolley.total_duration()


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
	_event_serial += 1
	match event["type"]:
		&"unit_moved":
			var view: UnitView = _unit_views.get(event["unit_id"])
			if view != null:
				var points := _move_points(event)
				_play_track_marks(event["unit_id"], points, view.facing_yaw())
				return view.move_along(points, _map_view.surface().ground_height)
		&"unit_attacked":
			var target: UnitView = _unit_views.get(event["target_id"])
			var shooter: UnitView = _unit_views.get(event["attacker_id"])
			if (
				target != null
				and shooter != null
				and event.get(EventQueue.VIEW_FX_KEY) == EventQueue.FX_ROCKET_VOLLEY
			):
				return _play_volley(shooter, target, event["target_hp"], event)
			if target != null:
				_add_impact_marks(event, target, shooter)
				return target.play_hit(event["target_hp"])
		&"unit_died":
			return _on_unit_died(event["unit_id"])
		&"turn_ended":
			if event["player"] == HUMAN_PLAYER:
				_select(-1)
		&"turn_started":
			_hud.on_turn_started(_sim.state, event["turn"], event["player"])
		&"game_over":
			_select(-1)
	return null


## Turn the launcher towards the target, fire the salvo from its tubes, then the hit reaction.
## One tween lasts the whole event (_volley_event_duration), so the queue waits for all of it.
func _play_volley(shooter: UnitView, target: UnitView, target_hp: int, event: Dictionary) -> Tween:
	var aim_point := target.global_position
	var tween := create_tween()
	var traverse := 0.0
	if shooter.has_launcher():
		traverse = shooter.launcher_traverse_towards(aim_point)
		_tween_launcher(tween, shooter, Vector2.ZERO, Vector2(0.0, 1.0), LAUNCHER_RAISE_DURATION)
		_tween_launcher(
			tween, shooter, Vector2(0.0, 1.0), Vector2(traverse, 1.0), LAUNCHER_TRAVERSE_DURATION
		)
	else:
		var from_yaw := shooter.facing_yaw()
		var to_yaw := shooter.yaw_towards(aim_point)
		tween.tween_method(
			func(f: float) -> void: shooter.set_facing_yaw(lerp_angle(from_yaw, to_yaw, f)),
			0.0,
			1.0,
			AIM_DURATION
		)
	var origins := shooter.launch_points()
	if origins.is_empty():
		origins.append(shooter.global_position + Vector3(0.0, 0.4, 0.0))
	var impact_point := aim_point + Vector3(0.0, 0.15, 0.0)
	var volley := RocketVolley.new()
	volley.name = "RocketVolley"
	add_child(volley)  # in the tree from the start (freed with the controller if the tween dies)
	tween.tween_callback(
		func() -> void:
			# Tubes move with the turned model: read their positions after aiming.
			var tubes := shooter.launch_points()
			volley.setup(tubes if not tubes.is_empty() else origins, impact_point, _fx_rng)
	)
	tween.tween_method(
		volley.update, 0.0, RocketVolley.total_duration(), RocketVolley.total_duration()
	)
	# The hit reaction starts with the last impact.
	tween.parallel()
	var hit_step := tween.tween_callback(_play_volley_hit.bind(target, target_hp, event, shooter))
	hit_step.set_delay(RocketVolley.last_impact_time())
	tween.tween_callback(volley.queue_free)
	if shooter.has_launcher():
		_tween_launcher(
			tween, shooter, Vector2(traverse, 1.0), Vector2(0.0, 1.0), LAUNCHER_TRAVERSE_DURATION
		)
		_tween_launcher(tween, shooter, Vector2(0.0, 1.0), Vector2.ZERO, LAUNCHER_RAISE_DURATION)
	return tween


## Appends a launcher step from pose `from` to `to` (x traverse, y elevation as a fraction of
## UnitModels.LAUNCHER_ELEVATION), eased in and out like a hydraulic drive.
func _tween_launcher(
	tween: Tween, shooter: UnitView, from: Vector2, to: Vector2, duration: float
) -> void:
	var step := tween.tween_method(
		func(f: float) -> void:
			if is_instance_valid(shooter):
				var pose := from.lerp(to, f)
				shooter.set_launcher_pose(pose.x, pose.y * UnitModels.LAUNCHER_ELEVATION),
		0.0,
		1.0,
		duration
	)
	step.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_volley_hit(
	target: UnitView, target_hp: int, event: Dictionary, shooter: UnitView
) -> void:
	if not is_instance_valid(target):
		return
	_add_impact_marks(event, target, shooter)
	var hit := target.play_hit(target_hp)
	if hit != null:
		hit.set_speed_scale(_burst_speed)


## Tile centres of `[from] + path` of a `unit_moved` event (`[from, to]` for events without
## a path).
func _move_points(event: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array([_map_view.tile_top_position(event["from"])])
	var path: Array = event.get("path", [event["to"]])
	for c: Vector2i in path:
		points.append(_map_view.tile_top_position(c))
	return points


func _on_unit_died(unit_id: int) -> Tween:
	if unit_id == _selected_unit_id:
		_select(-1)
	var view: UnitView = _unit_views.get(unit_id)
	if view == null:
		return null
	_marks.add_marks([GroundMarks.death_scorch(_event_serial, view.global_position)])
	# Forget the view right away: it frees itself at the end of the death tween.
	_unit_views.erase(unit_id)
	return view.play_death()


## Track or tyre marks along a move, drawn as the unit drives: every segment's mark exists from
## the start and is revealed along its length up to just behind the unit (GroundMarks.
## reveal_fractions), on the same time profile as UnitView.move_along. Everything is revealed
## when the tween ends. Infantry (and anything that is not a tank or rocket truck) leaves none.
func _play_track_marks(unit_id: int, points: PackedVector3Array, start_yaw: float) -> void:
	var unit := _sim.state.get_unit(unit_id)
	if unit == null or not _marks.is_active():
		return
	var segments := GroundMarks.track_segments(
		points, unit.definition.unit_class, VisualScale.unit_model_scale()
	)
	if segments.is_empty():
		return
	var decals := _marks.add_growing_tracks(segments)
	var move := HeavyMove.plan(points, start_yaw)
	var duration: float = move["duration"]
	var tween := create_tween()
	tween.set_speed_scale(_burst_speed)
	tween.tween_method(_reveal_tracks.bind(points, segments, decals, move), 0.0, duration, duration)
	tween.tween_callback(_reveal_tracks.bind(duration, points, segments, decals, move))


func _reveal_tracks(
	elapsed: float,
	points: PackedVector3Array,
	segments: Array[Dictionary],
	decals: Array[Decal],
	move: Dictionary
) -> void:
	var fractions := GroundMarks.reveal_fractions(
		points, HeavyMove.pose(move, elapsed)["path_time"]
	)
	for i in segments.size():
		_marks.set_reveal(decals[i], fractions[segments[i]["segment"]])


## Craters and a scorch patch at the target of indirect (rocket) fire, when the hit plays.
func _add_impact_marks(event: Dictionary, target: UnitView, shooter: UnitView) -> void:
	if not _marks.is_active() or shooter == null or not is_instance_valid(target):
		return
	var attacker := _sim.state.get_unit(event["attacker_id"])
	if attacker == null or not is_instance_valid(shooter):
		return
	var target_coord := Hex.from_world(target.global_position, _map_view.hex_size)
	var distance := Hex.distance(
		Hex.from_world(shooter.global_position, _map_view.hex_size), target_coord
	)
	var range_tiles := attacker.definition.attack_range
	var counter: bool = event.get("counter", false)
	var center := _map_view.tile_top_position(target_coord)
	var marks := GroundMarks.craters(_event_serial, center, range_tiles, distance, counter)
	marks.append_array(
		GroundMarks.impact_scorch(_event_serial, center, range_tiles, distance, counter)
	)
	_marks.add_marks(marks)


## Screenshot debug hook (tools/screenshot.gd): draws a scripted move and rocket strike
## around a unit without animation – tracks leading up to its tile, craters and a scorch patch
## three tiles to its right.
func debug_marks_demo(unit_id: int) -> void:
	var unit := _sim.state.get_unit(unit_id)
	if unit == null:
		push_error("debug_marks_demo: no unit %d" % unit_id)
		return
	var points := PackedVector3Array()
	for i in range(-2, 3):
		points.append(_map_view.tile_top_position(unit.coord + Vector2i(i - 1, 1)))
	var marks := GroundMarks.track_segments(
		points, unit.definition.unit_class, VisualScale.unit_model_scale()
	)
	if marks.is_empty():  # not a vehicle: show the tank marks anyway
		marks = GroundMarks.track_segments(points, &"tank", VisualScale.unit_model_scale())
	# The last segment is only 60 % revealed, as in the middle of a move.
	var growing := _marks.add_growing_tracks(marks)
	for i in growing.size():
		_marks.set_reveal(growing[i], 0.6 if i == growing.size() - 1 else 1.0)
	marks.clear()
	var strike := _map_view.tile_top_position(unit.coord + Vector2i(3, -1))
	marks.append_array(GroundMarks.craters(1, strike, 5, 3, false))
	marks.append_array(GroundMarks.impact_scorch(1, strike, 5, 3, false))
	marks.append(
		GroundMarks.death_scorch(2, _map_view.tile_top_position(unit.coord + Vector2i(2, -2)))
	)
	_marks.add_marks(marks, false)


## The view has caught up with the simulation: refresh everything derived from the state.
func _on_queue_drained() -> void:
	var selected := _sim.state.get_unit(_selected_unit_id)
	if selected != null and (not selected.is_alive() or not _unit_views.has(selected.id)):
		_select(-1)
	_refresh_hud()
	_hovered_unit_id = -1  # units may have moved under the cursor: re-pick the hovered unit
	_refresh_hovered_unit()
	_refresh_selection_ui()


func _on_command_rejected(command: Command, reason: String) -> void:
	print("Rejected %s: %s" % [command.get_script().get_global_name(), reason])


func _refresh_hud() -> void:
	_hud.refresh(_sim.state)
	_hud.set_end_enabled(_input_allowed())


func _on_end_turn_pressed() -> void:
	if _input_allowed():
		_end_human_turn()
