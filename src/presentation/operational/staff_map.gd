# gdlint: disable=max-public-methods,max-file-lines
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
## (top centre) and Enter end the move (EndOperationalTurnCommand); the view stays on one side;
## `--pending-battle` adds a dummy pending battle (blocks End turn).
## Orders (TASK-092c / 092d): with an own formation selected the cursor hex shows the route
## (StaffMapRoutePreview); a left click on a hex gives a MARCH order (IssueOrderCommand), on an
## enemy counter / hex an ATTACK order (advance posture). A right click on a hex opens the order
## ring (StaffMapOrderRing, the battle unit ring component): 1 MARCH, 2 ATTACK, 3 DEFEND,
## 4 CANCEL ORDER (keys 1-4 while it is open); Delete / Backspace / X cancel the order
## (CancelOrderCommand). The issued orders of the viewed side stay drawn (StaffMapOrders),
## rejections show in a toast.
## Camera: drag (left or middle button), WASD / arrows, screen edge pan; wheel zoom around the
## cursor; Ctrl + wheel or Q / E pitch, V flat <-> tilted; clamped to the map. G toggles the
## grid, B the country borders and names, N the place names (TASK-112),
## Esc (nothing selected) / Back returns to the menu.
## Contacts (TASK-094a / 094c): the notice's Play battle (B) hands the simulation and the view
## settings to Session and opens the battle scene; coming back (Session.take_simulation) the map
## is rebuilt around the same simulation, the view restored and the battle's short result shown
## (StaffMapBattleResult). Saving (TASK-094d): F5 or the Save button writes the campaign
## (Session.record -> CampaignSaver, `user://campaigns/<operation>.json`) with a "Saved" toast;
## Continue on the main menu hands a replayed operation over the same way as a battle return.
## Maths in StaffMapCameraMath, picking in StaffMapRelief.

## The windows that share the left edge of the screen: only one is open at a time, opening one
## closes the others (a strike report is only hidden – J brings it back).
enum LeftWindow { REPORT, COUNTRY_CARD, DEBUG, OPTIONS }
## (The ladder window is a full-screen overlay: opening it closes all of them, see
## `_close_other_windows`; opening any of them closes it.)

## Width of the hex strip slot in the bottom bar.
const CARD_SLOT_WIDTH := 470
const ACTION_GRID := &"grid"
const ACTION_NAMES := &"names"
const ACTION_BORDERS := &"borders"
const ACTION_POLITICS := &"politics"
const ACTION_FLAT := &"flat"
const ACTION_NEXT := &"next"
const ACTION_CANCEL := &"cancel"
const ACTION_REPORT := &"report"
const ACTION_SAVE := &"save"
const ACTION_DECISIONS := &"decisions"
const ACTION_STRIKE := &"strike"
const ACTION_MAP_OPTIONS := &"map_options"
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
## Opens a scene by path (default: Session.change_scene); tests replace it.
var open_scene: Callable
## Folder of the campaign saves (a test points it at a temp folder).
var save_dir := CampaignSaver.DIR

var _grid: HexGrid
var _imported: ImportedMap
var _palette: StaffMapPalette
var _view: StaffMapView
var _camera: Camera3D
var _card: StaffMapCard
var _back: Button
var _options: StaffMapOptionsWindow  # map layer toggles under the MAP button
var _bar: ActionBar
var _hud: CanvasLayer
var _simulation: OperationalSimulation
var _counter_layer: CanvasLayer
var _counters: StaffMapCounters
var _places: StaffMapPlaceLayer  # place-name labels (TASK-112), N toggles
var _installations: StaffMapInstallations
var _installation_card: StaffMapInstallationCard
var _installation_anchors := {}  # installation id -> point on the relief
var _panel: StaffMapFormationPanel
var _turn_bar: StaffMapTurnBar
var _route: StaffMapRoutePreview
var _route_marks: StaffMapRouteMarks
var _orders: StaffMapOrders
var _front: StaffMapFrontLine
var _order_ring: StaffMapOrderRing
var _toast: Toast
var _border_prompt: StaffMapBorderPrompt
var _join_notice: StaffMapJoinNotice
var _origins := {}  # formation id -> country id of origin (joined allies, TASK-118)
var _join_key := ""  # "<country>|<player>" of the group the notice shows
var _join_ids: Array = []
var _banner: TurnBanner
var _politics: StaffMapPoliticsHud
var _escalation: StaffMapEscalationHud
var _decisions: StaffMapDecisionsHud
var _strike: StaffMapStrikeHud  # strike mode, trail (TASK-097b)
var _decision_lines: Array[String] = []  # log of the decisions since the last report
var _contact_debug: StaffMapContactDebug  # F9 contact-map preview, --debug only (TASK-094b)
var _report: StaffMapTurnReport
var _contacts: StaffMapContacts
var _result_notice: StaffMapBattleResult
var _resumed := false  # the simulation came back from a played battle (Session)
var _marks := StaffMapTurnMarks.new()
var _slide := StaffMapSlide.new()  # the counters' slide after End turn
## True: the view switches to the side to play after each End turn (hot-seat).
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
	_take_session_operation()
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
	_take_session_operation()
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
	_places = StaffMapPlaceLayer.new()  # first child of the counter layer: under everything
	_counter_layer.add_child(_places)
	_places.build(imported, _view.relief())
	_bounds = _view.world_bounds()
	_build_operation(definition)
	_build_camera()
	_build_hud()
	if _resumed:
		_resume()
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
	var modal := _modal_open()  # the Politics screen / ladder window idle the map
	if not modal:
		_pitch_by_keys(delta)
	_follow_pitch(delta)
	if not modal:
		_pan_by_keys_and_edge(delta)
		_update_hover()
	_sync_action_bar()
	advance_slide(delta)
	if _strike != null:
		_strike.tick(delta)
	if _route != null:
		_route.tick(Time.get_ticks_msec())


