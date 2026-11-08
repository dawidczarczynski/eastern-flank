# gdlint: disable=max-public-methods
class_name StaffMap
extends Node3D
## The operational staff map scene (TASK-093a, 2.5D restyle TASK-125): the theatre as a dark
## digital map over a mildly extruded relief, seen by a tilted orthographic camera (no yaw, north
## up). Opens from the main menu ("Operation") or with `tools/run.sh --scene=staff_map`.
## Presentation only: it reads the ImportedMap / HexGrid and the OperationalState of its
## OperationalSimulation (TASK-092b) and reacts to its event_emitted (rule 3).
## Formations (TASK-092b): counters on their own CanvasLayer (StaffMapCounters), click selects
## (formation panel on the right), click on empty map or Esc deselects, Tab cycles own
## formations; `--side=nato|russia` picks the viewer (default NATO). Turns (TASK-093b): the turn bar
## (top centre) and Enter end the move (EndOperationalTurnCommand); with "follow" on the view
## switches to the side to play; `--pending-battle` adds a dummy pending battle (blocks End turn).
## Orders (TASK-092c / 092d): with an own formation selected the cursor hex shows the route
## (StaffMapRoutePreview) in the formation's posture, a left click on a hex gives the order
## (IssueOrderCommand), keys 1 / 2 / 3 or the picker under the counter set the posture
## (SetPostureCommand), Delete / Backspace / X cancel the order (CancelOrderCommand). The issued
## orders of the viewed side stay drawn (StaffMapOrders), rejections show in a toast.
## Camera: drag (left or middle button), WASD / arrows, screen edge pan; wheel zoom around the
## cursor; Ctrl + wheel or Q / E pitch, V flat <-> tilted; clamped to the map. G toggles the
## grid, B the country borders and names,
## Esc (nothing selected) / Back returns to the menu. Maths in StaffMapCameraMath, picking in
## StaffMapRelief.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const DEFAULT_MAP := &"suwalki_theatre"
const CARD_OFFSET := Vector2(18, 18)
## How fast the pitch follows its target (1 / s, exponential).
const PITCH_SMOOTHING := 14.0
const DEFAULT_OPERATION := &"suwalki_gap"
## Campaign seed until the session carries one (TASK-094); nothing draws from the RNG yet.
const DEFAULT_SEED := 1
## A left press released within this many pixels of travel is a click, not a drag.
const CLICK_SLOP := 5.0
const PANEL_MARGIN := Vector2(16, 16)
## Gap between the selected counter and the posture picker under it.
const PICKER_GAP := 12.0
## Viewport size assumed outside the scene tree (headless tests).
const FALLBACK_VIEWPORT := Vector2(1280, 720)

## Which map to open (the Operation button uses the default).
var map_id: StringName = DEFAULT_MAP
## The operation shown (its map replaces map_id when it loads).
var operation_id: StringName = DEFAULT_OPERATION
var seed_value := DEFAULT_SEED
## The player the human views the map as (0 = first side of the operation); -1 = from the
## command line (`--side=`), see StaffMapFormations.viewer_from_args.
var viewer_player := -1
## False: _ready only sets up the scene and the caller runs build_now() (headless tests).
var auto_build := true
## True once the map is built (the loading notice shows for a frame first).
var is_built := false
## Milliseconds the build took (reported by the screenshot / measure tools).
var build_ms := 0

