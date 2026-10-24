extends Node3D
## Battle scene: connects the simulation (GameSimulation) with the 3D view and player input.
## Rule: this script only translates input into commands and events into animations – no game rules.

const HUMAN_PLAYER := 0
const MAP_SEED := 12345
const BOTTOM_LEFT_MARGIN := 24
## Time the vehicle takes to turn towards its target before a volley (seconds at speed 1): a
## fixed launcher always turns; a turntable launcher with a limited traverse (Uragan) turns first
## when the target is outside its range (by zero when it isn't, same duration).
const AIM_DURATION := 0.5
## Launcher and deploy step durations (seconds at speed 1, each way), shared with the unit catalog.
const LAUNCHER_RAISE_DURATION := VolleyPlayback.LAUNCHER_RAISE_DURATION
const LAUNCHER_TRAVERSE_DURATION := VolleyPlayback.LAUNCHER_TRAVERSE_DURATION
const DEPLOY_DURATION := VolleyPlayback.DEPLOY_DURATION
const TURRET_AIM_DURATION := VolleyPlayback.TURRET_AIM_DURATION

## Command.validate() reasons the player can hit with a click, and the toast (translation key)
## that explains them. Other reasons (game_over, not_your_unit, ...) are not reachable by the UI.
const PREBUILD_GRASS_CHUNKS_PER_FRAME := 4
const WARM_UP_FRAME_S := 1.0 / 40.0  ## a frame faster than this counts as calm
const WARM_UP_CALM_FRAMES := 8
const WARM_UP_MAX_MS := 4000
const REJECT_TOASTS := {
	"unreachable": "CANNOT REACH THAT TILE",
	"out_of_range": "TARGET OUT OF RANGE",
	"already_attacked": "ALREADY ATTACKED THIS TURN",
	"not_an_enemy": "NOT AN ENEMY",
}

## Active graphics quality switches (GraphicsQuality.features); views read them before use.
var quality: Dictionary = {}
## True once _ready has built the whole scene (it waits one frame so the loading screen shows).
var is_built := false
var _sim: GameSimulation
var _ai := AiPlayer.new()
var _unit_views: Dictionary = {}  # unit id -> UnitView
var _selected_unit_id := -1
var _hovered_unit_id := -1
var _hud_root: Control
var _unit_popup: UnitPopup
var _portraits: PortraitRenderer
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
var _event_speed := 1.0  # speed of the event playing now (EventQueue.playback_speed)

var _wrecks := WreckField.new()  # burnt-out hulks of destroyed vehicles (TASK-065)
var _marks := GroundMarksView.new()  # ground decals (TASK-058), fed while animations play
var _event_serial := 0  # played events so far: the view-local seed of the marks

@onready var _map_view: MapView = $MapView
@onready var _units_root: Node3D = $Units
@onready var _camera_rig: CameraRig = $CameraRig


func _ready() -> void:
	Engine.max_fps = FramePacing.max_fps(true)
	_setup_graphics_quality()
	var state := Scenario.default_battle(MAP_SEED)
	# The loading screen must actually be presented before the heavy build below blocks the loop:
	# process_frame fires before the first draw, so wait for a frame to finish drawing.
	var loading := LoadingScreen.new()
	loading.set_operation(state.operation_name)
	loading.set_status("BUILDING THE BATTLEFIELD")
	$HUD.add_child(loading)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_sim = GameSimulation.new(state)
	_sim.event_emitted.connect(_on_event)
	_sim.command_rejected.connect(_on_command_rejected)

	_build_hud_root()
	_build_bottom_left_stack()
	await _next_frame()
	_map_view.build(state.grid)
	await _next_frame()
	_marks.name = "GroundMarks"
	_marks.setup(quality.get("decals_max", 0))
	add_child(_marks)
	_wrecks.name = "Wrecks"
	_wrecks.quality = quality
	_units_root.add_child(_wrecks)
	_camera_rig.set_bounds(_map_bounds())
	_camera_rig.set_ground_query(_map_view.visible_ground_height)
	var center := _map_view.center()
	_camera_rig.set_target(Vector2(center.x, center.z))
	_camera_rig.clicked.connect(_on_camera_clicked)
	for unit: Unit in state.units.values():
		_create_unit_view(unit)
	await _next_frame()
	_prerender_portraits(state)
	await _next_frame()
	await _prebuild_grass()
	await _warm_up()
	_refresh_hud()
	_refresh_selection_ui()
	loading.finish()
	is_built = true