func _unhandled_input(event: InputEvent) -> void:
	if not is_built:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		# The open Politics screen takes every key (the map below is dimmed and idle); Esc closes
		# the ring, 1-4 pick a slot; Enter / Esc close the result notice.
		if (
			(_decisions != null and _decisions.handle_key(key.keycode))
			or (_escalation != null and _escalation.handle_key(key.keycode))
			or (_strike != null and _strike.handle_key(key.keycode))
			or (_strike != null and _strike.handle_report_key(key.keycode))
			or _order_ring.handle_key(key.keycode)
			or _close_result_notice(key.keycode)
			or _answer_border_prompt(key.keycode)
		):
			return
		match key.keycode:
			KEY_ESCAPE:
				if (
					_close_options_key()
					or _politics.close_card()
					or _escalation.close_card()
					or _decisions.close()
				):
					return
				if selected_formation() != &"":
					select_formation(&"")
				else:
					_return_to_menu()
			KEY_ENTER, KEY_KP_ENTER:
				end_turn()
			KEY_SPACE:
				skip_slide()
			KEY_R:
				toggle_report()
			KEY_DELETE, KEY_BACKSPACE, KEY_X:
				cancel_order()
			KEY_G:
				toggle_grid()
			KEY_T:
				toggle_front_tint()
			KEY_B:
				if _contacts.is_active():
					_play_battle()
				else:
					toggle_borders()
			KEY_N:
				toggle_place_names()
			KEY_S:
				toggle_strike_mode()
			KEY_P:
				_politics.toggle_tint()
			StaffMapDecisionsPanel.OPEN_KEY:
				toggle_decisions()
			KEY_F9:
				toggle_debug_panels()
			KEY_F5:
				save_campaign()
			KEY_C:
				open_country_card(_card_hex_country())
			KEY_V:
				toggle_flat_view()
		return
	if _modal_open():
		_dragging = false  # the Politics screen idles the map: no wheel zoom, drag or click
	var button := event as InputEventMouseButton
	if button != null:
		if not _modal_open():
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
## The bottom menu of the staff map: the same effects as the keys on the buttons' caps.
func _build_action_bar() -> void:
	_bar = ActionBar.new()
	_bar.add_action(ACTION_MAP_OPTIONS, "MAP OPTIONS", "", true, "TIP_MAP_OPTIONS")
	_bar.add_separator()
	_bar.add_action(ACTION_NEXT, "NEXT", "TAB", false, "TIP_NEXT")
	_bar.add_action(ACTION_CANCEL, "CANCEL", "X", false, "TIP_CANCEL")
	_bar.add_action(ACTION_REPORT, "REPORT", "R", false, "TIP_REPORT")
	_bar.add_action(
		ACTION_DECISIONS,
		"DECISIONS",
		OS.get_keycode_string(StaffMapDecisionsPanel.OPEN_KEY),
		true,
		"TIP_DECISIONS"
	)
	_bar.add_action(ACTION_STRIKE, "STRIKE", "S", true, "TIP_STRIKE")
	_bar.add_separator()
	_bar.add_action(ACTION_SAVE, "SAVE", "F5", false, "TIP_SAVE_OPERATION")
	_bar.action_pressed.connect(_on_action_pressed)
	_hud.add_child(_bar)
	_build_options_window()
	# The hovered hex lives in the left zone (a fixed-width slot, so the bar does not jump).
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(CARD_SLOT_WIDTH, 50)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.remove_child(_card)
	slot.add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar.add_left(slot)
	if _turn_bar != null:
		_bar.add_right(_turn_bar.take_end_button())  # End turn: same place as in the battle


func action_bar() -> ActionBar:
	return _bar


## The map options window (grid, names, borders, politics, flat view) opened by the MAP button.
func _build_options_window() -> void:
	_options = StaffMapOptionsWindow.new()
	_options.add_option(ACTION_GRID, tr("GRID"), "G")
	_options.add_option(ACTION_NAMES, tr("PLACE NAMES"), "N")
	_options.add_option(ACTION_BORDERS, tr("BORDERS"), "B")
	_options.add_option(ACTION_POLITICS, tr("POLITICAL TINT"), "P")
	_options.add_option(ACTION_FLAT, tr("VIEW"), "V", tr("FLAT"), tr("TILTED"))
	_options.option_toggled.connect(_on_action_pressed)
	_options.close_requested.connect(close_options)
	_hud.add_child(_options)


func options_window() -> StaffMapOptionsWindow:
	return _options


func toggle_options() -> void:
	if _options.is_open():
		close_options()
		return
	_claim_left_dock(LeftWindow.OPTIONS)
	_options.open(_viewport_size().x)
	_sync_action_bar()


func _close_options_key() -> bool:
	if not _options.is_open():
		return false
	close_options()
	return true


## Closes the map options window (X, Esc, the bar button).
func close_options() -> void:
	_options.close()
	_sync_action_bar()


func _on_action_pressed(id: StringName) -> void:
	if not is_built:
		return
	match id:
		ACTION_MAP_OPTIONS:
			toggle_options()
		ACTION_STRIKE:
			toggle_strike_mode()
		ACTION_GRID:
			toggle_grid()
		ACTION_NAMES:
			toggle_place_names()
		ACTION_BORDERS:
			toggle_borders()
		ACTION_POLITICS:
			_politics.toggle_tint()
		ACTION_FLAT:
			toggle_flat_view()
		ACTION_NEXT:
			select_next_formation()
		ACTION_CANCEL:
			cancel_order()
		ACTION_REPORT:
			toggle_report()
		ACTION_DECISIONS:
			toggle_decisions()
		ACTION_SAVE:
			save_campaign()


## Lights the toggle buttons to match the layers (whatever changed them: a key or a button).
func _sync_action_bar() -> void:
	if _bar == null or _politics == null or _places == null:
		return
	_options.set_active(ACTION_GRID, _view.grid_visible())
	_options.set_active(ACTION_NAMES, _places.is_enabled())
	_options.set_active(ACTION_BORDERS, _view.countries().is_visible_layer())
	_options.set_active(ACTION_POLITICS, _politics.tint_enabled())
	_options.set_active(ACTION_FLAT, _pitch_target <= 0.5)
	_bar.set_active(ACTION_MAP_OPTIONS, _options.is_open())
	_bar.set_active(ACTION_STRIKE, _strike != null and _strike.is_open())
	_bar.set_active(ACTION_DECISIONS, _decisions.is_open())
	_bar.set_enabled(ACTION_CANCEL, _selected_own() != null)


func toggle_grid() -> void:
	_view.set_grid_visible(not _view.grid_visible())
	_apply_front_view()


func toggle_front_tint() -> void:
	_front.set_tint_visible(not _front.is_tint_visible())


func toggle_borders() -> void:
	_view.countries().set_visible_layer(not _view.countries().is_visible_layer())


func toggle_place_names() -> void:
	_places.set_enabled(not _places.is_enabled())
	_layout_places()


func toggle_flat_view() -> void:
	_pitch_target = StaffMapCameraMath.toggle_pitch(_pitch_target, _tilt)


## Selects the next own formation (Tab).
func select_next_formation() -> void:
	if _counters == null:
		return
	var next := StaffMapFormations.next_in_cycle(_counters.own_ids(), selected_formation())
	select_formation(next)
	_reveal(next)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not is_built or key == null or not key.pressed or key.keycode != KEY_TAB:
		return
	get_viewport().set_input_as_handled()
	select_next_formation()