var _grid: HexGrid
var _imported: ImportedMap
var _palette: StaffMapPalette
var _view: StaffMapView
var _camera: Camera3D
var _card: StaffMapCard
var _hint: Label
var _back: Button
var _hud: CanvasLayer
var _simulation: OperationalSimulation
var _counter_layer: CanvasLayer
var _counters: StaffMapCounters
var _panel: StaffMapFormationPanel
var _turn_bar: StaffMapTurnBar
var _route: StaffMapRoutePreview
var _route_marks: StaffMapRouteMarks
var _orders: StaffMapOrders
var _picker: StaffMapPosturePicker
var _toast: Toast
var _banner: TurnBanner
var _politics: StaffMapPoliticsHud
## True: the view switches to the side to play after each End turn (hot-seat).
var _follow_side := true
var _anchors := {}  # formation id -> Vector3 hex centre on the relief (hex units)
var _press_position := Vector2.ZERO
var _drag_travel := 0.0
var _dragging := false
var _min_zoom := 0.1
var _max_zoom := 1.0
var _bounds := Rect2()
var _km_per_unit := 1.0
## Camera state: ground point at the screen centre (world pixels) and zoom (screen px per world
## px), as in v0; pitch in degrees.
var _position := Vector2.ZERO
var _zoom := 1.0
var _pitch := StaffMapCameraMath.PITCH_DEFAULT
var _pitch_target := StaffMapCameraMath.PITCH_DEFAULT
var _tilt := StaffMapCameraMath.PITCH_DEFAULT  # the last tilt, for V
var _last_mouse := Vector2(-1, -1)


func _ready() -> void:
	Engine.max_fps = FramePacing.max_fps(true)
	GameSettings.apply_saved()
	_setup()
	if not auto_build:
		return
	var definition := OperationDefinition.find(operation_id)
	if definition != null:
		map_id = definition.map_id
	var imported := ImportedMap.find(map_id)
	var loading := LoadingScreen.new()
	loading.set_operation(imported.display_name if imported != null else "")
	loading.set_status("BUILDING THE STAFF MAP")
	_hud.add_child(loading)
	# The notice must be presented before the heavy build blocks the loop.
	await get_tree().process_frame
	await get_tree().process_frame
	var built := build_now()
	loading.queue_free()
	if not built:
		_return_to_menu()


## Builds map, operation, camera and HUD at once (_ready calls it after the loading notice);
## false when the map is missing. Works outside the scene tree too (headless tests: the
## viewport is then FALLBACK_VIEWPORT).
func build_now() -> bool:
	_setup()
	var start := Time.get_ticks_msec()
	var definition := OperationDefinition.find(operation_id)
	if definition != null:
		map_id = definition.map_id
	var imported := ImportedMap.find(map_id)
	if imported == null:
		push_error("StaffMap: no map '%s'" % map_id)
		return false
	_imported = imported
	_grid = imported.to_grid()
	_km_per_unit = imported.hex_spacing_m / Hex.SQRT3 / 1000.0
	_view = StaffMapView.new()
	add_child(_view)
	_view.build(_grid, _palette, imported.hex_spacing_m, imported)
	_view.build_countries(imported)
	_bounds = _view.world_bounds()
	_build_operation(definition)
	_build_camera()
	_build_hud()
	build_ms = Time.get_ticks_msec() - start
	print("Staff map built in %d ms" % build_ms)
	is_built = true
	refresh_texts()
	return true


func _notification(what: int) -> void:
	FramePacing.apply_notification(what)


func _process(delta: float) -> void:
	if not is_built:
		return
	_pitch_by_keys(delta)
	_follow_pitch(delta)
	_pan_by_keys_and_edge(delta)
	_update_hover()
	if _route != null:
		_route.tick(Time.get_ticks_msec())


func _unhandled_input(event: InputEvent) -> void:
	if not is_built:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_ESCAPE:
				if _politics.close_card():
					return
				if selected_formation() != &"":
					select_formation(&"")
				else:
					_return_to_menu()
			KEY_ENTER, KEY_KP_ENTER:
				end_turn()
			KEY_1, KEY_2, KEY_3, KEY_KP_1, KEY_KP_2, KEY_KP_3:
				var first := KEY_KP_1 if key.keycode >= KEY_KP_1 else KEY_1
				set_posture_number(key.keycode - first + 1)
			KEY_DELETE, KEY_BACKSPACE, KEY_X:
				cancel_order()
			KEY_G:
				_view.set_grid_visible(not _view.grid_visible())
			KEY_B:
				_view.countries().set_visible_layer(not _view.countries().is_visible_layer())
			KEY_P:
				_politics.toggle_tint()
			KEY_F9:
				_politics.toggle_panel()
			KEY_C:
				open_country_card(_card_hex_country())
			KEY_V:
				_pitch_target = StaffMapCameraMath.toggle_pitch(_pitch_target, _tilt)
		return
	var button := event as InputEventMouseButton
	if button != null:
		_on_mouse_button(button)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		if motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE) == 0:
			_dragging = false  # the release went to a button
			return
		_drag_travel += motion.relative.length()
		_move_camera(_position + StaffMapCameraMath.drag_delta(motion.relative, _zoom, _pitch))