## The build is split into stages with a drawn frame between them, so the loading screen's
## hatch keeps moving (a single blocking build would freeze it).
func _next_frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


## Builds the grass around the start camera behind the loading screen, a few chunks per frame,
## so the first seconds of the battle are not spent building it at 4-5 FPS.
func _prebuild_grass() -> void:
	_map_view.set_camera_target(_camera_rig.target())
	var grass := _map_view.grass()
	while not grass.is_settled():
		grass.update(PREBUILD_GRASS_CHUNKS_PER_FRAME)
		await _next_frame()


## The first frames of the finished scene are slow (shader pipelines, texture uploads). They are
## rendered under the loading screen: wait until the frame time settles, or give up after a while.
func _warm_up() -> void:
	var calm := 0
	var deadline := Time.get_ticks_msec() + WARM_UP_MAX_MS
	while calm < WARM_UP_CALM_FRAMES and Time.get_ticks_msec() < deadline:
		await _next_frame()
		calm = calm + 1 if get_process_delta_time() < WARM_UP_FRAME_S else 0


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
	if not is_built:
		return
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
		if is_built:
			_on_mouse_motion(motion.position)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not is_built:
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


## Screenshot debug hook (tools/screenshot.gd): hovers the unit's own tile (hover card).
func debug_hover_unit(unit_id: int) -> void:
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * 0.4)
	var unit := _sim.state.get_unit(unit_id)
	if unit != null:
		_set_hovered_hex(unit.coord)
	_update_unit_popup()


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


## Debug aid (tools/screenshot.gd, SCREENSHOT_NOTICE): shows one HUD notice so it can be
## photographed: "toast", "targeting", "banner" or "loading".
func debug_notice(kind: String) -> void:
	match kind:
		"toast":
			_hud.show_toast(REJECT_TOASTS["out_of_range"])
		"targeting":
			_hud.show_targeting("BLIND FIRE", "TANK #2", "Select a hex in range")
		"banner":
			_hud.on_turn_started(_sim.state, _sim.state.turn + 1, 1)
		"loading":
			var loading := LoadingScreen.new()
			loading.set_operation(_sim.state.operation_name)
			loading.set_status("BUILDING THE BATTLEFIELD")
			loading.add_child(ScreenDecor.new())  # vignette: the blank-image check needs variation
			$HUD.add_child(loading)
		_:
			push_error("debug_notice: unknown kind '%s'" % kind)


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
		TerrainPanelModel.build(_sim.state.grid, _hovered_hex, cost, moves_left),
		UiPalette.faction_color(_sim.state, unit.owner_id) if unit != null else UiPalette.AMBER
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
	_hud_root.add_child(ScreenDecor.new())  # above the 3D view, below every HUD panel
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
	stack.add_theme_constant_override(&"separation", 10)
	var operation := OperationLabel.new()
	operation.set_operation(_sim.state.operation_name)
	stack.add_child(operation)
	_terrain_panel = TerrainPanel.new()
	stack.add_child(_terrain_panel)
	_unit_popup = UnitPopup.new()
	_hud_root.add_child(_unit_popup)
	_portraits = PortraitRenderer.new()
	add_child(_portraits)
	_portraits.setup(quality)


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
	if unit == null or not unit.is_alive() or _unit_popup.suppressed:
		_popup_unit_id = -1
		_unit_popup.hide()
		return
	if unit.id != _popup_unit_id or not _unit_popup.visible:
		_popup_unit_id = unit.id
		_unit_popup.show_model(UnitPopupModel.build(state, unit, HUMAN_PLAYER))
	_unit_popup.set_portrait(_portrait_of(state, unit))  # may finish rendering while shown
	_unit_popup.position = UnitPopupModel.placement(
		get_viewport().get_mouse_position(),
		get_viewport().get_visible_rect().size,
		_unit_popup.card_size()
	)


## The unit's portrait once rendered, else null.
func _portrait_of(state: GameState, unit: Unit) -> Texture2D:
	var id := unit.definition.id
	var texture := _portraits.portrait(id, unit.owner_id, state.faction_of(unit.owner_id))
	return texture if _portraits.is_ready(id, unit.owner_id) else null