## Sets every text in the current language.
func refresh_texts() -> void:
	if _back == null:
		return  # not built yet; _ready calls it again
	_back.text = "‹ " + tr("Back").to_upper()
	if _bar != null:
		_bar.refresh_texts()
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


func installations() -> StaffMapInstallations:
	return _installations


func installation_card() -> StaffMapInstallationCard:
	return _installation_card


func formation_panel() -> StaffMapFormationPanel:
	return _panel


## The route preview (TASK-092c): read-only, creates no command.
func route_preview() -> StaffMapRoutePreview:
	return _route


## The front line layer (TASK-093c).
func front_line() -> StaffMapFrontLine:
	return _front


## The issued orders layer (TASK-092d).
func orders() -> StaffMapOrders:
	return _orders


func order_ring() -> StaffMapOrderRing:
	return _order_ring


func toast() -> Toast:
	return _toast


## Sets the selected own formation's posture to number `number` (1-based: march, attack, defend;
## debug / screenshot hooks); false when nothing happened.
func set_posture_number(number: int) -> bool:
	return set_posture(StaffMapRoute.posture_for_key(number))


## SetPostureCommand for the selected own formation; false when there is nothing to change.
func set_posture(posture: StringName) -> bool:
	var formation := _selected_own()
	if formation == null or posture == &"" or formation.posture == posture:
		return false
	return _execute(SetPostureCommand.new(formation.id, posture))


## IssueOrderCommand: the selected own formation goes to `destination` in `posture`; &"" = the
## default of a left click (attack on an enemy-held hex, else march).
func issue_order(destination: Vector2i, posture := &"") -> bool:
	var formation := _selected_own()
	if formation == null:
		return false
	if posture == &"":
		posture = StaffMapOrderRingModel.default_posture(_simulation.state, formation, destination)
	return _execute(IssueOrderCommand.new(formation.id, destination, posture))


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


## Executes `command`; a rejection shows its reason in the toast (command_rejected). An order
## whose route causes border incidents (sanctuary breach, casus belli) first asks for Enter / Esc
## (TASK-116) and returns false until it is confirmed.
func _execute(command: OperationalCommand) -> bool:
	var order := command as IssueOrderCommand
	if order != null and _border_prompt != null:
		var warnings := StaffMapBorders.order_warnings(_simulation.state, order)
		if not warnings.is_empty():
			_border_prompt.ask(order.formation_id, order.destination, order.posture, warnings)
			return false
	return _simulation.execute(command)


## Enter issues the order waiting in the border prompt, Esc drops it; true when the key was used.
func _answer_border_prompt(keycode: Key) -> bool:
	if _border_prompt == null or not _border_prompt.is_open():
		return false
	if keycode not in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		return false
	var order := _border_prompt.take()
	if keycode != KEY_ESCAPE:
		var command := IssueOrderCommand.new(
			order["formation_id"], order["destination"], order["posture"]
		)
		if _simulation.execute(command):
			select_formation(&"")
	return true


func border_prompt() -> StaffMapBorderPrompt:
	return _border_prompt


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
	_order_ring.close()
	if _border_prompt != null and _border_prompt.pending().get("formation_id") != formation_id:
		_border_prompt.take()
	_counters.set_selected(formation_id)
	if formation == null:
		_panel.hide()
		_route.set_formation(_simulation.state, &"")
		return
	_panel.show_formation(_simulation.state, formation, viewer_player, _palette)
	var own := formation.owner_id == viewer_player
	_route.set_formation(_simulation.state, formation_id if own else &"")
	var origin := CountryDefinition.find(origin_country(formation_id))
	_panel.show_origin(origin.display_name if origin != null else "")
	_show_order_ui(formation)
	_place_panel()


## Posture / order rows of the panel: own formations only.
func _show_order_ui(formation: Formation) -> void:
	if formation.owner_id != viewer_player:
		_panel.hide_order()
		return
	_panel.show_order(formation)


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
	_counters.apply_marks(_marks)
	_refresh_orders()
	_show_new_report()
	_refresh_contacts()
	if _panel.visible:
		select_formation(_panel.formation_id, true)


func turn_bar() -> StaffMapTurnBar:
	return _turn_bar


func turn_banner() -> TurnBanner:
	return _banner


## Ends the move of the side to play; false when the command is rejected (a battle is pending).
func end_turn() -> bool:
	if _simulation == null or is_sliding():
		return false
	return _simulation.execute(EndOperationalTurnCommand.new())


## True while the counters slide along the moves of the last end turn (End turn is off then).
func is_sliding() -> bool:
	return _slide.is_playing()


## Advances the slide by `delta` seconds (the frame loop calls it; tests drive it by hand).
func advance_slide(delta: float) -> void:
	if not _slide.is_playing():
		return
	if _slide.advance(delta):
		_finish_slide()
		return
	_slide.override_anchors(_anchors, _view.relief())
	_layout_counters()


## Jumps the counters to their end hexes; the state is final already, so this only ends the show.
func skip_slide() -> bool:
	if not _slide.skip():
		return false
	_finish_slide()
	return true


## Moved / in-contact marks and the turn report (TASK-092e view-model).
func turn_marks() -> StaffMapTurnMarks:
	return _marks


func turn_report() -> StaffMapTurnReport:
	return _report


## R: closes the turn report or opens it with the viewed side's last report.
func toggle_report() -> void:
	if _report == null:
		return
	if _report.visible:
		_report.close()
		return
	_show_report()


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


## The map point (hex units, x / z) under a screen point.
func ground_at_screen(screen: Vector2) -> Vector2:
	var ray := StaffMapCameraMath.screen_ray(screen, _viewport_size(), _target(), _scale(), _pitch)
	return _view.relief().raycast(ray["origin"], ray["direction"])


## Opens the country card of `country_id` (the viewer's relation); no-op for &"".
func open_country_card(country_id: StringName) -> void:
	if country_id != &"":
		_claim_left_dock(LeftWindow.COUNTRY_CARD)
		_politics.open_card(country_id)


func _claim_left_dock(owner: LeftWindow) -> void:
	_escalation.close_card()
	if owner != LeftWindow.OPTIONS and _options != null and _options.close():
		_sync_action_bar()
	if owner == LeftWindow.OPTIONS and _report != null:
		_report.close()
	if owner != LeftWindow.REPORT and _strike != null:
		_strike.reports().suspend()
	if owner != LeftWindow.COUNTRY_CARD:
		_politics.close_card()
	if owner != LeftWindow.DEBUG:
		_close_debug_panels()