## Tab is read here, before the GUI could take it for focus navigation.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not is_built or key == null or not key.pressed or key.keycode != KEY_TAB:
		return
	get_viewport().set_input_as_handled()
	if _counters != null:
		var next := StaffMapFormations.next_in_cycle(_counters.own_ids(), selected_formation())
		select_formation(next)
		_reveal(next)


## Sets every text in the current language.
func refresh_texts() -> void:
	if _back == null:
		return  # not built yet; _ready calls it again
	_back.text = "‹ " + tr("Back").to_upper()
	_hint.text = tr("STAFF_MAP_HINT")
	_view.countries().refresh_names()
	_refresh_turn_bar()
	if _panel != null and _panel.visible:
		select_formation(_panel.formation_id, true)


func _card_info(c: Vector2i) -> Dictionary:
	var data := StaffMapCard.info(_grid, c, _imported.country_at(c) if _imported != null else "")
	data["relation"] = CountryRules.relation(
		_simulation.state, viewer_player, _simulation.state.country_at(c)
	)
	return data


func view() -> StaffMapView:
	return _view


func camera() -> Camera3D:
	return _camera


func card() -> StaffMapCard:
	return _card


func simulation() -> OperationalSimulation:
	return _simulation


func counters() -> StaffMapCounters:
	return _counters


func formation_panel() -> StaffMapFormationPanel:
	return _panel


## The route preview (TASK-092c): read-only, creates no command.
func route_preview() -> StaffMapRoutePreview:
	return _route


## The issued orders layer (TASK-092d).
func orders() -> StaffMapOrders:
	return _orders


func posture_picker() -> StaffMapPosturePicker:
	return _picker


func toast() -> Toast:
	return _toast


## Sets the selected own formation's posture to number `number` (1-based, keys 1 / 2 / 3);
## false when nothing happened.
func set_posture_number(number: int) -> bool:
	return set_posture(StaffMapRoute.posture_for_key(number))


## SetPostureCommand for the selected own formation; false when there is nothing to change.
func set_posture(posture: StringName) -> bool:
	var formation := _selected_own()
	if formation == null or posture == &"" or formation.posture == posture:
		return false
	return _execute(SetPostureCommand.new(formation.id, posture))


## IssueOrderCommand: the selected own formation goes to `destination` in its picker posture.
func issue_order(destination: Vector2i) -> bool:
	var formation := _selected_own()
	if formation == null:
		return false
	return _execute(IssueOrderCommand.new(formation.id, destination, formation.posture))


## CancelOrderCommand for the selected own formation.
func cancel_order() -> bool:
	var formation := _selected_own()
	if formation == null:
		return false
	return _execute(CancelOrderCommand.new(formation.id))


func _selected_own() -> Formation:
	if _simulation == null:
		return null
	var formation := _simulation.state.get_formation(selected_formation())
	return formation if formation != null and formation.owner_id == viewer_player else null


## Executes `command`; a rejection shows its reason in the toast (command_rejected).
func _execute(command: OperationalCommand) -> bool:
	return _simulation.execute(command)


func _toast_message(message: String, colour: Color) -> void:
	_toast.show_message(message, colour)
	_toast.reset_size()
	_toast.position = Vector2(
		(_viewport_size().x - _toast.size.x) / 2.0, _viewport_size().y - 130.0
	)


func selected_formation() -> StringName:
	return _counters.selected() if _counters != null else &""


