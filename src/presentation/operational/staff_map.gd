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
enum LeftWindow { REPORT, COUNTRY_CARD, DEBUG, OPTIONS, MENU, OBJECTIVES }
## (The ladder window is a full-screen overlay: opening it closes all of them, see
## `_close_other_windows`; opening any of them closes it.)

## Width of the hex strip slot in the bottom bar.
const CARD_SLOT_WIDTH := 470
const ACTION_GRID := &"grid"
const ACTION_NAMES := &"names"
const ACTION_BORDERS := &"borders"
const DOCK_SLIDE_SECONDS := 0.2  # the dock slides and the map follows (ease-out)
const ACTION_POLITICS := &"politics"
const ACTION_FLAT := &"flat"
const ACTION_COVER := &"cover"
const ACTION_CONTROL := &"control"
const ACTION_NEXT := &"next"
const ACTION_CANCEL := &"cancel"
const ACTION_REPORT := &"report"
const ACTION_JOURNAL := &"journal"
const ACTION_OBJECTIVES := &"objectives"
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
const PANEL_FADE := 0.12  # s, the formation panel fading in on a new dock
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
## The side the AI leader plays (TASK-102c): the one that is not the viewer when the map opens;
## -1 = hot-seat (`--hotseat`, both sides human). Tests may set it and swap `ai_turn`.
var ai_side := -1
## Plays one AI turn: Callable(sim: OperationalSimulation, player: int) (the test seam).
var ai_turn: Callable = OperationalAiTurn.play
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
var _menu_button: StaffMapMenuButton  # hamburger, top-left: opens the operation menu
var _menu: StaffMapMenuWindow  # Save, Exit operation
var _exit_confirm: StaffMapExitConfirm  # "leave the operation?" (offers a save when unsaved)
var _unsaved := false  # the operation changed since the last save (or since it was built)
var _options: StaffMapOptionsWindow  # map layer toggles under the MAP button
var _journal: StaffMapJournalWindow  # the operational journal (JRN, J)
var _journal_ring: StaffMapJournalRing
var _journal_dirty := false
var _dock := StaffMapRightDock.new()  # the right tabbed dock: strike + journal (TASK-174a)
var _dock_view: StaffMapRightDockView
var _dock_inset := 0.0  # animated screen px the dock covers (0 .. StaffMapRightDock.WIDTH)
var _dock_tween: Tween
var _objectives: StaffMapObjectivesWindow  # what the operation is scored on (O)
var _bar: ActionBar
var _hud: CanvasLayer
var _simulation: OperationalSimulation
var _counter_layer: CanvasLayer
var _counters: StaffMapCounters
var _places: StaffMapPlaceLayer  # place-name labels (TASK-112), N toggles
var _installations: StaffMapInstallations
var _support_ghosts: StaffMapSupportGhosts  # arrivals of outside support on the way (TASK-121)
var _cover: StaffMapAirDefenceLayer  # air defence coverage zones (TASK-098b), under the markers
var _cover_on := false  # the player's toggle (key C); strike mode adds it while a weapon is picked
var _installation_card: StaffMapInstallationCard
var _installation_anchors := {}  # installation id -> point on the relief
var _panel: StaffMapFormationPanel
var _turn_bar: StaffMapTurnBar
var _route: StaffMapRoutePreview
var _route_marks: StaffMapRouteMarks
var _orders: StaffMapOrders
var _front: StaffMapFrontLine
var _control: StaffMapControlLayer  # terrain control (TASK-152), under the front line
var _reach: StaffMapReachLayer  # T+1 march contour of the armed formation (TASK-155)
var _order_ring: StaffMapOrderRing
var _unit_strip: StaffMapUnitStrip  # a formation in the hex strip's slot (TASK-151)
var _gesture := StaffMapOrderGesture.new()  # click own counter, aim, click hex (TASK-153)
var _route_ribbon: StaffMapRouteRibbon
var _order_ribbon: StaffMapRouteRibbon
var _fresh_ribbon: StaffMapRouteRibbon  # the order just issued settles here
var _aim_key := []  # [hex, posture, formation id, orders left] of the cached hover verdict
var _aim_verdict := {}
var _movement := OperationalMovement.shipped()
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
var _left_column_y := 130.0
var _contacts: StaffMapContacts
var _result_notice: StaffMapBattleResult
var _resumed := false  # the simulation came back from a played battle (Session)
var _marks := StaffMapTurnMarks.new()
var _ai_turn_key := -1  # turn * 2 + player of the AI turn already played
var _posture_switcher: StaffMapPostureSwitcher  # the posture strip under the selected counter
var _posture_key := []  # the last state handed to the strip (no work while it is unchanged)
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
var _raised_marker: StringName = &""  # installation drawn above the counters (_pick_counter)
var _insets := Vector4()  # HUD-covered screen px (top, bottom, left, right), see _clear_insets
var _ease: Tween  # camera ease that brings a selected counter into the clear zone
var _panel_fade: Tween
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
	_unsaved = false
	is_built = true
	refresh_texts()
	return true


func _notification(what: int) -> void:
	FramePacing.apply_notification(what)


func _process(delta: float) -> void:
	if not is_built:
		return
	var modal := _modal_open()  # the exit prompt idles the map
	if not modal:
		_pitch_by_keys(delta)
	_follow_pitch(delta)
	if not modal:
		_pan_by_keys_and_edge(delta)
		_update_hover()
	_sync_unit_strip(modal)
	_sync_action_bar()
	_sync_insets()
	_sync_left_column()
	_tick_journal(delta)
	advance_slide(delta)
	play_ai_turn_if_due()
	if _strike != null:
		_strike.tick(delta)
	if _route != null:
		_route.tick(Time.get_ticks_msec())
	_tick_gesture(delta)
	_sync_posture_switcher()


## Per frame: the journal is rebuilt once after new events while open; the ring follows the camera.
func _tick_journal(delta: float) -> void:
	if _journal_dirty:
		_journal_dirty = false
		_journal.refresh()
	if _journal_ring != null and _journal_ring.is_active():
		_journal_ring.tick(delta, _screen_of_hex)


func _unhandled_input(event: InputEvent) -> void:
	if not is_built:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		# The open POLITICS tab takes its own keys (cards, arrows, Enter, Tab); Esc closes the ring,
		# 1-4 pick a slot; Enter / Esc close the result notice.
		if (
			(_decisions != null and _decisions.handle_key(key.keycode))
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
					cancel_exit()
					or close_menu()
					or _close_options_key()
					or _close_dock_key()
					or _close_objectives_key()
					or _politics.close_card()
					or close_info()
					or _cancel_gesture()
				):
					return
				if selected_formation() != &"":
					select_formation(&"")
				else:
					toggle_menu()
			KEY_ENTER, KEY_KP_ENTER:
				end_turn()
			KEY_SPACE:
				skip_slide()
			KEY_R:
				toggle_report()
			KEY_J:
				toggle_journal()
			KEY_O:
				toggle_objectives()
			KEY_DELETE, KEY_BACKSPACE, KEY_X:
				cancel_order()
			KEY_G:
				toggle_grid()
			KEY_T:
				open_country_card(_card_hex_country())
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
				toggle_air_defence_cover()
			KEY_K:
				toggle_terrain_control()
			KEY_V:
				toggle_flat_view()
			KEY_I:
				toggle_info()
			KEY_1, KEY_2, KEY_3:
				_pick_posture_key(key.keycode - KEY_1 + 1)
		return
	if _modal_open():
		_dragging = false  # a full-screen prompt idles the map: no wheel zoom, drag or click
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
	_bar.add_action(ACTION_OBJECTIVES, "OBJECTIVES", "O", true, "TIP_OBJECTIVES")
	_bar.add_action(ACTION_JOURNAL, "JOURNAL", "J", true, "TIP_JOURNAL")
	_bar.add_action(
		ACTION_DECISIONS,
		"DECISIONS",
		OS.get_keycode_string(StaffMapDecisionsPanel.OPEN_KEY),
		true,
		"TIP_DECISIONS"
	)
	_bar.add_action(ACTION_STRIKE, "STRIKE", "S", true, "TIP_STRIKE")
	_bar.action_pressed.connect(_on_action_pressed)
	_hud.add_child(_bar)
	_build_options_window()
	_build_journal()
	_build_objectives()
	# The hovered hex lives in the left zone (a fixed-width slot, so the bar does not jump).
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(CARD_SLOT_WIDTH, 50)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.remove_child(_card)
	slot.add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.remove_child(_unit_strip)
	slot.add_child(_unit_strip)
	_unit_strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	_options.add_option(ACTION_COVER, tr("AIR DEFENCE COVER"), "C")
	_options.add_option(ACTION_CONTROL, tr("TERRAIN CONTROL"), "K")
	_options.option_toggled.connect(_on_action_pressed)
	_options.close_requested.connect(close_options)
	_hud.add_child(_options)


## The operational journal window (JRN button, key J) and the ring it puts on a clicked hex.
func _build_journal() -> void:
	_journal = StaffMapJournalWindow.new(_palette)
	_journal.place_namer = _place_name
	_journal.close_requested.connect(close_journal)
	_journal.entry_chosen.connect(_on_journal_entry)
	_hud.add_child(_journal)  # moved into the right dock by _build_right_dock
	_journal_ring = StaffMapJournalRing.new()
	_hud.add_child(_journal_ring)
	_journal.show_journal(_simulation.state, viewer_player)
	_journal.mark_seen()  # what happened before the map was built counts as read
	_journal.hide()