func _close_debug_panels() -> void:
	var politics := _politics.panel()
	if politics != null and politics.visible:
		_politics.toggle_panel()
	if _contact_debug != null and _contact_debug.is_open():
		_contact_debug.toggle(Vector2.ZERO)


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
func hex_screen_position(c: Vector2i) -> Vector2:
	return _screen_of_hex(c)


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
	var resumed := Session.take_simulation(operation_id)
	_resumed = resumed != null
	if _resumed:
		_simulation = resumed
		state = resumed.state
		viewer_player = int(Session.view.get("viewer", state.current_player))
	elif definition != null:
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
	if not _resumed:
		_simulation = OperationalSimulation.new(state)
		Session.start_campaign(_simulation, operation_id, seed_value)
	_simulation.event_emitted.connect(_on_operational_event)
	_simulation.command_rejected.connect(_on_command_rejected)
	if viewer_player < 0:
		viewer_player = StaffMapFormations.viewer_from_args(
			OS.get_cmdline_user_args(), state.player_sides
		)
		# No explicit --side: start on the side to play (the first turn has no turn_started
		# event to switch the view).
		if not _has_side_arg():
			viewer_player = state.current_player
	_installations = StaffMapInstallations.new()  # under the counters
	_counter_layer.add_child(_installations)
	_installations.build(state, _palette)
	_counters = StaffMapCounters.new()
	_counter_layer.add_child(_counters)
	_build_route_preview()  # after the counters: its cross and label draw over them
	_counters.build(state, _palette, viewer_player)
	_counters.refresh()  # the order marks, also when the state already holds orders
	_orders.refresh(state, viewer_player)
	_front.refresh(state, viewer_player)
	_apply_front_view()
	_update_anchors()
	if not _resumed and OS.get_cmdline_user_args().has("--pending-battle"):
		state.pending_battles.append(BattleSetup.new())


func _build_route_preview() -> void:
	_front = StaffMapFrontLine.new(_view.relief(), _palette)
	_view.add_child(_front)
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
	_installation_anchors.clear()
	for installation in _simulation.state.installations:
		var at := Hex.to_world(installation.coord, 1.0)
		_installation_anchors[installation.id] = _view.relief().surface_point(Vector2(at.x, at.z))
	_anchors.clear()
	for formation in _simulation.state.formations:
		var w := Hex.to_world(formation.coord, 1.0)
		_anchors[formation.id] = _view.relief().surface_point(Vector2(w.x, w.z))
	_slide.override_anchors(_anchors, _view.relief())


## Screen-space counters follow the camera; called only when it moved (no per-frame cost).
func _layout_counters() -> void:
	if _route_marks != null:
		_route_marks.refresh()
		_orders.refresh_projection()
		if _order_ring != null:
			_order_ring.follow()
	if _contacts != null:
		_contacts.layout()
		_place_queue()
	if _strike != null:
		_strike.layout(_viewport_size(), _turn_bar.size.y + PANEL_MARGIN.y / 2.0)
	if _installations != null:
		var spots := {}
		for id: StringName in _installation_anchors:
			spots[id] = _project(_installation_anchors[id])
		_installations.layout(spots)
	if _counters == null:
		return
	var points := {}
	for id: StringName in _anchors:
		points[id] = _project(_anchors[id])
	_counters.layout(points)
	_layout_places()


func _on_command_rejected(command: OperationalCommand, reason: String) -> void:
	if command is StrikeCommand:  # the rejection code itself (TASK-097a)
		_toast_message(reason, _palette.ui_alert)
		return
	if command is PoliticalDecisionCommand:
		_toast_message(
			TranslationServer.translate(StaffMapDecisionsModel.REASONS.get(reason, reason)),
			_palette.ui_alert
		)
		return
	_toast_message(tr("ORDER_REJECTED_" + reason.to_upper()), _palette.ui_alert)


func _on_operational_event(event: Dictionary) -> void:
	_add_new_counters()
	_contacts.on_event(event)
	if event.get("type") == &"formation_joined":
		_on_formation_joined(event)
	_marks.on_event(_simulation.state, event)
	_slide.collect(event)
	if event.get("type") == &"operational_turn_started":
		_on_turn_started(event)
	if event.get("type") == &"country_stance_changed":
		_politics.refresh(viewer_player)
	_escalation.on_event(event)
	if event.get("type") == &"operational_turn_ended":
		_decisions.close()
	if event.get("type") == &"political_decision_taken":
		_decision_lines.append(StaffMapDecisionsModel.log_text(_simulation.state, event))
	_decisions.refresh()
	if event.get("type") == &"casus_belli_gained":
		_toast_message(
			StaffMapBorders.casus_belli_event_text(_simulation.state, event), _palette.ui_amber
		)
	_on_strike_event(event)
	_update_anchors()
	_order_ring.follow()  # closes the ring when its formation may no longer be ordered
	_counters.refresh()
	_counters.apply_marks(_marks)
	_refresh_orders()
	_route.invalidate()
	_layout_counters()
	_refresh_turn_bar()
	if _panel.visible:
		select_formation(_panel.formation_id, true)
	if event.get("type") == &"operational_turn_started":
		_begin_slide()
		_show_new_report()
		if int(event.get("player", -1)) == viewer_player:
			_decision_lines.clear()  # shown (or not wanted) – the log starts over
	elif event.get("type") == &"battle_consequences":
		_begin_slide()  # the retreating counter slides back (TASK-095)
	_refresh_contacts()


## Strike events (TASK-097a): the markers' bars, the result report and the debug panel's stock line.
func _on_strike_event(event: Dictionary) -> void:
	var type: StringName = event.get("type", &"")
	_strike.on_event(event)
	if type in [&"installation_changed", &"strike_stock_changed", &"strike_launched"]:
		_installations.refresh()
		_politics.refresh(viewer_player)
	elif type == &"strike_resolved":
		_politics.refresh(viewer_player)


## Formations that joined (appended to the state) get their counters, a pulse and the country of
## origin (the country of the hex they appeared on) before any other handler reads the counters.
func _add_new_counters() -> void:
	if _counters.counter_count() == _simulation.state.formations.size():
		return
	var state := _simulation.state
	for formation in state.formations:
		if _counters.counter(formation.id) == null:
			_origins[formation.id] = state.country_at(formation.coord)
	_counters.sync_new(_origins)