## Selects a formation (counter brackets + panel); &"" deselects. `refill` refreshes the panel
## even when the selection did not change (language switch, events).
func select_formation(formation_id: StringName, refill := false) -> void:
	if _counters == null:
		return
	var formation := _simulation.state.get_formation(formation_id)
	if formation == null:
		formation_id = &""
	if formation_id == _counters.selected() and not refill:
		return
	_counters.set_selected(formation_id)
	if formation == null:
		_panel.hide()
		_route.set_formation(_simulation.state, &"")
		_picker.hide()
		return
	_panel.show_formation(_simulation.state, formation, viewer_player, _palette)
	var own := formation.owner_id == viewer_player
	_route.set_formation(_simulation.state, formation_id if own else &"")
	_show_order_ui(formation)
	_place_panel()


## Posture / order rows of the panel and the picker under the counter: own formations only; the
## picker only while the viewed side is the side to play.
func _show_order_ui(formation: Formation) -> void:
	if formation.owner_id != viewer_player:
		_panel.hide_order()
		_picker.hide()
		return
	_panel.show_order(formation)
	if formation.owner_id == _simulation.state.current_player:
		_picker.show_posture(formation.posture)
		_place_picker()
	else:
		_picker.hide()


## Views the map as `player` (own / enemy swap); the panel follows.
func set_viewer(player: int) -> void:
	viewer_player = player
	if _counters == null:
		return
	_refresh_turn_bar()
	if _politics != null:
		_politics.refresh(player)
	_counters.set_viewer(player)
	_counters.refresh()
	_orders.refresh(_simulation.state, player)
	if _panel.visible:
		select_formation(_panel.formation_id, true)


func turn_bar() -> StaffMapTurnBar:
	return _turn_bar


func turn_banner() -> TurnBanner:
	return _banner


func follows_side() -> bool:
	return _follow_side


## Ends the move of the side to play; false when the command is rejected (a battle is pending).
func end_turn() -> bool:
	if _simulation == null:
		return false
	return _simulation.execute(EndOperationalTurnCommand.new())


## "Follow the side to play" on / off; switching it on views the side to play at once.
func set_follow_side(follow: bool) -> void:
	_follow_side = follow
	if follow and _simulation != null:
		set_viewer(_simulation.state.current_player)
	_refresh_turn_bar()


func pitch() -> float:
	return _pitch


func zoom() -> float:
	return _zoom


## Zoom limits for the current window and pitch (min: the whole theatre, max: ~10 hex rows).
func zoom_limits() -> Vector2:
	return Vector2(_min_zoom, _max_zoom)


## Screenshot / test aid: camera centre (hex units) and zoom (clamped); fades jump to the level.
func debug_focus(centre_hex_units: Vector2, zoom_value: float) -> void:
	_position = centre_hex_units * StaffMapView.UNIT
	_set_zoom(zoom_value)
	_view.set_zoom_level(_view.zoom_level(), true)


## Screenshot / test aid: sets the pitch at once (no smoothing).
func debug_pitch(degrees: float) -> void:
	_pitch = StaffMapCameraMath.clamp_pitch(degrees)
	_pitch_target = _pitch
	if _pitch > 0.5:
		_tilt = _pitch
	_on_pitch_changed()


## Screenshot / test aid: shows the hover card for a hex as if the cursor were over it.
func debug_hover(c: Vector2i) -> void:
	if not _view.has_tile(c):
		return
	_view.highlight(c)
	_card.show_info(_card_info(c))
	_place_card(_screen_of_hex(c))


## The map point (hex units, x / z) under a screen point.
func ground_at_screen(screen: Vector2) -> Vector2:
	var ray := StaffMapCameraMath.screen_ray(screen, _viewport_size(), _target(), _scale(), _pitch)
	return _view.relief().raycast(ray["origin"], ray["direction"])


## Opens the country card of `country_id` (the viewer's relation); no-op for &"".
func open_country_card(country_id: StringName) -> void:
	if country_id != &"":
		_politics.open_card(country_id)


## The country card (tests, screenshots).
func country_card() -> StaffMapCountryCard:
	return _politics.card()


func politics_hud() -> StaffMapPoliticsHud:
	return _politics