## Queues the portraits of every (unit definition, owner) pair of the scenario, so the first
## hover has no hitch.
func _prerender_portraits(state: GameState) -> void:
	for unit: Unit in state.units.values():
		_portraits.portrait(unit.definition.id, unit.owner_id, state.faction_of(unit.owner_id))


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


## Volleys and direct fire play longer than a plain hit: the queue learns the duration from the
## annotation (the simulation's event is copied, not modified).
func _annotate(event: Dictionary) -> Dictionary:
	if event["type"] == &"unit_attacked" and _fires_volley(event["attacker_id"]):
		var shooter: UnitView = _unit_views.get(event["attacker_id"])
		var launcher := shooter != null and shooter.has_launcher()
		var limited := launcher and shooter.launcher_limited()
		var deploy := shooter != null and shooter.has_deployables()
		var plan := _salvo_plan(event, shooter)
		var annotated := EventQueue.with_view_duration(
			event,
			_volley_event_duration(
				launcher, limited, deploy, plan["count"], plan["interval"], plan["flight"]
			)
		)
		annotated[EventQueue.VIEW_FX_KEY] = EventQueue.FX_ROCKET_VOLLEY
		return annotated
	if event["type"] == &"unit_attacked":
		var gunner: UnitView = _unit_views.get(event["attacker_id"])
		if gunner != null and gunner.has_turret():
			var direct := EventQueue.with_view_duration(
				event, _direct_fire_duration(gunner.turret_limited())
			)
			direct[EventQueue.VIEW_FX_KEY] = EventQueue.FX_DIRECT_FIRE
			return direct
	return event


func _fires_volley(attacker_id: int) -> bool:
	var attacker := _sim.state.get_unit(attacker_id)
	return attacker != null and UnitModels.fires_volley(attacker.definition)


## A volley event's salvo when it is emitted (VolleyPlayback.salvo_plan): the shooter's tubes, the
## distance between the tiles the attacker and the target stand on when the event plays.
func _salvo_plan(event: Dictionary, shooter: UnitView) -> Dictionary:
	var attacker := _sim.state.get_unit(event["attacker_id"])
	var to := Hex.to_world(_sim.state.get_unit(event["target_id"]).coord, _map_view.hex_size)
	var distance := VolleyPlayback.horizontal_distance(
		Hex.to_world(attacker.coord, _map_view.hex_size), to
	)
	var mouths := shooter.launch_points().size() if shooter != null else 0
	return VolleyPlayback.salvo_plan(attacker.definition.id, mouths, distance)


## Aim + salvo (SalvoTiming.salvo_duration) + stow. A turntable `launcher` raises and traverses
## before the salvo and stows after it; a `limited` one always has the body turn first (zero angle
## when not needed), so the duration doesn't depend on the view state when the event is annotated.
static func _volley_event_duration(
	launcher: bool, limited: bool, deploy: bool, count: int, interval: float, flight: float
) -> float:
	var salvo := SalvoTiming.salvo_duration(count, interval, flight)
	if launcher:
		var duration := 2.0 * (LAUNCHER_RAISE_DURATION + LAUNCHER_TRAVERSE_DURATION) + salvo
		if deploy:
			duration += 2.0 * DEPLOY_DURATION
		return duration + AIM_DURATION if limited else duration
	return AIM_DURATION + salvo