## The objectives window (OBJECTIVES button, key O): objectives, holders, round counter.
func _build_objectives() -> void:
	_objectives = StaffMapObjectivesWindow.new()
	_objectives.close_requested.connect(close_objectives)
	_hud.add_child(_objectives)


func objectives_window() -> StaffMapObjectivesWindow:
	return _objectives


func toggle_objectives() -> void:
	if _objectives.is_open():
		close_objectives()
	else:
		open_objectives()


## Opens the objectives for the viewed side with the current holders (closes other left windows).
func open_objectives() -> void:
	_claim_left_dock(LeftWindow.OBJECTIVES)
	_objectives.show_objectives(_simulation.state, viewer_player)
	_objectives.show()
	_objectives.dock(_viewport_size().x)
	_sync_action_bar()


func _close_objectives_key() -> bool:
	if not _objectives.is_open():
		return false
	close_objectives()
	return true


func close_objectives() -> void:
	_objectives.close()
	_sync_action_bar()


func journal_window() -> StaffMapJournalWindow:
	return _journal


func journal_ring() -> StaffMapJournalRing:
	return _journal_ring


## J / the JRN button: the journal tab of the right dock (the key of the open tab closes it).
func toggle_journal() -> void:
	if _dock.is_tab_open(StaffMapRightDock.Tab.JOURNAL):
		close_journal()
	else:
		open_journal()


## Opens the journal tab for the viewed side (leaves the strike mode); `focus` (an entry of the
## viewed side) is scrolled to and lit.
func open_journal(focus: OperationalJournal.Entry = null) -> void:
	var was_open := _dock.is_open()
	var was_tab := _dock.tab()
	_dock.open(StaffMapRightDock.Tab.JOURNAL)
	if _strike != null and _strike.is_open():
		_strike.close()  # its open_changed(false) finds the tab already switched
	_close_right_info_panel()
	_journal.show_journal(_simulation.state, viewer_player, focus)
	_journal.show()
	_dock_changed(was_open, was_tab)


func _close_dock_key() -> bool:
	if not _dock.is_open():
		return false
	close_dock()
	return true


func close_journal() -> void:
	if _dock.is_tab_open(StaffMapRightDock.Tab.JOURNAL):
		close_dock()


## Esc / X / a selection / leaving the strike mode: closes the dock (the map slides back).
func close_dock() -> bool:
	var was_tab := _dock.tab()
	if not _dock.close():
		return false
	if was_tab == StaffMapRightDock.Tab.STRIKE and _strike != null and _strike.is_open():
		_strike.close()
	_dock_changed(true, was_tab)
	return true


## The dock model (tests, screenshots).
func right_dock() -> StaffMapRightDock:
	return _dock


func right_dock_view() -> StaffMapRightDockView:
	return _dock_view


## Screen px the dock covers right now (animated 0 .. 420).
func dock_inset() -> float:
	return _dock_inset


## The bar button of the dock (STR / JRN with no section open): the last tab opens.
func _on_dock_tab_pressed(tab: StaffMapRightDock.Tab) -> void:
	match tab:
		StaffMapRightDock.Tab.STRIKE:
			toggle_strike_mode()
		StaffMapRightDock.Tab.POLITICS:
			toggle_decisions()
		_:
			toggle_journal()


## Brings the panels, tab strip, bar lights and the slide in line with the model after it changed
## (`was_open` / `was_tab`: what it was before).
func _dock_changed(was_open: bool, was_tab: StaffMapRightDock.Tab) -> void:
	if _dock_view == null:
		return
	var open := _dock.is_open()
	var tab := _dock.tab()
	_dock_view.set_active_tab(int(tab) if open else -1)
	_dock_view.show_tabs(open)
	if open:
		_dock_view.layout(_viewport_size())
		if tab != StaffMapRightDock.Tab.JOURNAL:
			_journal.close()  # counts what it showed as seen
		for other: StaffMapRightDock.Tab in StaffMapRightDock.Tab.values():
			if other != tab:
				_dock_view.panel(other).hide()
		var panel := _dock_view.panel(tab)
		panel.show()
		if was_open and was_tab != tab:
			_dock_view.fade_in(panel)
		else:
			panel.modulate.a = 1.0
		_animate_dock(1.0)
	else:
		# the sections vanish at once; the map slides back over the freed area
		_journal.close()  # counts what it showed as seen
		for tab_id: StaffMapRightDock.Tab in StaffMapRightDock.Tab.values():
			_dock_view.panel(tab_id).hide()
		_animate_dock(0.0)
	_sync_action_bar()


## Slides the dock (and so the free map area) to `target` 0 / 1 in 200 ms, ease-out.
func _animate_dock(target: float) -> void:
	var goal := StaffMapRightDock.WIDTH * target
	if _dock_tween != null:
		_dock_tween.kill()
	if not is_inside_tree() or absf(goal - _dock_inset) < 0.5:
		_set_dock_inset(goal)
		_dock_finished()
		return
	_dock_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_dock_tween.tween_method(_set_dock_inset, _dock_inset, goal, DOCK_SLIDE_SECONDS)
	_dock_tween.tween_callback(_dock_finished)


## One animation step: the dock holder moves and the camera keeps the centre of the visible map.
func _set_dock_inset(inset: float) -> void:
	var delta := inset - _dock_inset
	_dock_inset = inset
	_dock_view.set_progress(inset / StaffMapRightDock.WIDTH)
	if delta != 0.0:
		_position += StaffMapCameraMath.drag_delta(Vector2(-delta * 0.5, 0.0), _zoom, _pitch)
	_insets = _clear_insets()
	_move_camera(_position)


## Test / screenshot aid: jumps a running dock slide to its end.
func settle_dock() -> void:
	if _dock_tween != null:
		_dock_tween.kill()
	_set_dock_inset(_dock.inset())
	_dock_finished()


func _dock_finished() -> void:
	_dock_view.set_progress(_dock_inset / StaffMapRightDock.WIDTH)


## A unit was selected (selection, INFO ring, key I): the dock closes and stays closed, except in
## the strike mode, where a map click is a target pick.
func _close_dock_on_selection() -> void:
	var was_tab := _dock.tab()
	if _dock.on_selection(_strike_mode_open()):
		_dock_changed(true, was_tab)


## The formation panel on the right would sit under the dock: it closes when the dock opens.
func _close_right_info_panel() -> void:
	if _panel != null and _panel.visible and _panel.dock_side == StaffMapWindow.Dock.RIGHT:
		close_info()


## A click on a journal entry: the map centres on its place and rings the hex.
func _on_journal_entry(coord: Vector2i) -> void:
	if not _view.has_tile(coord):
		return
	_centre_on_hex(coord)
	_journal_ring.show_at(coord, _screen_of_hex(coord))


## A strike report asks for its line in the journal (Enter, a click on the card or the chip).
func _on_strike_log_requested(model: Dictionary) -> void:
	var found: OperationalJournal.Entry = null
	for entry in _simulation.state.journal.entries_for(viewer_player):
		if (
			entry.kind == &"strike"
			and entry.actor == model["striker"]
			and entry.turn == model["turn"]
		):
			if found == null or entry.coord == model["coord"]:
				found = entry
	open_journal(found)


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
		ACTION_COVER:
			toggle_air_defence_cover()
		ACTION_CONTROL:
			toggle_terrain_control()
		ACTION_NEXT:
			select_next_formation()
		ACTION_CANCEL:
			cancel_order()
		ACTION_REPORT:
			toggle_report()
		ACTION_DECISIONS:
			toggle_decisions()
		ACTION_JOURNAL:
			toggle_journal()
		ACTION_OBJECTIVES:
			toggle_objectives()


## Lights the toggle buttons to match the layers (whatever changed them: a key or a button).
func _sync_action_bar() -> void:
	if _bar == null or _politics == null or _places == null:
		return
	_options.set_active(ACTION_GRID, _view.grid_visible())
	_options.set_active(ACTION_NAMES, _places.is_enabled())
	_options.set_active(ACTION_BORDERS, _view.countries().is_visible_layer())
	_options.set_active(ACTION_POLITICS, _politics.tint_enabled())
	_options.set_active(ACTION_FLAT, _pitch_target <= 0.5)
	_options.set_active(ACTION_COVER, _cover_on)
	_options.set_active(ACTION_CONTROL, _control.is_enabled())
	_bar.set_active(ACTION_MAP_OPTIONS, _options.is_open())
	_bar.set_active(ACTION_STRIKE, _dock.is_tab_open(StaffMapRightDock.Tab.STRIKE))
	_bar.set_active(ACTION_DECISIONS, _dock.is_tab_open(StaffMapRightDock.Tab.POLITICS))
	_bar.set_active(ACTION_JOURNAL, _dock.is_tab_open(StaffMapRightDock.Tab.JOURNAL))
	_bar.set_active(ACTION_OBJECTIVES, _objectives != null and _objectives.is_open())
	_bar.set_enabled(ACTION_CANCEL, _selected_own() != null)