## A new ally appears (TASK-118): the notice "<Country> joins <side> – N formations" counts the
## group (country + side) up.
func _on_formation_joined(event: Dictionary) -> void:
	var state := _simulation.state
	var id: StringName = event["formation_id"]
	var player: int = event["player"]
	var key := "%s|%d" % [event.get("country", &""), player]
	if key != _join_key or not _join_notice.visible:
		_join_key = key
		_join_ids = []
	_join_ids.append(id)
	var definition := CountryDefinition.find(StringName(event.get("country", &"")))
	var side := SideDefinition.find(state.player_sides[player])
	_join_notice.present(
		(
			tr("%s joins %s – %d formations")
			% [
				tr(definition.display_name) if definition != null else "?",
				tr(side.display_name) if side != null else "?",
				_join_ids.size()
			]
		),
		_join_ids,
		StaffMapFormations.side_colour(_palette, player)
	)
	_place_join_notice()


func _place_join_notice() -> void:
	_join_notice.reset_size()
	_join_notice.position = Vector2(
		(_viewport_size().x - _join_notice.size.x) / 2.0, _viewport_size().y - 190.0
	)


## *Show* on the notice: centres the map on the new formations.
func _on_join_show(ids: Array) -> void:
	if ids.is_empty():
		return
	var sum := Vector2.ZERO
	for id: StringName in ids:
		var point: Vector3 = _anchors.get(id, Vector3.ZERO)
		sum += Vector2(point.x, point.z)
	# Fully zoomed out the camera is pinned to the theatre centre, so zoom in to a mid level first.
	_set_zoom(maxf(_zoom, sqrt(_min_zoom * _max_zoom)))
	_move_camera(sum / ids.size() * StaffMapView.UNIT)


## Country of origin of a formation that joined during the operation; &"" for the starting ones.
func origin_country(formation_id: StringName) -> StringName:
	return _origins.get(formation_id, &"")


func join_notice() -> StaffMapJoinNotice:
	return _join_notice


## The contact view (TASK-094a): notice, queue, scrim.
func contacts() -> StaffMapContacts:
	return _contacts


## Shows / updates the contact notice; centres the camera on a battle hex that just became active.
func _refresh_contacts() -> void:
	if _contacts == null or _simulation == null:
		return
	if _contacts.refresh(_simulation.state, viewer_player, not is_sliding()):
		_centre_on_hex(_contacts.active_hex())
	_place_queue()


## A campaign waiting in Session (Continue, or back from a battle) names the operation and seed.
func _take_session_operation() -> void:
	if Session.resuming():
		operation_id = Session.operation_id
		seed_value = Session.seed_value


## F5 / Save: writes the campaign (also with a battle pending) to `<save_dir>/<operation>.json`
## with the viewer as the human's side; "Saved" or the failure in the toast.
func save_campaign() -> bool:
	if _simulation == null:
		return false
	var record := Session.record(viewer_player)
	var path := CampaignSaver.path_for(String(operation_id), save_dir)
	if record == null or CampaignSaver.save(record, path) != OK:
		_toast_message(tr("CAMPAIGN_SAVE_FAILED"), _palette.ui_alert)
		return false
	_toast_message(tr("CAMPAIGN_SAVED"), _palette.ui_amber)
	return true


## B on the notice: Play battle.
func _play_battle() -> void:
	_contacts.notice.press_play()


## Play battle (TASK-094c): hands the simulation, the human's side (the viewer) and the view
## settings to Session, which cuts the first pending battle's map, then opens the battle scene.
## False (toast) when the battle cannot be played.
func play_battle() -> bool:
	if _simulation == null or is_sliding():
		return false
	var problem := Session.play_battle(_simulation, operation_id, viewer_player, view_settings())
	if problem != "":
		_toast_message(tr("CONTACT_PLAY_FAILED_" + problem.to_upper()), _palette.ui_alert)
		return false
	if open_scene.is_valid():
		open_scene.call(Session.BATTLE_SCENE)
	else:
		Session.change_scene(get_tree() if is_inside_tree() else null, Session.BATTLE_SCENE)
	return true


## Auto-resolve (TASK-120): the first pending battle is resolved at once through Session (no
## battle scene); the staff map stays and shows the short result notice. False (toast) when it
## cannot be resolved.
func auto_resolve() -> bool:
	if _simulation == null or is_sliding():
		return false
	var problem := Session.auto_resolve(_simulation, operation_id)
	if problem != "":
		_toast_message(tr("CONTACT_AUTO_FAILED"), _palette.ui_alert)
		return false
	var report := Session.take_report()
	_result_notice.present(
		_simulation.state,
		report["setup"],
		report["result"],
		_palette,
		viewer_player,
		report["events"]
	)
	_place_result_notice()
	return true


## What the human set up on the map and gets back after a battle: camera (position, zoom, pitch),
## viewer and follow, the selection, the grid / front tint / borders toggles and the joined
## formations' countries of origin.
func view_settings() -> Dictionary:
	return {
		"position": _position,
		"zoom": _zoom,
		"pitch": _pitch,
		"pitch_target": _pitch_target,
		"tilt": _tilt,
		"viewer": viewer_player,
		"selected": selected_formation(),
		"grid": _view.grid_visible(),
		"front_tint": _front.is_tint_visible(),
		"borders": _view.countries().is_visible_layer(),
		"origins": _origins.duplicate(),
	}


## Back from a battle: the queue from the state, the view as it was, the battle's result notice.
func _resume() -> void:
	_origins = (Session.view.get("origins", {}) as Dictionary).duplicate()
	for id: StringName in _origins:
		var origin := CountryDefinition.find(StringName(_origins[id]))
		var counter := _counters.counter(id)
		if origin != null and counter != null:
			counter.country_tag = origin.iso_code
	_contacts.sync(_simulation.state)
	_refresh_contacts()
	_apply_view_settings(Session.view)
	var report := Session.take_report()
	if not report.is_empty():
		_result_notice.present(
			_simulation.state,
			report["setup"],
			report["result"],
			_palette,
			viewer_player,
			report["events"]
		)
		_place_result_notice()
		for event: Dictionary in report["events"]:  # the retreat slides although the map is new
			_slide.collect(event)
		_begin_slide()


func _apply_view_settings(settings: Dictionary) -> void:
	if not settings.has("zoom"):
		return  # Continue only sets the viewer
	_pitch = settings["pitch"]
	_pitch_target = settings["pitch_target"]
	_tilt = settings["tilt"]
	_update_limits()
	_zoom = clampf(settings["zoom"], _min_zoom, _max_zoom)
	_move_camera(settings["position"])
	_view.set_grid_visible(settings["grid"])
	_front.set_tint_visible(settings["front_tint"])
	_view.countries().set_visible_layer(settings["borders"])
	_apply_front_view()
	select_formation(settings["selected"])