## Turret aim + hit + turret back; a limited traverse always has the body turn first (see
## _volley_event_duration for why the duration doesn't depend on the view state).
static func _direct_fire_duration(limited: bool) -> float:
	var duration := 2.0 * TURRET_AIM_DURATION + EventQueue.ATTACK_DURATION
	return duration + AIM_DURATION if limited else duration


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
		var event := _event_queue.pop()
		_event_speed = EventQueue.playback_speed(event, _burst_speed)
		var tween := _play_event(event)
		if tween != null:
			tween.set_speed_scale(_event_speed)
			tween.finished.connect(_play_next_event, CONNECT_ONE_SHOT)
			return
	_playing = false
	_burst_speed = 1.0
	_event_speed = 1.0
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
				var move := view.move_along(points, _map_view.surface().ground_height)
				if move != null:
					# A unit that ends its move on a wreck's tile hides the wreck.
					move.finished.connect(_wrecks.on_unit_moved.bind(event["to"]), CONNECT_ONE_SHOT)
				return move
		&"unit_attacked":
			var target: UnitView = _unit_views.get(event["target_id"])
			var shooter: UnitView = _unit_views.get(event["attacker_id"])
			if (
				target != null
				and shooter != null
				and event.get(EventQueue.VIEW_FX_KEY) == EventQueue.FX_ROCKET_VOLLEY
			):
				return _play_volley(shooter, target, event["target_hp"], event)
			if (
				target != null
				and shooter != null
				and event.get(EventQueue.VIEW_FX_KEY) == EventQueue.FX_DIRECT_FIRE
			):
				return _play_direct_fire(shooter, target, event["target_hp"], event)
			if target != null:
				_add_impact_marks(event, target, shooter)
				return target.play_hit(event["target_hp"])
		&"unit_died":
			return _on_unit_died(event["unit_id"])
		&"turn_ended":
			if event["player"] == HUMAN_PLAYER:
				_select(-1)
		&"turn_started":
			_wrecks.on_turn_started()
			_hud.on_turn_started(_sim.state, event["turn"], event["player"])
		&"game_over":
			_select(-1)
	return null


## Turn the launcher towards the target, fire the salvo from its tubes (the target's HP steps down
## as the rockets land), stow. One tween lasts the whole event (_volley_event_duration). A limited
## traverse turns the vehicle first (it stays turned afterwards).
func _play_volley(shooter: UnitView, target: UnitView, target_hp: int, event: Dictionary) -> Tween:
	var aim_point := target.global_position
	var tween := create_tween()
	var traverse := 0.0
	var elevation := 0.0
	if shooter.has_launcher():
		var aim := shooter.launcher_aim_towards(aim_point)
		traverse = aim.y
		elevation = shooter.launcher_elevation()
		if shooter.launcher_limited():
			VolleyPlayback.tween_body_turn(tween, shooter, aim.x, AIM_DURATION)
		VolleyPlayback.append_aim(tween, shooter, traverse, elevation)
	else:
		var turn := wrapf(shooter.yaw_towards(aim_point) - shooter.facing_yaw(), -PI, PI)
		VolleyPlayback.tween_body_turn(tween, shooter, turn, AIM_DURATION)
	var from := shooter.global_position
	var context := {
		"launcher_terrain": VolleyPlayback.terrain_name(_terrain_at(from.x, from.z)),
		"target_terrain": VolleyPlayback.terrain_name(_terrain_at(aim_point.x, aim_point.z)),
	}
	var radius := SalvoTiming.LANDING_RADIUS * _map_view.hex_size
	# View-local scatter, the same for a replayed event; never GameState.rng.
	var rng := VolleyPlayback.scatter_rng(_event_serial, event["attacker_id"])
	var ground := _map_view.mesh_height_at
	var volley := VolleyPlayback.append_salvo(
		tween, self, shooter, aim_point, rng, radius, context, ground
	)
	volley.effects = SalvoEffects.new()  # TASK-075 assigns its pooled effects on HIGH here
	VolleyPlayback.connect_hp_steps(
		volley, target, target_hp, _event_speed, _add_impact_marks.bind(event, target, shooter)
	)
	if shooter.has_launcher():
		VolleyPlayback.append_stow(tween, shooter, traverse, elevation)
	return tween


## A turreted vehicle fires: [limited: the hull turns], the turret traverses and the gun elevates
## to the target, the hit lands, turret and gun return to the front. One tween lasts the whole
## event (_direct_fire_duration).
func _play_direct_fire(
	shooter: UnitView, target: UnitView, target_hp: int, event: Dictionary
) -> Tween:
	var aim_point := target.global_position
	var aim := shooter.turret_aim_towards(aim_point)
	var elevation := shooter.gun_elevation_towards(aim_point + Vector3(0.0, 0.15, 0.0))
	var pose := Vector2(aim.y, elevation)
	var tween := create_tween()
	if shooter.turret_limited():
		VolleyPlayback.tween_body_turn(tween, shooter, aim.x, AIM_DURATION)
	VolleyPlayback.tween_turret(tween, shooter, Vector2.ZERO, pose, TURRET_AIM_DURATION)
	tween.tween_callback(_play_direct_hit.bind(target, target_hp, event, shooter))
	tween.tween_interval(EventQueue.ATTACK_DURATION)
	VolleyPlayback.tween_turret(tween, shooter, pose, Vector2.ZERO, TURRET_AIM_DURATION)
	return tween