func toggle_grid() -> void:
	_view.set_grid_visible(not _view.grid_visible())
	_apply_front_view()


func toggle_terrain_control() -> void:
	_control.set_enabled(not _control.is_enabled())
	_sync_action_bar()


func toggle_borders() -> void:
	_view.countries().set_visible_layer(not _view.countries().is_visible_layer())


func toggle_place_names() -> void:
	_places.set_enabled(not _places.is_enabled())
	_layout_places()


## Key C / the "Air defence cover" row: the coverage zones of both sides (default off).
func toggle_air_defence_cover() -> void:
	_cover_on = not _cover_on
	_apply_cover()
	_sync_action_bar()


func air_defence_cover() -> StaffMapAirDefenceLayer:
	return _cover


## Shown when the player toggled it on, or while the strike mode is open with a weapon picked.
func _apply_cover() -> void:
	if _cover == null:
		return
	_cover.set_shown(_cover_on or (_strike != null and _strike.wants_cover()))


func _refresh_cover_zones() -> void:
	if _cover != null:
		_cover.set_zones(StaffMapAirDefence.zones(_simulation.state))


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
	if _menu_button == null:
		return  # not built yet; _ready calls it again
	_menu_button.tooltip_text = tr("MENU")
	if _bar != null:
		_bar.refresh_texts()
	_view.countries().refresh_names()
	_refresh_turn_bar()
	_refresh_selection_ui()


func _card_info(c: Vector2i) -> Dictionary:
	var data := StaffMapCard.info(_grid, c, _imported.country_at(c) if _imported != null else "")
	data["relation"] = CountryRules.relation(
		_simulation.state, viewer_player, _simulation.state.country_at(c)
	)
	data["control"] = TerrainControl.card_text(_simulation.state, c, viewer_player)
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
func terrain_control() -> StaffMapControlLayer:
	return _control


## The T+1 march reach contour of the armed formation (TASK-155).
func reach_contour() -> StaffMapReachLayer:
	return _reach


func front_line() -> StaffMapFrontLine:
	return _front


## The issued orders layer (TASK-092d).
func orders() -> StaffMapOrders:
	return _orders


## The order gesture state machine (TASK-153): armed = an own formation selected on its side's turn.
func order_gesture() -> StaffMapOrderGesture:
	return _gesture


## The route preview's marks layer (cursor label, target marks).
func route_marks() -> StaffMapRouteMarks:
	return _route_marks


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
	var cancelled := _execute(CancelOrderCommand.new(formation.id))
	if cancelled and _gesture.edited_from() != &"":
		_gesture.cancel()  # the aim, then the editing itself
		_gesture.cancel()
		select_formation(&"")
	return cancelled


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
		_orders.mark_fresh(order["formation_id"])
		_gesture.confirm()
		if _simulation.execute(command):
			select_formation(&"")
		else:
			_orders.mark_fresh(&"")
			_gesture.fail()
	else:
		_gesture.cancel()  # back to aiming
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


## Selects a formation (counter brackets, brief card); &"" deselects. The formation panel is not
## shown by a selection any more (TASK-151) but, while it is open, switches to the new selection.
## `refill` refreshes the selection UI even when the selection did not change (language switch,
## events); `ease_camera` false keeps the camera where it is (view restore).
func select_formation(formation_id: StringName, refill := false, ease_camera := true) -> void:
	if _counters == null:
		return
	var formation := _simulation.state.get_formation(formation_id)
	if formation == null:
		formation_id = &""
	if formation_id == _counters.selected() and not refill:
		return
	_order_ring.close()
	var new_selection := formation_id != _counters.selected()
	if new_selection:
		_clear_pick()
		if formation_id != &"":
			_close_dock_on_selection()
	if _border_prompt != null and _border_prompt.pending().get("formation_id") != formation_id:
		_border_prompt.take()
	_counters.set_selected(formation_id)
	_sync_posture_switcher()
	if formation == null:
		_route.set_formation(_simulation.state, &"")
		return
	var own := formation.owner_id == viewer_player
	_route.set_formation(_simulation.state, formation_id if own else &"")
	if new_selection or not _panel.visible:
		_fill_panel(formation)  # the panel follows the selection while it is open
		if new_selection and _panel.visible:
			_dock_panel_for(formation_id, false, ease_camera)
	else:
		_refresh_panel()
		_place_panel()


## Fills the formation panel (shown or not) from `formation`.
func _fill_panel(formation: Formation) -> void:
	_panel.fill_formation(_simulation.state, formation, viewer_player, _palette)
	var origin := CountryDefinition.find(origin_country(formation.id))
	_panel.show_origin(origin.display_name if origin != null else "")
	_show_order_ui(formation)


## Refills the panel with the formation it shows (events, language, viewer swap).
func _refresh_panel() -> void:
	if _panel == null or _panel.formation_id == &"":
		return
	var formation := _simulation.state.get_formation(_panel.formation_id)
	if formation == null:
		close_info()
		return
	_fill_panel(formation)


## Selection UI after a change of the state, the language or the viewer.
func _refresh_selection_ui() -> void:
	if _counters != null and selected_formation() != &"":
		select_formation(selected_formation(), true)
	else:
		_refresh_panel()


## Opens the full formation panel for `formation_id` (own or hostile; the selection is not
## changed): RMB on a hostile counter, ring slot INFO, key I. False for an unknown formation.
func open_info(formation_id: StringName) -> bool:
	var formation := _simulation.state.get_formation(formation_id)
	if formation == null or _panel == null:
		return false
	var appears := not _panel.visible
	_close_dock_on_selection()
	_fill_panel(formation)
	_panel.show()
	_dock_panel_for(formation_id, appears, true)
	return true


## Closes the full panel; true when it was open.
func close_info() -> bool:
	if _panel == null or not _panel.visible:
		return false
	if _panel_fade != null:
		_panel_fade.kill()
	_panel.hide()
	_panel.modulate.a = 1.0
	_sync_insets()
	return true


## Key I: closes the panel, else opens it for the selected formation (or the hovered counter).
func toggle_info() -> void:
	if close_info():
		return
	var id := selected_formation()
	if id == &"" and _counters != null:
		id = _counters.hovered()
	if id != &"":
		open_info(id)


## Keys 1-3 with an own formation armed: the next click on the map orders in that posture (the
## same key or Esc drops it); the brief card shrinks to the chip meanwhile.
func _pick_posture_key(number: int) -> void:
	var formation := _selected_own()
	if formation == null or not _can_order(formation.id):
		return
	_sync_gesture()
	_gesture.pick_posture(StaffMapRoute.posture_for_key(number))
	_route.set_posture(_gesture.posture())
	_aim_key = []
	_sync_posture_switcher()


## A click on a segment of the posture strip (TASK-158): a formation with an order gets a
## SetPostureCommand (the order is kept and re-planned); without one the posture is armed for the
## next target click, exactly as keys 1-3 do. False when nothing changed.
func pick_posture_segment(posture: StringName) -> bool:
	var formation := _selected_own()
	if formation == null or not _can_order(formation.id) or is_sliding() or _modal_open():
		return false
	_sync_gesture()
	var action := StaffMapPostureSwitcherModel.click_action(
		formation.order != null, formation.posture, _gesture.posture(), posture
	)
	match action:
		StaffMapPostureSwitcherModel.SET:
			return set_posture(posture)
		StaffMapPostureSwitcherModel.ARM, StaffMapPostureSwitcherModel.DISARM:
			_pick_posture_key(OperationalPosture.NAMES.find(posture) + 1)
			return true
	return false


func posture_switcher() -> StaffMapPostureSwitcher:
	return _posture_switcher


## Per frame (cheap, cached): posture badges at zoom level 1 and closer, and the strip under the
## selected own formation. Reads the state only.
func _sync_posture_switcher() -> void:
	if _counters == null or _posture_switcher == null or _simulation == null:
		return
	var zoomed := _view.zoom_level() >= 1
	_counters.set_posture_badges(zoomed)
	var formation := _selected_own()
	var counter := _counters.counter(formation.id) if formation != null else null
	if not zoomed or counter == null or not counter.visible:
		_posture_key = []
		_posture_switcher.clear()
		return
	var state := _simulation.state
	var has_order := formation.order != null
	var armed := _gesture.posture() if not has_order else &""
	var active := StaffMapPostureSwitcherModel.active_posture(formation.posture, armed)
	var dest_y := 0.0
	if has_order:
		dest_y = _screen_of_hex(formation.order.destination).y
	var flipped := StaffMapPostureSwitcherModel.flip_above(
		counter.position.y, has_order, dest_y, _viewport_size().y
	)
	var enabled := StaffMapPostureSwitcherModel.enabled(
		true,
		state.current_player == viewer_player,
		_modal_open(),
		is_sliding(),
		_strike_mode_open()
	)
	var key := [counter.position, active, flipped, enabled]
	if key == _posture_key and _posture_switcher.visible:
		return
	_posture_key = key
	_posture_switcher.present(counter.position, active, flipped, enabled)


func _clear_pick() -> void:
	if _gesture.posture() == &"":
		return
	_gesture.clear_posture()
	_aim_key = []
	if _route != null:
		_route.set_posture(&"")