## Enter / Esc close the battle result notice; true when it did.
func _close_result_notice(keycode: Key) -> bool:
	if not _result_notice.visible or keycode not in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		return false
	_result_notice.close()
	return true


## Screenshot aid: resolves the first pending battle as a demo win of the attacker (the
## defender's companies at half strength, the attacker's lose one) and shows the result notice.
func debug_result_notice() -> void:
	var state := _simulation.state
	if state.pending_battles.is_empty():
		return
	var setup := state.pending_battles[0]
	var result := StaffMapContacts.draw_result(setup)
	result.winner = setup.attacker
	result.reason = &"objective_taken"
	result.turns = 7
	for company in result.companies:
		var attacking := company.player == setup.attacker
		company.strength_end = (
			maxi(company.strength_start - 1, 0)
			if attacking
			else floori(company.strength_start / 2.0)
		)
	for company in result.companies:  # one destroyed company, to see that state
		if company.player != setup.attacker:
			company.strength_end = 0
			break
	result.field_holder = setup.attacker
	result.retreat = 1 - setup.attacker
	var events: Array[Dictionary] = []
	var collect := func(event: Dictionary) -> void: events.append(event)
	_simulation.event_emitted.connect(collect)
	var accepted := _simulation.execute(ResolveBattleCommand.new(result))
	_simulation.event_emitted.disconnect(collect)
	if accepted:
		_result_notice.present(state, setup, result, _palette, viewer_player, events)
		_place_result_notice()


func result_notice() -> StaffMapBattleResult:
	return _result_notice


func _place_result_notice() -> void:
	_result_notice.reset_size()
	_result_notice.position = Vector2(
		(_viewport_size().x - _result_notice.size.x) / 2.0,
		maxf((_viewport_size().y - _result_notice.size.y) / 2.0, 8.0)
	)


## The queue sits at the left edge, under the turn report when that is open.
func _place_queue() -> void:
	var queue := _contacts.queue
	if not queue.visible:
		return
	queue.reset_size()
	var top := 130.0
	if _report != null and _report.visible:
		top = _report.position.y + _report.size.y + 12.0
	queue.position = Vector2(PANEL_MARGIN.x, top)


## The counters of everything that moved slide to their new hexes (cosmetic: state is final).
func _begin_slide() -> void:
	skip_slide()
	if _slide.begin():
		_refresh_orders()  # the arrows wait until the counters stand
		_slide.override_anchors(_anchors, _view.relief())
		_layout_counters()
		_refresh_turn_bar()


func _finish_slide() -> void:
	_update_anchors()
	_layout_counters()
	_refresh_orders()
	_refresh_turn_bar()
	_show_new_report()
	_refresh_contacts()


## Issued orders of the viewed side and the front line; both hidden while the counters slide.
func _refresh_orders() -> void:
	_orders.refresh(_simulation.state, -1 if is_sliding() else viewer_player)
	_front.refresh(_simulation.state, viewer_player, not is_sliding())
	_apply_front_view()


## The front line follows the camera scale, the zoom level and the grid (exact hex edges at Z2).
func _apply_front_view() -> void:
	_front.set_view(_scale(), _view.zoom_level(), _view.grid_visible() and _view.zoom_level() == 2)


## Opens the report panel with the viewed side's last report.
func _show_report() -> void:
	_report.show_report(_simulation.state, _marks.report_of(viewer_player), _decision_lines)
	_report.show()
	_report.reset_size()
	_report.position = Vector2(PANEL_MARGIN.x, 130.0)


## Opens the report of the viewed side's last move once, when it is new (not during the slide).
func _show_new_report() -> void:
	if _report != null and not is_sliding() and _marks.take_unseen(viewer_player):
		_show_report()


func _on_report_entry(formation_id: StringName, _coord: Vector2i) -> void:
	select_formation(formation_id)
	_centre_on(formation_id)


## The move changed hands: the banner names the bloc.
func _on_turn_started(event: Dictionary) -> void:
	var player: int = event["player"]
	var state := _simulation.state
	var colour := StaffMapFormations.side_colour(_palette, player)
	_banner.show_timed(
	if player != viewer_player:
		set_viewer(player)  # hot-seat (no AI yet): the human orders whichever bloc is to move
		"%s %02d" % [tr("TURN"), state.turn],
		(tr("%s to move") % StaffMapTurnBar.side_name(state, player)).to_upper(),
		colour
	)


func _has_side_arg() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(StaffMapFormations.SIDE_ARG):
			return true
	return false


func _refresh_turn_bar() -> void:
	if _turn_bar != null and _simulation != null:
		_turn_bar.set_busy(is_sliding())
		_turn_bar.show_state(_simulation.state, _palette, viewer_player)
		_place_turn_bar()
		_place_panel()


func _place_turn_bar() -> void:
	_turn_bar.position = Vector2((_viewport_size().x - _turn_bar.size.x) / 2.0, 0.0)


func _toggle_ladder_card() -> void:
	_escalation.toggle_card()


## True while a full-screen window (Politics screen, ladder window) dims the map.
func _modal_open() -> bool:
	return (
		(_decisions != null and _decisions.is_open())
		or (_escalation != null and _escalation.card().visible)
	)


## The ladder window opens: every other staff-map window closes.
func _close_other_windows() -> void:
	_decisions.close()
	if _strike != null:
	_options.close()
		_strike.reports().suspend()
		_strike.close()
	_politics.close_card()
	_close_debug_panels()


## Key H / the Decisions button: the Politics screen (closes the ladder card).
func toggle_decisions() -> void:
	if _decisions == null:
		return
	_escalation.close_card()
	_decisions.toggle()


func decisions_hud() -> StaffMapDecisionsHud:
	return _decisions


## Key S / the Strike button: opens or closes the strike mode (TASK-097b); closes the other cards.
func toggle_strike_mode() -> void:
	if _strike == null:
		return
	if not _strike.is_open():
		_escalation.close_card()
		_decisions.close()
		select_formation(&"")
	_strike.toggle()
	_sync_action_bar()


func strike_hud() -> StaffMapStrikeHud:
	return _strike


func _on_strike_open_changed(open: bool) -> void:
	_sync_action_bar()
	if not open:
		_installation_card.set_note("")
	_layout_counters()


func escalation_hud() -> StaffMapEscalationHud:
	return _escalation


func _place_panel() -> void:
	if _panel == null:
		return
	_panel.dock(_viewport_size().x)  # right dock, under the turn bar row