func _play_direct_hit(
	target: UnitView, target_hp: int, event: Dictionary, shooter: UnitView
) -> void:
	if not is_instance_valid(target):
		return
	_add_impact_marks(event, target, shooter)
	var hit := target.play_hit(target_hp)
	if hit != null:
		hit.set_speed_scale(_event_speed)


## Tile centres of `[from] + path` of a `unit_moved` event (`[from, to]` for events without
## a path).
func _move_points(event: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array([_map_view.tile_top_position(event["from"])])
	var path: Array = event.get("path", [event["to"]])
	for c: Vector2i in path:
		points.append(_map_view.tile_top_position(c))
	return points


## The black burnt ground of a wreck: the decal, and no grass or flowers growing on it.
func _burn_ground(serial: int, position: Vector3, animate: bool) -> void:
	_marks.add_marks([GroundMarks.wreck_burnt(serial, position)], animate)
	var center := Vector2(position.x, position.z)
	_map_view.grass().add_clearing(center, GroundMarks.WRECK_BURNT_RADIUS)
	BurntGround.burn(_map_view, center, GroundMarks.WRECK_BURNT_RADIUS)


func _on_unit_died(unit_id: int) -> Tween:
	if unit_id == _selected_unit_id:
		_select(-1)
	var view: UnitView = _unit_views.get(unit_id)
	if view == null:
		return null
	# Forget the view right away: it frees itself at the end of the death tween.
	_unit_views.erase(unit_id)
	var unit := _sim.state.get_unit(unit_id)
	var is_wreck := unit != null and WreckPlan.leaves_wreck(unit.definition)
	if is_wreck:
		_burn_ground(_event_serial, view.global_position, true)
	else:
		_marks.add_marks([GroundMarks.death_scorch(_event_serial, view.global_position)])
	if is_wreck:
		# A vehicle burns black and stays on its tile as a wreck (a dead unit never moves again).
		return view.play_death(_wrecks.adopt.bind(unit.coord))
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


## Screenshot hook (SCREENSHOT_SALVO): plays a volley view-only (VolleyPlayback.show_attack, no
## command, no state change); its tween runs although the tool disables the scene's processing.
func debug_salvo(attacker_id: int, target_id: int) -> void:
	var target := _sim.state.get_unit(target_id)
	if target == null or not _fires_volley(attacker_id) or not _unit_views.has(target_id):
		push_error("debug_salvo: %d cannot fire a volley at %d" % [attacker_id, target_id])
		return
	var event := VolleyPlayback.show_attack(attacker_id, target_id, target.hp)
	var tween := _play_event(_annotate(event))
	if tween != null:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)


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


## Screenshot debug hook (tools/screenshot.gd, SCREENSHOT_WRECK): the unit's view dies at once
## through the real wreck path (burnt, turret askew, smoke), without touching the simulation.
func debug_wreck_demo(unit_id: int) -> void:
	var view: UnitView = _unit_views.get(unit_id)
	var unit := _sim.state.get_unit(unit_id)
	if view == null or unit == null:
		push_error("debug_wreck_demo: no unit %d" % unit_id)
		return
	_unit_views.erase(unit_id)
	view.begin_wreck_death()
	view.set_wreck_time(EventQueue.DEATH_DURATION)
	var wreck := _wrecks.adopt(view, unit.coord)
	wreck.process_mode = Node.PROCESS_MODE_ALWAYS  # the screenshot tool pauses the scene
	view.queue_free()
	_burn_ground(1, view.global_position, false)


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
	# Only the human's own rejected orders get a toast (the AI never reaches the UI).
	if REJECT_TOASTS.has(reason) and _sim.state.current_player == HUMAN_PLAYER:
		_hud.show_toast(REJECT_TOASTS[reason])


func _refresh_hud() -> void:
	_hud.refresh(_sim.state)
	_hud.set_end_enabled(_input_allowed())


func _on_end_turn_pressed() -> void:
	if _input_allowed():
		_end_human_turn()