## Esc: steps the order gesture back (a picked posture, then aiming, then the arming); true when
## it consumed the key. Disarming deselects, as the Esc fallback does for any selection.
func _cancel_gesture() -> bool:
	_sync_gesture()
	var before := _gesture.state()
	var had_posture := _gesture.posture() != &""
	var intent := _gesture.cancel()
	if had_posture:
		_route.set_posture(&"")
	_aim_key = []
	if intent["type"] == StaffMapOrderGesture.DISARM:
		select_formation(&"")
		return true
	return (
		before != StaffMapOrderGesture.State.IDLE and before != StaffMapOrderGesture.State.COMMITTED
	)


## Feeds the gesture what disables it and the selection (idempotent, cheap): strike mode, a modal,
## the counter slide and a turn that is not the viewer's turn drop it to IDLE.
func _sync_gesture() -> void:
	if _simulation == null or _counters == null:
		return
	_gesture.set_context(
		_strike_mode_open(),
		_modal_open(),
		is_sliding(),
		_simulation.state.current_player == viewer_player
	)
	var formation := _selected_own()
	if (
		_gesture.state() == StaffMapOrderGesture.State.CONFIRM
		and (_border_prompt == null or not _border_prompt.is_open())
	):
		_gesture.cancel()  # the prompt was dropped by something else
	_gesture.select(formation.id if formation != null else &"")


## The reach contour shows while a formation is armed or aimed (not at the prompt, committed or
## idle); it recomputes only when the formation or the map changed (TASK-155).
func _refresh_reach() -> void:
	if _reach == null or _simulation == null:
		return
	var gesture_state := _gesture.state()
	var shown := (
		gesture_state == StaffMapOrderGesture.State.ARMED
		or gesture_state == StaffMapOrderGesture.State.AIMING
		or gesture_state == StaffMapOrderGesture.State.EDITING
	)
	_reach.refresh(_simulation.state, _selected_own() if shown else null, shown)


## Per frame: gesture context, the flowing dashes (only while aiming) and the commit settle.
func _tick_gesture(delta: float) -> void:
	_sync_gesture()
	_gesture.tick(delta)
	_refresh_reach()
	if _route != null:
		_route.set_flowing(_gesture.is_aiming())
		_route.set_editing(_gesture.edited_from() != &"")
	if _orders.set_ghost(_gesture.edited_from()):
		_refresh_orders()
	if _gesture.state() == StaffMapOrderGesture.State.COMMITTED:
		_orders.settle(_gesture.settle())
	elif _orders.has_fresh():
		_orders.mark_fresh(&"")
		_refresh_orders()  # the settled line joins the other orders


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
	if _journal != null and _dock.is_tab_open(StaffMapRightDock.Tab.JOURNAL):
		_journal.show_journal(_simulation.state, player)
	if _politics != null:
		_politics.refresh(player)
	_counters.set_viewer(player)
	_counters.refresh()
	_counters.apply_marks(_marks)
	_refresh_orders()
	_show_new_report()
	_refresh_contacts()
	_refresh_selection_ui()


## Place-based name of a hex ("Suwałki, 5 km east"), shared by the report and the contacts.
func _place_name(c: Vector2i) -> String:
	return StaffMapPlaceName.describe(_imported, c)


func turn_bar() -> StaffMapTurnBar:
	return _turn_bar


func turn_banner() -> TurnBanner:
	return _banner


## Lets the AI play its side once per turn (TASK-102c), when it is to move, no battle waits, no
## slide is running and no battle result notice is open (the human clicks Continue first); the
## usual end-of-turn marks (report, slide, strike reports) follow from the events. It never plays
## or auto-resolves a battle (the notice asks the human only).
## True when the AI turn ran.
func play_ai_turn_if_due() -> bool:
	if _simulation == null or ai_side < 0 or is_sliding():
		return false
	if _result_notice != null and _result_notice.visible:
		return false  # the AI moves only after the human clicks Continue on the battle summary
	var state := _simulation.state
	if state.current_player != ai_side or not state.result.is_empty():
		return false
	if not state.pending_battles.is_empty():
		return false
	var key := state.turn * 2 + state.current_player
	if key == _ai_turn_key:
		return false
	_ai_turn_key = key
	ai_turn.call(_simulation, ai_side)
	return true


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
	if _panel != null and _panel.dock_side == StaffMapWindow.Dock.LEFT:
		_panel.dock_side = StaffMapWindow.Dock.RIGHT  # the left dock is taken: back to the right
		_place_panel()
	if owner != LeftWindow.OPTIONS and _options != null and _options.close():
		_sync_action_bar()
	if owner != LeftWindow.MENU:
		close_menu()
	if owner != LeftWindow.OBJECTIVES and _objectives != null and _objectives.close():
		_sync_action_bar()
	if owner in [LeftWindow.OPTIONS, LeftWindow.MENU, LeftWindow.OBJECTIVES] and _report != null:
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


## A ground point (hex units) on the screen, on the relief.
func _ground_to_screen(ground: Vector2) -> Vector2:
	return _project(_view.relief().surface_point(ground))


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
	if _palette.glow_enabled:
		# Bloom of the bright lines only (peak above the threshold); ground and 2D HUD stay as is.
		environment.glow_enabled = true
		environment.glow_hdr_threshold = _palette.glow_threshold
		environment.glow_hdr_scale = _palette.glow_feather
		environment.glow_intensity = _palette.glow_intensity
		environment.glow_strength = _palette.glow_strength
		environment.glow_bloom = 0.0
		environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		for level in [1, 2, 3, 4]:
			environment.set_glow_level(level, 1.0)
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
	_set_zoom(_default_zoom())
	_view.set_zoom_level(_view.zoom_level(), true)
	if is_inside_tree():
		get_viewport().size_changed.connect(_on_viewport_resized)


## The zoom a fresh map opens at: zoom level 1 (counters, orders, badges readable), a little above
## the threshold so the hysteresis does not drop it to level 0; never beyond the zoom limits.
func _default_zoom() -> float:
	var px_per_km := _palette.zoom_level_px_per_km.x * (1.0 + 2.0 * _palette.zoom_hysteresis)
	return clampf(px_per_km * _km_per_unit / StaffMapView.UNIT, _min_zoom, _max_zoom)


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
	var chosen_side := Session.take_chosen_side() if not _resumed else &""
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
			if state.player_sides.has(chosen_side):  # the side picked in the menu (TASK-149)
				viewer_player = state.player_sides.find(chosen_side)
	if not _resumed:
		# The human's side moves first; --hotseat and AI-less runs keep the data's order.
		var human := viewer_player if not OS.get_cmdline_user_args().has("--hotseat") else -1
		Operation.give_initiative(state, human)
	if state.player_sides.size() == 2 and not OS.get_cmdline_user_args().has("--hotseat"):
		ai_side = 1 - viewer_player
	_cover = StaffMapAirDefenceLayer.new()  # under the markers and counters
	_cover.setup(_palette, _ground_to_screen)
	_counter_layer.add_child(_cover)
	_cover.set_zones(StaffMapAirDefence.zones(state))
	_installations = StaffMapInstallations.new()  # under the counters
	_counter_layer.add_child(_installations)
	_installations.build(state, _palette)
	_support_ghosts = StaffMapSupportGhosts.new()  # under the counters
	_support_ghosts.set_colour(StaffMapFormations.side_colour(_palette, viewer_player))
	_counter_layer.add_child(_support_ghosts)
	_counters = StaffMapCounters.new()
	_counter_layer.add_child(_counters)
	_posture_switcher = StaffMapPostureSwitcher.new()  # over the counters
	_posture_switcher.setup(_palette)
	_posture_switcher.posture_picked.connect(pick_posture_segment)
	_counter_layer.add_child(_posture_switcher)
	_counters.set_depth(StaffMapCounter.depth_for_pitch(_pitch))
	_installations.set_depth(StaffMapCounter.depth_for_pitch(_pitch))
	_build_route_preview()  # after the counters: its cross and label draw over them
	_counters.build(state, _palette, viewer_player)
	_counters.refresh()  # the order marks, also when the state already holds orders
	_support_ghosts.show_ghosts(StaffMapSupportModel.ghosts(state, viewer_player))
	_orders.refresh(state, viewer_player)
	_front.refresh(state, viewer_player)
	_control.refresh(state, viewer_player)
	_apply_front_view()
	_update_anchors()
	if not _resumed and OS.get_cmdline_user_args().has("--pending-battle"):
		state.pending_battles.append(BattleSetup.new())