func _card_hex_country() -> StringName:
	var hovered := _view.hovered()
	return _simulation.state.country_at(hovered) if _view.has_tile(hovered) else &""


## The hex under a screen point (picking against the relief); check has_tile.
func hex_at_screen(screen: Vector2) -> Vector2i:
	var ray := StaffMapCameraMath.screen_ray(screen, _viewport_size(), _target(), _scale(), _pitch)
	return StaffMapLayers.hex_at(_view.relief().raycast(ray["origin"], ray["direction"]))


## Screen position of a formation counter (its hex centre on the relief).
func counter_screen_position(formation_id: StringName) -> Vector2:
	return _project(_anchors[formation_id])


## Screen position of a hex centre on the relief.
func _screen_of_hex(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c, 1.0)
	return _project(_view.relief().surface_point(Vector2(w.x, w.z)))


func _project(point: Vector3) -> Vector2:
	return StaffMapCameraMath.project(point, _viewport_size(), _target(), _scale(), _pitch)


func _viewport_size() -> Vector2:
	if not is_inside_tree():
		return FALLBACK_VIEWPORT
	return get_viewport().get_visible_rect().size


func _target() -> Vector3:
	return Vector3(_position.x, 0.0, _position.y) / StaffMapView.UNIT


## Screen pixels per hex unit.
func _scale() -> float:
	return _zoom * StaffMapView.UNIT


func _ground_viewport() -> Vector2:
	return StaffMapCameraMath.ground_viewport(_viewport_size(), _pitch)


## Palette, environment and the two canvas layers (once).
func _setup() -> void:
	if _hud != null:
		return
	_palette = load(StaffMapPalette.PATH) as StaffMapPalette
	_build_environment()
	_counter_layer = CanvasLayer.new()
	_counter_layer.name = "CounterLayer"
	_counter_layer.layer = 1
	add_child(_counter_layer)
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	_hud.layer = 2
	add_child(_hud)


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = _palette.map_void
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var world := WorldEnvironment.new()
	world.name = "Environment"
	world.environment = environment
	add_child(world)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 1.0
	_camera.far = StaffMapCameraMath.CAMERA_DISTANCE * 2.0
	add_child(_camera)
	if is_inside_tree():
		_camera.make_current()
	_position = _bounds.get_center()
	_update_limits()
	_set_zoom(_min_zoom)
	_view.set_zoom_level(_view.zoom_level(), true)
	if is_inside_tree():
		get_viewport().size_changed.connect(_on_viewport_resized)


## The operational state, its simulation and the counters (TASK-092b).
func _build_operation(definition: OperationDefinition) -> void:
	var state: OperationalState = null
	if definition != null:
		state = Operation.from_definition(
			definition,
			seed_value,
			_grid,
			Operation.map_countries(_imported) if _imported != null else {}
		)
	if state == null:
		push_error("StaffMap: cannot build operation '%s'" % operation_id)
		state = OperationalState.new()
		state.grid = _grid
	_simulation = OperationalSimulation.new(state)
	_simulation.event_emitted.connect(_on_operational_event)
	_simulation.command_rejected.connect(_on_command_rejected)
	if viewer_player < 0:
		viewer_player = StaffMapFormations.viewer_from_args(
			OS.get_cmdline_user_args(), state.player_sides
		)
	_counters = StaffMapCounters.new()
	_counter_layer.add_child(_counters)
	_build_route_preview()  # after the counters: its cross and label draw over them
	_counters.build(state, _palette, viewer_player)
	_counters.refresh()  # the order marks, also when the state already holds orders
	_orders.refresh(state, viewer_player)
	_update_anchors()
	if OS.get_cmdline_user_args().has("--pending-battle"):
		state.pending_battles.append(BattleSetup.new())