## Centres the camera on a formation whose counter is off screen (Tab).
func _reveal(formation_id: StringName) -> void:
	if not _anchors.has(formation_id):
		return
	var screen := counter_screen_position(formation_id)
	if Rect2(Vector2.ZERO, _viewport_size()).grow(-60.0).has_point(screen):
		return
	_centre_on(formation_id)


## Centres the camera on a hex.
func _centre_on_hex(c: Vector2i) -> void:
	var w := Hex.to_world(c, 1.0)
	var point := _view.relief().surface_point(Vector2(w.x, w.z))
	_move_camera(Vector2(point.x, point.z) * StaffMapView.UNIT)


## Centres the camera on a formation.
func _centre_on(formation_id: StringName) -> void:
	if not _anchors.has(formation_id):
		return
	var point: Vector3 = _anchors[formation_id]
	_move_camera(Vector2(point.x, point.z) * StaffMapView.UNIT)


func _build_hud() -> void:
	_card = StaffMapCard.new()
	_hud.add_child(_card)
	_installation_card = StaffMapInstallationCard.new()
	_hud.add_child(_installation_card)
	_panel = StaffMapFormationPanel.new()
	_hud.add_child(_panel)
	_turn_bar = StaffMapTurnBar.new()
	_panel.close_requested.connect(func() -> void: select_formation(&""))
	_turn_bar.end_turn_pressed.connect(end_turn)
	_turn_bar.escalation_pressed.connect(func() -> void: _toggle_ladder_card())
	_hud.add_child(_turn_bar)
	_report = StaffMapTurnReport.new()
	_report.entry_chosen.connect(_on_report_entry)
	_hud.add_child(_report)
	_banner = TurnBanner.new()
	_hud.add_child(_banner)
	_order_ring = StaffMapOrderRing.new(_hud, _execute, _screen_of_hex, _viewport_size, _can_order)
	_order_ring.ordered.connect(_on_ring_ordered)
	_order_ring.closed.connect(_on_ring_closed)
	_toast = Toast.new()
	_hud.add_child(_toast)
	_border_prompt = StaffMapBorderPrompt.new(
		_palette, float(ActionBar.HEIGHT + ActionBar.NOTICE_GAP)
	)
	_hud.add_child(_border_prompt)
	_join_notice = StaffMapJoinNotice.new()
	_join_notice.show_pressed.connect(_on_join_show)
	_hud.add_child(_join_notice)
	_contacts = StaffMapContacts.new(
		_palette,
		_counter_layer,
		_hud,
		_simulation.execute,
		_screen_of_hex,
		_viewport_size,
		OS.get_cmdline_user_args().has("--debug")
	)
	_contacts.play_requested.connect(play_battle)
	_contacts.auto_requested.connect(auto_resolve)
	_result_notice = StaffMapBattleResult.new()
	_hud.add_child(_result_notice)
	_back = MenuStyle.button("")
	_back.position = Vector2(16, 16)
	_back.pressed.connect(_return_to_menu)
	_back.focus_mode = Control.FOCUS_NONE
	_hud.add_child(_back)
	_build_action_bar()
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
	_escalation = StaffMapEscalationHud.new(_simulation, _palette, _hud, _toast_message)
	_escalation.menu_requested.connect(_return_to_menu)
	_decisions = StaffMapDecisionsHud.new(
		_simulation, _palette, _hud, func() -> int: return viewer_player
	_escalation.ladder_opening.connect(_close_other_windows)
	)
	_strike = StaffMapStrikeHud.new(
		_simulation,
		_palette,
		_hud,
		_counter_layer,
		_screen_of_hex,
		func() -> int: return viewer_player,
		_toast_message
	)
	_strike.open_changed.connect(_on_strike_open_changed)
	_strike.reports().shown.connect(func() -> void: _claim_left_dock(LeftWindow.REPORT))
	if OS.get_cmdline_user_args().has("--debug"):
		contact_debug()


## F9 (--debug): the politics and the contact-map panels open and close together, the contact
## panel under the politics one.
func toggle_debug_panels() -> void:
	if _politics.panel() == null and _contact_debug == null:
		return
	var opening := _contact_debug != null and not _contact_debug.is_open()
	if opening:
		_claim_left_dock(LeftWindow.DEBUG)
	var politics := _politics.panel()
	if politics != null and politics.visible != opening:
		_politics.toggle_panel()
	if _contact_debug != null and opening != _contact_debug.is_open():
		var top := Vector2(16, 130)
		if politics != null and politics.visible:
			top.y += politics.size.y + 12
		_contact_debug.toggle(top)


## The debug contact-map preview (TASK-094b); made on first use (with --debug at build, else for
## the screenshot tool and tests).
func contact_debug() -> StaffMapContactDebug:
	if _contact_debug == null and _view != null:
		_contact_debug = StaffMapContactDebug.new(
			_view, _simulation.state, _imported, _palette, _hud
		)
	return _contact_debug


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
	_layout_places()
	if _front != null:
		_apply_front_view()


## Place names follow the camera; recomputed only when it (or the zoom level, toggle) changed.
func _layout_places() -> void:
	if _places != null and _view != null:
		_places.layout(
			_project,
			_viewport_size(),
			_places_level(),
			[_target(), _scale(), _pitch],
			_counters.screen_rects() if _counters != null else ([] as Array[Rect2])
		)