func _build_route_preview() -> void:
	_control = StaffMapControlLayer.new(_view.relief(), _palette)
	_view.add_child(_control)
	_reach = StaffMapReachLayer.new(_view.relief(), _palette)
	_view.add_child(_reach)
	_front = StaffMapFrontLine.new(_view.relief(), _palette)
	_view.add_child(_front)
	_order_ribbon = StaffMapRouteRibbon.new("OrderRibbon")
	_order_ribbon.set_glow(_orders_glow())
	_view.add_child(_order_ribbon)
	_fresh_ribbon = StaffMapRouteRibbon.new("FreshOrderRibbon")
	_fresh_ribbon.set_glow(_orders_glow())
	_view.add_child(_fresh_ribbon)
	var order_marks := StaffMapRouteMarks.new()
	order_marks.name = "OrderMarks"
	order_marks.set_projector(_project)
	_counter_layer.add_child(order_marks)
	_orders = StaffMapOrders.new(_order_ribbon, order_marks, _view.relief(), _palette)
	_orders.set_fresh_ribbon(_fresh_ribbon)
	_route_ribbon = StaffMapRouteRibbon.new()
	_route_ribbon.set_glow(_orders_glow())
	_view.add_child(_route_ribbon)
	var alt_ribbon := StaffMapRouteRibbon.new("AltRouteRibbon")
	_view.add_child(alt_ribbon)
	_route_marks = StaffMapRouteMarks.new()
	_route_marks.set_projector(_project)
	_counter_layer.add_child(_route_marks)
	if _posture_switcher != null:  # the strip stays above the order marks and labels
		_counter_layer.move_child(_posture_switcher, -1)
	_route = StaffMapRoutePreview.new(_route_ribbon, _route_marks, _view.relief(), _palette)
	_route.set_alt_ribbon(alt_ribbon)
	_update_line_scale()


## Screen pixels per map unit on the ground at the view centre: the shader cuts the dashes of the
## order lines in pixels from it, so their pitch does not change with the zoom.
func _update_line_scale() -> void:
	if _route == null:
		return
	var centre := _target()
	var px := _project(centre).distance_to(_project(centre + Vector3.RIGHT))
	_route.set_line_scale(px)
	_orders.set_line_scale(px)


func _orders_glow() -> float:
	return _palette.glow_orders if _palette.glow_enabled else 1.0


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
		_update_line_scale()
		if _order_ring != null:
			_order_ring.follow()
	if _contacts != null:
		_contacts.layout()
		_place_queue()
	if _strike != null:
		_strike.layout(_viewport_size(), _turn_bar.size.y + PANEL_MARGIN.y / 2.0)
	if _cover != null:
		_cover.layout()
	if _installations != null:
		var spots := {}
		for id: StringName in _installation_anchors:
			spots[id] = _project(_installation_anchors[id])
		_installations.layout(spots)
	if _support_ghosts != null:
		_support_ghosts.layout(_screen_of_hex)
	if _counters == null:
		return
	var points := {}
	for id: StringName in _anchors:
		points[id] = _project(_anchors[id])
	_counters.layout(points)
	_layout_places()
	_sync_posture_switcher()


func _on_command_rejected(command: OperationalCommand, reason: String) -> void:
	if command is StrikeCommand:  # the rejection code itself (TASK-097a)
		_toast_message(reason, _palette.ui_alert)
		return
	if command is PoliticalDecisionCommand:
		_toast_message(StaffMapSupportModel.reason_text(reason), _palette.ui_alert)
		return
	_toast_message(tr("ORDER_REJECTED_" + reason.to_upper()), _palette.ui_alert)


func _on_operational_event(event: Dictionary) -> void:
	_unsaved = true
	_journal_dirty = _journal_dirty or _dock.is_tab_open(StaffMapRightDock.Tab.JOURNAL)
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
	_on_support_event(event)
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
	_refresh_selection_ui()
	if event.get("type") == &"operational_turn_started":
		_begin_slide()
		_show_new_report()
		if int(event.get("player", -1)) == viewer_player:
			_decision_lines.clear()  # shown (or not wanted) – the log starts over
	elif event.get("type") == &"battle_consequences":
		_begin_slide()  # the retreating counter slides back (TASK-095)
	_refresh_contacts()


## Outside support (TASK-121): the ghost counters follow the packages on the way; requests,
## arrivals, waits and withdrawals show a toast (the casus belli one is toasted above).
func _on_support_event(event: Dictionary) -> void:
	if _support_ghosts == null:
		return
	var state := _simulation.state
	_support_ghosts.show_ghosts(StaffMapSupportModel.ghosts(state, viewer_player))
	var text := StaffMapSupportModel.toast_text(state, viewer_player, event)
	if text != "":
		_toast_message(text, _palette.ui_amber)


func support_ghosts() -> StaffMapSupportGhosts:
	return _support_ghosts


## Strike events (TASK-097a): the markers' bars, the result report and the debug panel's stock line.
func _on_strike_event(event: Dictionary) -> void:
	var type: StringName = event.get("type", &"")
	_strike.on_event(event)
	if type in [&"installation_changed", &"installation_suppressed"]:
		_refresh_cover_zones()
	if (
		type
		in [
			&"installation_changed",
			&"installation_suppressed",
			&"strike_stock_changed",
			&"strike_launched"
		]
	):
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
	if _contacts.is_active() and _report != null:
		_report.close()  # the contact notice has the screen; the report would lie under it
	elif not _contacts.is_active():
		_show_new_report()  # the report that waited for the contact notice to go
	_place_queue()
	_contacts.layout()


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
	_unsaved = false
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
## viewer and follow, the selection, the grid / terrain control / borders toggles and the joined
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
		"terrain_control": _control.is_enabled(),
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
	_control.set_enabled(settings.get("terrain_control", true))
	_view.countries().set_visible_layer(settings["borders"])
	_apply_front_view()
	select_formation(settings["selected"], false, false)


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


## Top of the left column: 130 px, or under the strike report card / chip while one shows.
func _left_column_top() -> float:
	var top := 130.0
	if _strike != null:
		var reports := _strike.reports()
		for node: Control in [reports.card(), reports.chip()]:
			if node.visible:
				top = maxf(top, node.position.y + node.size.y + 12.0)
	return top


## The turn report and the queue follow the strike report as it comes and goes (no overlap).
func _sync_left_column() -> void:
	var top := _left_column_top()
	if is_equal_approx(top, _left_column_y):
		return
	_left_column_y = top
	if _report != null and _report.visible:
		_place_report()
	if _contacts != null:
		_place_queue()


## The queue sits at the left edge, under the turn report when that is open.
func _place_queue() -> void:
	var queue := _contacts.queue
	if not queue.visible:
		return
	queue.reset_size()
	var top := _left_column_top()
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
	_control.refresh(_simulation.state, viewer_player, not is_sliding())
	_apply_front_view()


## The front line follows the camera scale, the zoom level and the grid (exact hex edges at Z2).
func _apply_front_view() -> void:
	var exact := _view.grid_visible() and _view.zoom_level() == 2
	_front.set_view(_scale(), _view.zoom_level(), exact)
	_control.set_view(_view.zoom_level())


## Opens the report panel with the viewed side's last report.
func _show_report() -> void:
	if _contacts != null and _contacts.is_active():
		return
	if _objectives != null:
		_objectives.close()
	_report.show_report(_simulation.state, _marks.report_of(viewer_player), _decision_lines)
	_report.show()
	_place_report()


func _place_report() -> void:
	_report.reset_size()
	var top := _left_column_top()
	var report_floor := _viewport_size().y - float(ActionBar.HEIGHT) - PANEL_MARGIN.y
	_report.position = Vector2(
		PANEL_MARGIN.x, clampf(top, 8.0, maxf(report_floor - _report.size.y, 8.0))
	)


## Opens the report of the viewed side's last move once, when it is new (not during the slide).
func _show_new_report() -> void:
	if _contacts != null and _contacts.is_active():
		return  # stays unseen; _refresh_contacts shows it once the notice is gone
	if _report != null and not is_sliding() and _marks.take_unseen(viewer_player):
		_show_report()


func _on_report_entry(formation_id: StringName, _coord: Vector2i) -> void:
	select_formation(formation_id)
	_centre_on(formation_id)