func _build_route_preview() -> void:
	var order_ribbon := StaffMapRouteRibbon.new("OrderRibbon")
	_view.add_child(order_ribbon)
	var order_marks := StaffMapRouteMarks.new()
	order_marks.name = "OrderMarks"
	order_marks.set_projector(_project)
	_counter_layer.add_child(order_marks)
	_orders = StaffMapOrders.new(order_ribbon, order_marks, _view.relief(), _palette)
	var ribbon := StaffMapRouteRibbon.new()
	_view.add_child(ribbon)
	_route_marks = StaffMapRouteMarks.new()
	_route_marks.set_projector(_project)
	_counter_layer.add_child(_route_marks)
	_route = StaffMapRoutePreview.new(ribbon, _route_marks, _view.relief(), _palette)


func _update_anchors() -> void:
	_anchors.clear()
	for formation in _simulation.state.formations:
		var w := Hex.to_world(formation.coord, 1.0)
		_anchors[formation.id] = _view.relief().surface_point(Vector2(w.x, w.z))


## Screen-space counters follow the camera; called only when it moved (no per-frame cost).
func _layout_counters() -> void:
	if _route_marks != null:
		_route_marks.refresh()
		_orders.refresh_projection()
		_place_picker()
	if _counters == null:
		return
	var points := {}
	for id: StringName in _anchors:
		points[id] = _project(_anchors[id])
	_counters.layout(points)


func _on_command_rejected(_command: OperationalCommand, reason: String) -> void:
	_toast_message(tr("ORDER_REJECTED_" + reason.to_upper()), _palette.ui_alert)


func _on_operational_event(event: Dictionary) -> void:
	if event.get("type") == &"operational_turn_started":
		_on_turn_started(event)
	if event.get("type") == &"country_stance_changed":
		_politics.refresh(viewer_player)
	_update_anchors()
	_counters.refresh()
	_orders.refresh(_simulation.state, viewer_player)
	_route.invalidate()
	_layout_counters()
	_refresh_turn_bar()
	if _panel.visible:
		select_formation(_panel.formation_id, true)


## The move changed hands: the view follows (if wanted) and the banner names the bloc.
func _on_turn_started(event: Dictionary) -> void:
	var player: int = event["player"]
	if _follow_side and player != viewer_player:
		set_viewer(player)
	var state := _simulation.state
	var colour := StaffMapFormations.side_colour(_palette, player)
	_banner.show_timed(
		"%s %02d" % [tr("TURN"), state.turn],
		(tr("%s to move") % StaffMapTurnBar.side_name(state, player)).to_upper(),
		colour
	)


func _refresh_turn_bar() -> void:
	if _turn_bar != null and _simulation != null:
		_turn_bar.show_state(_simulation.state, _palette, viewer_player, _follow_side)
		_place_turn_bar()
		_place_panel()


func _place_turn_bar() -> void:
	_turn_bar.position = Vector2((_viewport_size().x - _turn_bar.size.x) / 2.0, 0.0)


func _place_panel() -> void:
	if _panel == null:
		return
	_panel.reset_size()
	# Below the turn bar (the bar is as wide as the middle of the screen).
	var top := PANEL_MARGIN.y
	if _turn_bar != null:
		top = _turn_bar.size.y + PANEL_MARGIN.y / 2.0
	_panel.position = Vector2(_viewport_size().x - PANEL_MARGIN.x - _panel.size.x, top)


## Centres the camera on a formation whose counter is off screen (Tab).
func _reveal(formation_id: StringName) -> void:
	if not _anchors.has(formation_id):
		return
	var screen := counter_screen_position(formation_id)
	if Rect2(Vector2.ZERO, _viewport_size()).grow(-60.0).has_point(screen):
		return
	var point: Vector3 = _anchors[formation_id]
	_move_camera(Vector2(point.x, point.z) * StaffMapView.UNIT)