## Zoom level for the place names: no hysteresis, so zooming in and out switches at the same
## scroll step (the view's own level keeps its hysteresis for the grid and hatching).
func _places_level() -> int:
	return StaffMapCameraMath.zoom_level(
		_scale() / _km_per_unit, 0, _palette.zoom_level_px_per_km, 0.0
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
			if event.pressed and is_sliding():
				skip_slide()  # a click only skips the slide
				_dragging = false
				return
			if event.pressed:
				close_docked_windows()
			if event.pressed:
				_press_position = event.position
				_drag_travel = 0.0
			elif (
				_drag_travel < CLICK_SLOP
				and event.position.distance_to(_press_position) < CLICK_SLOP
			):
				click_at(event.position)
		MOUSE_BUTTON_RIGHT:
			if not event.pressed:
				right_click_at(event.position)
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


func _strike_mode_open() -> bool:
	return _strike != null and _strike.is_open()


func _zoom_at(notches: float, cursor: Vector2) -> void:
	var new_zoom := StaffMapCameraMath.zoom_by(_zoom, notches, _min_zoom, _max_zoom)
	var size := _viewport_size()
## A click on the map closes every docked window (left dock and the strike report card; the
## formation panel follows the selection, which `click_at` clears on an empty hex).
func close_docked_windows() -> void:
	var closed := _options.close()
	closed = _politics.close_card() or closed
	if _report != null and _report.visible:
		_report.close()
	if _strike != null and _strike.reports().card_visible():
		_strike.reports().collapse()
	if closed:
		_sync_action_bar()


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
			float(
				(
					(Input.is_physical_key_pressed(KEY_S) and not _strike_mode_open())
					or Input.is_physical_key_pressed(KEY_DOWN)
				)
			)
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


## A left click on the map: with the order ring open it only closes it; otherwise selects the
## counter under `screen`. With an own formation selected a click on a hex gives it a MARCH order
## there (and deselects it), a click on an enemy counter or hex an ATTACK order; elsewhere it
## deselects.
func click_at(screen: Vector2) -> void:
	if _counters == null:
		return
	if _order_ring.is_open():
		_order_ring.close()
		return
	if _mode_click(screen):
		return
	var hit := _counters.counter_at(screen)
	var target := _enemy_of_selected(hit)
	if target != null:
		if issue_order(target.coord):
			select_formation(&"")
		return
	if hit == &"":
		var named := _politics.country_name_at(ground_at_screen(screen))
		if named != &"":
			open_country_card(named)
			return
		_politics.close_card()
	if hit == &"" and _selected_own() != null:
		var hex := hex_at_screen(screen)
		if _view.has_tile(hex):
			if issue_order(hex):
				select_formation(&"")  # done with this one; the next click must not re-order it
			return
	select_formation(hit)


## A right click on the map: with an own formation selected (and its side to play) opens the order
## ring on the hex under `screen`; otherwise it only closes an open ring. Returns true when the
## ring is open afterwards.
func right_click_at(screen: Vector2) -> bool:
	if _counters == null:
		return false
	var was_open := _order_ring.is_open()
	_order_ring.close()
	var formation := _selected_own()
	if formation == null or not _can_order(formation.id):
		return false
	var hex := hex_at_screen(screen)
	if not _view.has_tile(hex):
		return false
	_order_ring.open(
		_simulation.state, formation, hex, StaffMapFormations.side_colour(_palette, viewer_player)
	)
	return was_open or _order_ring.is_open()


## The enemy formation behind counter `hit` when an own formation is selected; null otherwise.
func _enemy_of_selected(hit: StringName) -> Formation:
	var own := _selected_own()
	if own == null or hit == &"" or _simulation == null:
		return null
	var other := _simulation.state.get_formation(hit)
	return other if other != null and other.owner_id != own.owner_id else null


## True while `formation_id` is an own formation whose side is the side to play.
func _can_order(formation_id: StringName) -> bool:
	var formation := _simulation.state.get_formation(formation_id)
	return (
		formation != null
		and formation_id == selected_formation()
		and formation.owner_id == viewer_player
		and formation.owner_id == _simulation.state.current_player
	)


func _on_ring_ordered(action: StringName) -> void:
	if action != StaffMapOrderRingModel.CANCEL:
		select_formation(&"")  # done with this one, as after a left click order
	else:
		select_formation(selected_formation(), true)


func _on_ring_closed() -> void:
	if _route != null:
		_route.set_posture(&"")


func _update_hover() -> void:
	if _dragging or not DisplayServer.window_is_focused():
		return
	if _order_ring.is_open():
		_hover_ring()
		return
	var mouse := get_viewport().get_mouse_position()
	if not get_viewport().get_visible_rect().has_point(mouse):
		_clear_hover()
		return
	if _panel != null and _panel.visible and _panel.get_global_rect().has_point(mouse):
		_clear_hover()  # the panel covers the map
		return
	if _strike != null and _strike.is_open():
		_strike.set_hover(&"" if _strike.covers(mouse) else _strike_target_at(mouse))
	if _counters != null:
		_counters.set_hovered(_counters.counter_at(mouse))
	var c := hex_at_screen(mouse)
	if not _view.has_tile(c):
		_clear_hover()
		return
	if _hover_installation(mouse):
		_route.set_hex(StaffMapRoutePreview.OFF)
		_view.highlight(StaffMapView.NO_HEX)
		return
	_installation_card.hide()
	_route.set_hex(c)
	if c != _view.hovered() or not _card.visible:
		_view.highlight(c)
		_card.show_info(_card_info(c))
	_last_mouse = mouse


## While the order ring is open the route preview shows its hex in the hovered posture.
func _hover_ring() -> void:
	_card.hide()
	if _counters != null:
		_counters.set_hovered(&"")
	_route.set_posture(_order_ring.hovered_posture())
	_route.set_hex(_order_ring.hex())
	_view.highlight(_order_ring.hex())


## A click taken by the debug contact picker or the open strike mode; true then.
func _mode_click(screen: Vector2) -> bool:
	if _contact_debug != null and _contact_debug.click(hex_at_screen(screen)):
		return true
	if _strike != null and _strike.is_open():
		_strike.click(_strike_target_at(screen))
		return true
	return false


## The enemy target under `screen` for the strike mode (counter, marker or hex), or &"".
func _strike_target_at(screen: Vector2) -> StringName:
	var marker := _installations.marker_at(screen)
	var counter := _counters.counter_at(screen)
	return _strike.target_at(counter, marker, hex_at_screen(screen))


## Shows the installation card when the cursor is on a marker (and no counter); true then.
func _hover_installation(mouse: Vector2) -> bool:
	var id := &""
	if _counters == null or _counters.counter_at(mouse) == &"":
		id = _installations.marker_at(mouse)
	_installations.set_hovered(id)
	if id == &"":
		return false
	_installation_card.show_info(
		StaffMapInstallations.info(_simulation.state, _simulation.state.get_installation(id))
	)
	_installation_card.set_note(_strike.hover_note(id) if _strike != null else "")
	_card.hide()
	_place_card(mouse, _installation_card)
	return true


func _clear_hover() -> void:
	if _strike != null:
		_strike.set_hover(&"")
	if _installations != null:
		_installations.set_hovered(&"")
		_installation_card.hide()
	if _route != null:
		_route.set_hex(StaffMapRoutePreview.OFF)
	_view.highlight(StaffMapView.NO_HEX)
	if _counters != null:
		_counters.set_hovered(&"")
	_card.hide()


## Puts the card next to `screen`, kept inside the window.
func _place_card(screen: Vector2, card: Control = null) -> void:
	if card == null:
		card = _card
	var size := _viewport_size()
	var at := screen + CARD_OFFSET
	if at.x + card.size.x > size.x:
		at.x = screen.x - CARD_OFFSET.x - card.size.x
	if at.y + card.size.y > size.y:
		at.y = screen.y - CARD_OFFSET.y - card.size.y
	card.position = at


func _return_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