## The move changed hands: the banner names the bloc.
func _on_turn_started(event: Dictionary) -> void:
	var player: int = event["player"]
	if player != viewer_player and player != ai_side:
		set_viewer(player)  # hot-seat: the human orders whichever bloc is to move
	var state := _simulation.state
	var colour := StaffMapFormations.side_colour(_palette, player)
	_banner.show_timed(
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


## True while a full-screen window (the exit prompt) idles the map.
func _modal_open() -> bool:
	return _exit_confirm != null and _exit_confirm.visible


## The ladder window opens: every other staff-map window closes.
func _close_other_windows() -> void:
	close_menu()
	_options.close()
	close_dock()
	_objectives.close()
	if _strike != null:
		_strike.reports().suspend()
		_strike.close()
	_politics.close_card()
	_close_debug_panels()


## Key H / the Decisions button: the POLITICS tab of the right dock (the key of the open tab
## closes it).
func toggle_decisions() -> void:
	if _decisions == null:
		return
	if _dock.is_tab_open(StaffMapRightDock.Tab.POLITICS):
		close_dock()
	else:
		open_decisions()


## The level chip under the turn bar: the LADDER sub-tab of POLITICS (a second click closes).
func toggle_ladder() -> void:
	if _decisions == null:
		return
	var panel := _decisions.panel()
	if (
		_dock.is_tab_open(StaffMapRightDock.Tab.POLITICS)
		and panel.tab() == StaffMapDecisionsPanel.TAB_LADDER
	):
		close_dock()
		return
	if not _dock.is_tab_open(StaffMapRightDock.Tab.POLITICS):
		open_decisions()
	panel.open_tab(StaffMapDecisionsPanel.TAB_LADDER)


## Opens the POLITICS tab (leaves the strike mode, closes a right-docked formation panel).
func open_decisions() -> void:
	var was_open := _dock.is_open()
	var was_tab := _dock.tab()
	_dock.open(StaffMapRightDock.Tab.POLITICS)
	if _strike != null and _strike.is_open():
		_strike.close()  # its open_changed(false) finds the tab already switched
	_close_right_info_panel()
	_decisions.open()
	_dock_changed(was_open, was_tab)


## The tab's own X / Esc / H: closes the dock when POLITICS is the open tab.
func _close_politics_tab() -> void:
	if _dock.is_tab_open(StaffMapRightDock.Tab.POLITICS):
		close_dock()


func decisions_hud() -> StaffMapDecisionsHud:
	return _decisions


## Key S / the Strike button: opens or closes the strike mode (TASK-097b); closes the other cards.
func toggle_strike_mode() -> void:
	if _strike == null:
		return
	if not _strike.is_open():
		select_formation(&"")
	_strike.toggle()
	_sync_action_bar()


func strike_hud() -> StaffMapStrikeHud:
	return _strike


func _on_strike_open_changed(open: bool) -> void:
	var was_open := _dock.is_open()
	var was_tab := _dock.tab()
	if open and not _dock.is_tab_open(StaffMapRightDock.Tab.STRIKE):
		_dock.open(StaffMapRightDock.Tab.STRIKE)  # opening the mode (key S) leaves the journal
		_close_right_info_panel()
		_dock_changed(was_open, was_tab)
	elif not open and _dock.is_tab_open(StaffMapRightDock.Tab.STRIKE):
		_dock.close()  # leaving the mode (S, X, Esc, a made strike) closes the tab
		_dock_changed(true, was_tab)
	_sync_action_bar()
	if not open:
		_installation_card.set_note("")
	_layout_counters()


func escalation_hud() -> StaffMapEscalationHud:
	return _escalation


## Screen rect of the visible formation panel (the order card keeps clear of it), empty if hidden.
func _panel_rect() -> Rect2:
	if _panel == null or not _panel.visible:
		return Rect2()
	return _panel.get_global_rect()


func _place_panel() -> void:
	if _panel == null:
		return
	_panel.dock(_viewport_size().x)  # under the turn bar row


## Docks the panel of a newly selected formation opposite its counter (left dock only when it is
## free), fading it in (120 ms) when it appears or changes side; then eases the counter into the
## clear zone when the panel or a bar covers it.
func _dock_panel_for(formation_id: StringName, appears: bool, ease_camera: bool) -> void:
	var counter := (
		counter_screen_position(formation_id) if _anchors.has(formation_id) else Vector2()
	)
	var left := StaffMapCameraMath.panel_on_left(
		counter.x, _viewport_size().x, not _left_dock_busy()
	)
	left = left or _dock.is_open()  # the right dock (strike mode keeps it) is never covered
	var side := StaffMapWindow.Dock.LEFT if left else StaffMapWindow.Dock.RIGHT
	var changed := side != _panel.dock_side
	_panel.dock_side = side
	_place_panel()
	if _panel_fade != null:
		_panel_fade.kill()
	_panel.modulate.a = 1.0
	if (changed or appears) and is_inside_tree():
		_panel.modulate.a = 0.0
		_panel_fade = create_tween()
		_panel_fade.tween_property(_panel, "modulate:a", 1.0, PANEL_FADE)
	_sync_insets()
	if ease_camera:
		_ease_into_clear_zone(counter)


## A window other than the formation panel holds the left dock.
func _left_dock_busy() -> bool:
	for window in _docked_windows():
		if window != _panel and window.dock_side == StaffMapWindow.Dock.LEFT:
			return true
	return false


## Visible docked windows (not the centred confirm dialogs and the centred menu).
func _docked_windows() -> Array[StaffMapWindow]:
	var result: Array[StaffMapWindow] = []
	if _hud == null:
		return result
	for node in _hud.find_children("*", "StaffMapWindow", true, false):
		var window := node as StaffMapWindow
		if (
			window.visible
			and window.dock_side != StaffMapWindow.Dock.TABBED
			and not window is StaffMapExitConfirm
			and not window is StaffMapStrikeConfirm
			and not window is StaffMapMenuWindow
		):
			result.append(window)
	return result


## Screen px the HUD covers: turn bar + chip, the bottom bar and the open docked windows.
func _clear_insets() -> Vector4:
	var size := _viewport_size()
	var left := 0.0
	var right := 0.0
	for window in _docked_windows():
		var rect := window.get_global_rect()
		if window.dock_side == StaffMapWindow.Dock.LEFT:
			left = maxf(left, rect.end.x)
		else:
			right = maxf(right, size.x - rect.position.x)
	right = maxf(right, _dock_inset)  # the tabbed dock: its animated width, not its panels' rects
	return Vector4(StaffMapCameraMath.TOP_INSET, float(ActionBar.HEIGHT), left, right)


## Screen rect no bar or window covers.
func _clear_rect() -> Rect2:
	return StaffMapCameraMath.clear_rect(_viewport_size(), _insets)


## Re-clamps the camera when a window opened / closed.
func _sync_insets() -> void:
	var insets := _clear_insets()
	if insets != _insets:
		_insets = insets
		_move_camera(_position)


## Eases the camera so `counter` (screen px) lands inside the clear zone (280 ms ease-out).
func _ease_into_clear_zone(counter: Vector2) -> void:
	var shift := StaffMapCameraMath.ease_shift(
		counter, _clear_rect(), StaffMapCameraMath.EASE_MARGIN
	)
	if shift == Vector2.ZERO:
		return
	var from := _position
	var to := _position + StaffMapCameraMath.drag_delta(shift, _zoom, _pitch)
	if _ease != null:
		_ease.kill()
	if not is_inside_tree():
		_move_camera(to)
		return
	_ease = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ease.tween_method(
		func(t: float) -> void: _move_camera(from.lerp(to, t)),
		0.0,
		1.0,
		StaffMapCameraMath.EASE_SECONDS
	)


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
	_card.place_namer = _place_name
	_hud.add_child(_card)
	_installation_card = StaffMapInstallationCard.new()
	_hud.add_child(_installation_card)
	_unit_strip = StaffMapUnitStrip.new()
	_hud.add_child(_unit_strip)
	_panel = StaffMapFormationPanel.new()
	_panel.place_namer = _place_name
	_panel.close_requested.connect(func() -> void: close_info())
	_hud.add_child(_panel)
	_turn_bar = StaffMapTurnBar.new()
	_turn_bar.end_turn_pressed.connect(end_turn)
	_turn_bar.escalation_pressed.connect(toggle_ladder)
	_hud.add_child(_turn_bar)
	_report = StaffMapTurnReport.new()
	_report.entry_chosen.connect(_on_report_entry)
	_report.place_namer = _place_name
	_hud.add_child(_report)
	_banner = TurnBanner.new()
	_hud.add_child(_banner)
	_order_ring = StaffMapOrderRing.new(
		_hud, _execute, _screen_of_hex, _viewport_size, _ring_valid, _panel_rect, _clear_rect
	)
	_order_ring.ordered.connect(_on_ring_ordered)
	_order_ring.info_requested.connect(func(id: StringName) -> void: open_info(id))
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
	_contacts.place_namer = _place_name
	_contacts.play_requested.connect(play_battle)
	_contacts.auto_requested.connect(auto_resolve)
	_result_notice = StaffMapBattleResult.new()
	_result_notice.place_namer = _place_name
	_hud.add_child(_result_notice)
	_menu_button = StaffMapMenuButton.new()
	_menu_button.pressed.connect(toggle_menu)
	_hud.add_child(_menu_button)
	_build_menu_windows()
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
	_escalation = StaffMapEscalationHud.new(
		_simulation, _palette, _hud, _toast_message, func() -> int: return viewer_player
	)
	_escalation.menu_requested.connect(_return_to_menu)
	_decisions = StaffMapDecisionsHud.new(
		_simulation, _palette, func() -> int: return viewer_player
	)
	_decisions.close_requested.connect(_close_politics_tab)
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
	_strike.cover_wanted_changed.connect(func(_wanted: bool) -> void: _apply_cover())
	_strike.reports().shown.connect(func() -> void: _claim_left_dock(LeftWindow.REPORT))
	_strike.reports().log_requested.connect(_on_strike_log_requested)
	_build_right_dock()
	if OS.get_cmdline_user_args().has("--debug"):
		contact_debug()


## The right tabbed dock (TASK-174a): the strike panel and the journal move into it.
func _build_right_dock() -> void:
	_dock_view = StaffMapRightDockView.new()
	_hud.add_child(_dock_view)
	_dock_view.add_section(StaffMapRightDock.Tab.STRIKE, tr("STRIKE"), _strike.panel())
	_dock_view.add_section(StaffMapRightDock.Tab.POLITICS, tr("POLITICS"), _decisions.panel())
	_dock_view.add_section(StaffMapRightDock.Tab.JOURNAL, tr("JOURNAL"), _journal)
	_journal.max_list_height = maxf(
		_viewport_size().y - 92.0 - float(ActionBar.HEIGHT) - 130.0, 200.0
	)
	_dock_view.tab_pressed.connect(_on_dock_tab_pressed)
	_dock_view.layout(_viewport_size())


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
	var ground := _ground_viewport()  # the map never gets narrower than beside the open dock
	ground.x = StaffMapRightDock.min_map_width(ground.x)
	_min_zoom = StaffMapCameraMath.min_zoom(_bounds, ground)
	_max_zoom = StaffMapCameraMath.max_zoom(_viewport_size(), StaffMapView.UNIT, _min_zoom)


func _on_viewport_resized() -> void:
	if _menu != null and _menu.is_open():
		_menu.open_centered(_viewport_size())
	if _exit_confirm != null and _exit_confirm.visible:
		_exit_confirm.present(_unsaved, _viewport_size())
	_update_limits()
	_set_zoom(_zoom)
	_place_panel()
	if _dock_view != null:
		_dock_view.layout(_viewport_size())
	if _turn_bar != null:
		_place_turn_bar()


func _set_zoom(zoom_value: float) -> void:
	_zoom = clampf(zoom_value, _min_zoom, _max_zoom)
	_move_camera(_position)


func _move_camera(position: Vector2) -> void:
	_position = StaffMapCameraMath.clamp_position(
		position,
		_zoom,
		_bounds,
		_ground_viewport(),
		StaffMapCameraMath.ground_insets(_insets, _pitch),
		_dock_inset
	)
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
	if _strike != null:  # launcher labels at Z1 / Z2 like the counter labels (TASK-147)
		_strike.layer().set_labels(_view.zoom_level() >= 1)
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
	var depth := StaffMapCounter.depth_for_pitch(_pitch)
	if _counters != null:
		_counters.set_depth(depth)
	if _installations != null:
		_installations.set_depth(depth)
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
			if event.pressed:
				close_docked_windows()
			_dragging = event.pressed
			if event.button_index != MOUSE_BUTTON_LEFT:
				return
			if event.pressed and is_sliding():
				skip_slide()  # a click only skips the slide
				_dragging = false
				return
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


## A click on the map closes every docked window (left dock and the strike report card; the
## formation panel follows the selection, which `click_at` clears on an empty hex).
func close_docked_windows() -> void:
	var closed := close_menu()
	closed = _options.close() or closed
	closed = _objectives.close() or closed
	closed = _politics.close_card() or closed
	if _report != null and _report.visible:
		_report.close()
	if _strike != null and _strike.reports().card_visible():
		_strike.reports().collapse()
	if closed:
		_sync_action_bar()


func _strike_mode_open() -> bool:
	return _strike != null and _strike.is_open()


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


## A left click on the map: with the order ring open it only closes it; otherwise it drives the
## order gesture (TASK-153, StaffMapOrderGesture): a click on the armed own counter disarms it,
## with an own formation armed a click on a hex gives it a MARCH order there (and deselects it), a
## click on an enemy counter or hex an ATTACK order (or the picked posture); elsewhere it selects
## the counter under `screen` or deselects.
func click_at(screen: Vector2) -> void:
	if _counters == null:
		return
	if _order_ring.is_open():
		_order_ring.close()
		return
	if _mode_click(screen):
		return
	_sync_gesture()
	var hit := _pick_counter(screen)
	var target := _enemy_of_selected(hit)
	if _disarm_by_click(hit):
		return
	if target == null and hit == &"" and _grab_head(screen):
		return
	if target != null:
		_gesture_click_hex(target.coord)
	elif hit == &"":
		_click_bare_map(screen)
	else:
		select_formation(hit)
		_sync_gesture()


## A click on the head of an own issued order starts re-aiming it (TASK-157): that formation is
## selected and the gesture edits; the old order stays until a replacement is issued. True then.
func _grab_head(screen: Vector2) -> bool:
	if _gesture.is_blocked() or _orders == null:
		return false
	var id := StaffMapOrders.head_at(screen, _orders.heads_on_screen())
	if id == &"" or id == _gesture.edited_from():
		return false
	var formation := _simulation.state.get_formation(id)
	if (
		formation == null
		or formation.order == null
		or formation.owner_id != viewer_player
		or formation.owner_id != _simulation.state.current_player
	):
		return false
	select_formation(id)
	_gesture.click_head(id)
	_aim_key = []
	_sync_gesture()
	return true


## A click on the armed own counter disarms it; true then.
func _disarm_by_click(hit: StringName) -> bool:
	if hit == &"" or hit != selected_formation() or _selected_own() == null:
		return false
	if _gesture.click_own_counter(hit)["type"] != StaffMapOrderGesture.DISARM:
		return false
	select_formation(&"")
	return true


## A click on no counter: with an own formation armed it is the order on that hex; else it closes
## the panels and the country card or opens one, and deselects.
func _click_bare_map(screen: Vector2) -> void:
	close_info()  # a click on the bare map closes the full panel
	# With an own formation selected the click is an order, not a look at a country name.
	var named := _politics.country_name_at(ground_at_screen(screen))
	if named != &"" and _selected_own() == null:
		open_country_card(named)
		return
	_politics.close_card()
	var hex := hex_at_screen(screen)
	if _selected_own() != null and _view.has_tile(hex):
		_gesture_click_hex(hex)
		return
	select_formation(&"")
	_sync_gesture()


## The click on `hex` with an own formation armed: the gesture decides (issue, ask the border
## prompt first, or refuse); the command is the existing IssueOrderCommand (rule 2).
func _gesture_click_hex(hex: Vector2i) -> void:
	var formation := _selected_own()
	if formation == null:
		return
	if _gesture.is_blocked():  # not the viewer's turn: the command's rejection says why
		if issue_order(hex):
			select_formation(&"")
		return
	var posture := _gesture.posture()
	if posture == &"":
		posture = StaffMapOrderRingModel.default_posture(_simulation.state, formation, hex)
	var preview := StaffMapRoute.preview_in_posture(
		_simulation.state, formation, hex, posture, _movement
	)
	var verdict := StaffMapRoutePreview.verdict_of(_simulation.state, formation, preview)
	var intent := _gesture.click_hex(hex, verdict, _effective_orders_left(formation))
	match intent["type"]:
		StaffMapOrderGesture.ISSUE:
			_orders.mark_fresh(formation.id)
			if issue_order(hex, posture):
				select_formation(&"")  # done with this one; the next click must not re-order it
			else:
				_orders.mark_fresh(&"")
				_gesture.fail()
		StaffMapOrderGesture.CONFIRM_NEEDED:
			issue_order(hex, posture)  # the border prompt opens; Enter / Esc answer it
		StaffMapOrderGesture.REJECT:
			_aim_key = []  # the label already says why; no command is sent


## A right click on the map. On a counter (TASK-151): an own one is selected and gets the ring with
## slot INFO only; a hostile one, with an own formation selected, gets the order ring on its hex
## (ATTACK ..., INFO = the hostile's panel), else it opens the full panel directly. Elsewhere, with
## an own formation selected (and its side to play), it opens the order ring on the hex under
## `screen`; otherwise it only closes an open ring. Returns true when the ring is open afterwards.
func right_click_at(screen: Vector2) -> bool:
	if _counters == null:
		return false
	var was_open := _order_ring.is_open()
	_order_ring.close()
	var hit := _pick_counter(screen)
	if hit != &"":
		var enemy := _enemy_of_selected(hit)
		if enemy == null or not _can_order(_selected_own().id):
			return _right_click_counter(hit)
		# An own formation is selected: the ring over the enemy counter (ATTACK ...), INFO = its.
		var attacker := _selected_own()
		_order_ring.open(
			_simulation.state,
			attacker,
			enemy.coord,
			StaffMapFormations.side_colour(_palette, viewer_player),
			false,
			enemy.id
		)
		return _order_ring.is_open()
	var formation := _selected_own()
	if formation == null or not _can_order(formation.id):
		return false
	var hex := hex_at_screen(screen)
	if not _view.has_tile(hex):
		return false
	open_order_ring(hex)
	return was_open or _order_ring.is_open()


## Opens the order ring of the selected own formation on `hex`; false when it may not be ordered.
func open_order_ring(hex: Vector2i) -> bool:
	var formation := _selected_own()
	if formation == null or not _can_order(formation.id) or not _view.has_tile(hex):
		return false
	_order_ring.open(
		_simulation.state, formation, hex, StaffMapFormations.side_colour(_palette, viewer_player)
	)
	return _order_ring.is_open()


func _right_click_counter(formation_id: StringName) -> bool:
	var formation := _simulation.state.get_formation(formation_id)
	if formation == null:
		return false
	if formation.owner_id != viewer_player:
		open_info(formation_id)
		return false
	select_formation(formation_id)
	_order_ring.open(
		_simulation.state,
		formation,
		formation.coord,
		StaffMapFormations.side_colour(_palette, viewer_player),
		true
	)
	return _order_ring.is_open()


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


## The ring may stay open: a hex ring while its formation may be ordered, a counter ring (INFO)
## while its own formation is selected.
func _ring_valid(formation_id: StringName) -> bool:
	if _order_ring.is_on_counter():
		var formation := _simulation.state.get_formation(formation_id)
		return (
			formation != null
			and formation.owner_id == viewer_player
			and formation_id == selected_formation()
		)
	return _can_order(formation_id)


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
	if _covered_by_hud(mouse):
		_clear_hover()  # the panel or the posture strip covers the map: no aim line through it
		return
	if _strike != null and _strike.is_open():
		_strike.set_hover(&"" if _strike.covers(mouse) else _strike_target_at(mouse))
	if _counters != null:
		_counters.set_hovered(_pick_counter(mouse))
	var c := hex_at_screen(mouse)
	if not _view.has_tile(c):
		_clear_hover()
		return
	if _hover_installation(mouse):
		_route.set_hex(StaffMapRoutePreview.OFF)
		_view.highlight(StaffMapView.NO_HEX)
		return
	_installation_card.hide()
	_aim_hex(c)
	_route.set_hex(
		StaffMapRoutePreview.OFF if _gesture.state() == StaffMapOrderGesture.State.ARMED else c
	)
	if _counters != null and _counters.hovered() != &"":
		_view.highlight(c)  # the counter wins the slot (_sync_unit_strip)
		_card.hide()
	elif c != _view.hovered() or not _card.visible:
		_view.highlight(c)
		_card.show_info(_card_info(c))
	_last_mouse = mouse


## True while the cursor is over a HUD control that takes the mouse (bars, windows, the posture
## strip, panels): clicks do not reach the map there, so the order line must not aim through it.
func _covered_by_hud(mouse: Vector2) -> bool:
	if get_viewport().gui_get_hovered_control() != null:
		return true
	for control: Control in [_panel, _posture_switcher]:
		if control != null and control.visible and control.get_global_rect().has_point(mouse):
			return true
	return false


## The cursor is over `hex`: the armed gesture aims there. The verdict is the cheap reachability
## check, cached until the hex, posture, formation or orders left change.
func _aim_hex(hex: Vector2i) -> void:
	var formation := _selected_own()
	if formation == null or _simulation == null:
		return
	_sync_gesture()
	var state := _simulation.state
	var posture := _gesture.posture()
	if posture == &"":
		posture = StaffMapOrderRingModel.default_posture(state, formation, hex)
	var left := _effective_orders_left(formation)
	var key := [hex, posture, formation.id, left]
	if key != _aim_key:
		_aim_key = key
		_aim_verdict = StaffMapRoutePreview.quick_verdict(state, formation, hex, posture)
	_gesture.hover(hex, _aim_verdict, left)


## The orders the aim may count on: an order given this turn is re-aimed for free (TASK-154), so
## at least 1 even when none are left.
func _effective_orders_left(formation: Formation) -> int:
	var left := _simulation.state.orders_left()
	return maxi(left, 1) if _simulation.state.ordered_this_turn.has(formation.id) else left


## While the order ring is open the route preview shows its hex in the hovered posture.
func _hover_ring() -> void:
	_card.hide()
	if _counters != null:
		_counters.set_hovered(&"")
	if _order_ring.is_on_counter():  # the INFO ring has no target hex
		_route.set_hex(StaffMapRoutePreview.OFF)
		_view.highlight(StaffMapView.NO_HEX)
		return
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


## The counter under `screen`, unless the installation marker there is raised above it.
## A marker the cursor reaches where no counter covers it comes to the front alone (z_index), and
## goes back when the cursor reaches a counter outside it, so overlapping tiles can be clicked.
func _pick_counter(screen: Vector2) -> StringName:
	var counter := _counters.counter_at(screen)
	var marker := _installations.marker_at(screen)
	if marker != &"" and counter == &"":
		_raise_marker(marker)
	elif counter != &"" and marker == &"":
		_raise_marker(&"")
	if marker != &"" and marker == _raised_marker:
		return &""
	return counter


func _raise_marker(id: StringName) -> void:
	if id == _raised_marker:
		return
	if _installations.marker(_raised_marker) != null:
		_installations.marker(_raised_marker).z_index = 0
	_raised_marker = id
	if _installations.marker(id) != null:
		_installations.marker(id).z_index = 1


## Shows the installation card when the cursor is on a marker (and no counter); true then.
func _hover_installation(mouse: Vector2) -> bool:
	var id := &""
	if _counters == null or _pick_counter(mouse) == &"":
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
	_gesture.hover(StaffMapOrderGesture.NO_HEX, {}, 0)
	_view.highlight(StaffMapView.NO_HEX)
	if _counters != null:
		_counters.set_hovered(&"")
	_card.hide()


## Puts the card next to `screen`, kept inside the window.
func _place_card(screen: Vector2, card: Control = null) -> void:
	if card == null:
		card = _card
	var size := _viewport_size()
	var floor_y := size.y - float(ActionBar.HEIGHT)  # the bottom bar is a margin of the screen
	var at := screen + CARD_OFFSET
	if at.x + card.size.x > size.x:
		at.x = screen.x - CARD_OFFSET.x - card.size.x
	if at.y + card.size.y > floor_y:
		at.y = screen.y - CARD_OFFSET.y - card.size.y
	at.y = clampf(at.y, 0.0, maxf(floor_y - card.size.y, 0.0))
	card.position = at


## The operation menu behind the hamburger: Save and Exit operation.
func _build_menu_windows() -> void:
	_menu = StaffMapMenuWindow.new()
	_menu.save_pressed.connect(_on_menu_save)
	_menu.exit_pressed.connect(request_exit)
	_menu.close_requested.connect(func() -> void: close_menu())
	_hud.add_child(_menu)
	_exit_confirm = StaffMapExitConfirm.new()
	_exit_confirm.save_and_exit.connect(_on_save_and_exit)
	_exit_confirm.exit_confirmed.connect(_return_to_menu)
	_exit_confirm.cancelled.connect(func() -> void: cancel_exit())
	_hud.add_child(_exit_confirm)


func menu_window() -> StaffMapMenuWindow:
	return _menu


func menu_button() -> StaffMapMenuButton:
	return _menu_button


func exit_confirm() -> StaffMapExitConfirm:
	return _exit_confirm


## True while the operation has changed since the last save.
func has_unsaved_changes() -> bool:
	return _unsaved


## The hamburger / Esc with nothing to close: opens or closes the operation menu.
func toggle_menu() -> void:
	if _menu.is_open():
		close_menu()
		return
	if _exit_confirm.visible:
		return
	_claim_left_dock(LeftWindow.MENU)
	_menu.open_centered(_viewport_size())
	_menu_button.set_lit(true)


## Closes the menu; true when it was open.
func close_menu() -> bool:
	if _menu == null:
		return false
	var was_open := _menu.close()
	_menu_button.set_lit(false)
	return was_open


func _on_menu_save() -> void:
	save_campaign()
	close_menu()


## Exit operation: asks first; offers a save when the operation changed since the last one.
func request_exit() -> void:
	close_menu()
	_exit_confirm.present(_unsaved, _viewport_size())


## Dismisses the exit question; true when it was open.
func cancel_exit() -> bool:
	return _exit_confirm != null and _exit_confirm.close()


func _on_save_and_exit() -> void:
	if save_campaign():
		_return_to_menu()  # a failed save keeps the question open: the toast says why


func _return_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## True while a posture or target is being picked (ring open, or key 1-3 pressed).
func is_picking() -> bool:
	return _order_ring.is_open() or _gesture.posture() != &""


## Per frame: the left slot shows the formation under the cursor, else (when the cursor is on no
## hex and no installation) the selected own one; the hex strip takes the slot otherwise.
func _sync_unit_strip(modal: bool) -> void:
	if _unit_strip == null or _counters == null:
		return
	var id := unit_strip_target(modal)
	var formation := _simulation.state.get_formation(id) if id != &"" else null
	if formation == null:
		_unit_strip.hide()
		return
	_card.hide()
	var armed := ""
	if _gesture.posture() != &"" and id == selected_formation():
		armed = tr("POSTURE_" + String(_gesture.posture()).to_upper()).to_upper()
	_unit_strip.show_unit(
		StaffMapUnitCardModel.build(formation, viewer_player, _place_name), _palette, armed
	)


## The formation the left slot shows: the hovered counter (not under the panel, not while a window
## idles the map or the map is dragged), else the selected own formation when neither a hex nor
## an installation is hovered. &"" = none.
func unit_strip_target(modal := false) -> StringName:
	if modal or is_sliding() or (_dragging and _drag_travel > CLICK_SLOP):
		return &""
	var viewport := get_viewport()
	var mouse := viewport.get_mouse_position() if viewport != null else Vector2(-1, -1)
	var over_panel := _panel.visible and _panel.get_global_rect().has_point(mouse)
	var hovered := _counters.hovered()
	if hovered != &"" and not over_panel:
		return hovered
	if _card.visible or _installation_card.visible:
		return &""
	var selected := _selected_own()
	return selected.id if selected != null else &""


func unit_strip() -> StaffMapUnitStrip:
	return _unit_strip


## Screenshot hook: shows `id` (or the selection when empty) in the strip as if hovered.
func debug_unit_strip(id: StringName = &"") -> void:
	var formation := _simulation.state.get_formation(id if id != &"" else selected_formation())
	if formation == null:
		return
	_card.hide()
	_unit_strip.show_unit(
		StaffMapUnitCardModel.build(formation, viewer_player, _place_name), _palette
	)


## Screenshot / test hook: key 1-3 pick-a-target mode of the selected own formation.
func pick_posture_number(number: int) -> void:
	_pick_posture_key(number)