func _build_hud() -> void:
	_card = StaffMapCard.new()
	_hud.add_child(_card)
	_panel = StaffMapFormationPanel.new()
	_hud.add_child(_panel)
	_turn_bar = StaffMapTurnBar.new()
	_turn_bar.end_turn_pressed.connect(end_turn)
	_turn_bar.follow_toggled.connect(set_follow_side)
	_hud.add_child(_turn_bar)
	_banner = TurnBanner.new()
	_hud.add_child(_banner)
	_picker = StaffMapPosturePicker.new()
	_picker.posture_chosen.connect(set_posture)
	_counter_layer.add_child(_picker)
	_toast = Toast.new()
	_hud.add_child(_toast)
	_back = MenuStyle.button("")
	_back.position = Vector2(16, 16)
	_back.pressed.connect(_return_to_menu)
	_back.focus_mode = Control.FOCUS_NONE
	_hud.add_child(_back)
	_hint = MenuStyle.label("", HudTheme.mono(500, 1), 11, UiPalette.HUD_DESC)
	var plate := MenuStyle.box(UiPalette.PANEL, UiPalette.LINE)
	plate.set_content_margin_all(7)
	_hint.add_theme_stylebox_override(&"normal", plate)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(16, -40)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hint)
	_politics = StaffMapPoliticsHud.new(
		_view,
		_imported,
		_palette,
		_simulation,
		_hud,
		_toast_message,
		OS.get_cmdline_user_args().has("--debug")
	)
	_politics.refresh(viewer_player)


func _update_limits() -> void:
	_min_zoom = StaffMapCameraMath.min_zoom(_bounds, _ground_viewport())
	_max_zoom = StaffMapCameraMath.max_zoom(_viewport_size(), StaffMapView.UNIT, _min_zoom)


func _on_viewport_resized() -> void:
	_update_limits()
	_set_zoom(_zoom)
	_place_panel()
	if _turn_bar != null:
		_place_turn_bar()


func _set_zoom(zoom_value: float) -> void:
	_zoom = clampf(zoom_value, _min_zoom, _max_zoom)
	_move_camera(_position)


func _move_camera(position: Vector2) -> void:
	_position = StaffMapCameraMath.clamp_position(position, _zoom, _bounds, _ground_viewport())
	_apply_camera()


## Pushes the 2D state to the Camera3D and the view (zoom level, hatch scale).
func _apply_camera() -> void:
	_camera.transform = StaffMapCameraMath.camera_transform(_target(), _pitch)
	_camera.size = _viewport_size().y / _scale()
	_view.set_view_scale(_scale(), _pitch)
	_layout_counters()
	var px_per_km := _scale() / _km_per_unit
	_view.set_zoom_level(
		StaffMapCameraMath.zoom_level(
			px_per_km,
			maxi(_view.zoom_level(), 0),
			_palette.zoom_level_px_per_km,
			_palette.zoom_hysteresis
		)
	)


func _on_pitch_changed() -> void:
	_update_limits()
	_set_zoom(_zoom)


func _pitch_by_keys(delta: float) -> void:
	var direction := (
		float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	)
	if direction != 0.0:
		_set_pitch_target(_pitch_target + direction * StaffMapCameraMath.PITCH_KEY_SPEED * delta)
		_pitch = _pitch_target  # held keys drive the pitch directly (already smooth)
		_on_pitch_changed()


func _set_pitch_target(degrees: float) -> void:
	_pitch_target = StaffMapCameraMath.clamp_pitch(degrees)
	if _pitch_target > 0.5:
		_tilt = _pitch_target


func _follow_pitch(delta: float) -> void:
	if is_equal_approx(_pitch, _pitch_target):
		return
	var t := 1.0 - exp(-PITCH_SMOOTHING * delta)
	_pitch = lerpf(_pitch, _pitch_target, t)
	if absf(_pitch - _pitch_target) < 0.05:
		_pitch = _pitch_target
	_on_pitch_changed()


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			if event.button_index != MOUSE_BUTTON_LEFT:
				return
			if event.pressed:
				_press_position = event.position
				_drag_travel = 0.0
			elif (
				_drag_travel < CLICK_SLOP
				and event.position.distance_to(_press_position) < CLICK_SLOP
			):
				click_at(event.position)
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not event.pressed:
				return
			var notches := event.factor if event.factor > 0.0 else 1.0
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				notches = -notches
			if event.ctrl_pressed:
				_set_pitch_target(_pitch_target + notches * StaffMapCameraMath.PITCH_WHEEL_STEP)
			else:
				_zoom_at(notches, event.position)


func _zoom_at(notches: float, cursor: Vector2) -> void:
	var new_zoom := StaffMapCameraMath.zoom_by(_zoom, notches, _min_zoom, _max_zoom)
	var size := _viewport_size()
	var moved := StaffMapCameraMath.zoom_about(
		_position,
		_zoom,
		new_zoom,
		StaffMapCameraMath.ground_cursor(cursor, size, _pitch),
		_ground_viewport()
	)
	_zoom = new_zoom
	_move_camera(moved)


func _pan_by_keys_and_edge(delta: float) -> void:
	var direction := Vector2(
		(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		),
		(
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		)
	)
	if direction == Vector2.ZERO and not _dragging:
		direction = _edge_direction()
	if direction != Vector2.ZERO:
		var step := direction.normalized() * StaffMapCameraMath.KEY_PAN_SPEED * delta
		_move_camera(_position - StaffMapCameraMath.drag_delta(step, _zoom, _pitch))


## Pan direction from the cursor touching the window edge (focused window only).
func _edge_direction() -> Vector2:
	if not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var size := _viewport_size()
	var mouse := get_viewport().get_mouse_position()
	if mouse.x < 0.0 or mouse.y < 0.0 or mouse.x > size.x or mouse.y > size.y:
		return Vector2.ZERO
	var margin := StaffMapCameraMath.EDGE_MARGIN
	return Vector2(
		float(mouse.x >= size.x - margin) - float(mouse.x <= margin),
		float(mouse.y >= size.y - margin) - float(mouse.y <= margin)
	)


## A left click on the map: selects the counter under `screen`; with an own formation selected a
## click on a hex gives it an order there; elsewhere it deselects.
func click_at(screen: Vector2) -> void:
	if _counters == null:
		return
	var hit := _counters.counter_at(screen)
	if hit == &"":
		var named := _politics.country_name_at(ground_at_screen(screen))
		if named != &"":
			_politics.open_card(named)
			return
		_politics.close_card()
	if hit == &"" and _selected_own() != null:
		var hex := hex_at_screen(screen)
		if _view.has_tile(hex):
			issue_order(hex)
			return
	select_formation(hit)


func _update_hover() -> void:
	if _dragging or not DisplayServer.window_is_focused():
		return
	var mouse := get_viewport().get_mouse_position()
	if not get_viewport().get_visible_rect().has_point(mouse):
		_clear_hover()
		return
	if _panel != null and _panel.visible and _panel.get_global_rect().has_point(mouse):
		_clear_hover()  # the panel covers the map
		return
	if _counters != null:
		_counters.set_hovered(_counters.counter_at(mouse))
	var c := hex_at_screen(mouse)
	if not _view.has_tile(c):
		_clear_hover()
		return
	_route.set_hex(c)
	if c != _view.hovered() or not _card.visible:
		_view.highlight(c)
		_card.show_info(_card_info(c))
	if mouse != _last_mouse:
		_place_card(mouse)
		_last_mouse = mouse


func _clear_hover() -> void:
	if _route != null:
		_route.set_hex(StaffMapRoutePreview.OFF)
	_view.highlight(StaffMapView.NO_HEX)
	if _counters != null:
		_counters.set_hovered(&"")
	_card.hide()


## Puts the card next to `screen`, kept inside the window.
func _place_picker() -> void:
	if _picker == null or not _picker.visible:
		return
	var id := selected_formation()
	if not _anchors.has(id):
		return
	var at := _project(_anchors[id])
	_picker.position = Vector2(
		at.x - _picker.size.x / 2.0, at.y + StaffMapCounter.OWN_SIZE.y / 2.0 + PICKER_GAP
	)


func _place_card(screen: Vector2) -> void:
	var size := _viewport_size()
	var at := screen + CARD_OFFSET
	if at.x + _card.size.x > size.x:
		at.x = screen.x - CARD_OFFSET.x - _card.size.x
	if at.y + _card.size.y > size.y:
		at.y = screen.y - CARD_OFFSET.y - _card.size.y
	_card.position = at


func _return_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
