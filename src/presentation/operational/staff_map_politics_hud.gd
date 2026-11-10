class_name StaffMapPoliticsHud
extends RefCounted
## Everything political on the staff map (TASK-114) behind a few calls, so StaffMap stays small:
## the tint (StaffMapPolitics), the country card, and with --debug the F9 politics panel. The
## view side only reads the state; the debug panel changes stances through CountryRules.set_stance
## (the one place they change) and re-emits the rule's event on the simulation.

var _politics: StaffMapPolitics
var _card: StaffMapCountryCard
var _panel: StaffMapPoliticsPanel
var _view: StaffMapView
var _simulation: OperationalSimulation
var _palette: StaffMapPalette
var _toast: Callable  # (message: String, colour: Color)
var _viewer := 0


## `debug` adds the F9 panel. Everything is optional: a map without countries or graphic layers
## has no tint, but the card and panel still work.
func _init(
	view: StaffMapView,
	imported: ImportedMap,
	palette: StaffMapPalette,
	simulation: OperationalSimulation,
	hud: CanvasLayer,
	toast: Callable,
	debug: bool
) -> void:
	_view = view
	_simulation = simulation
	_palette = palette
	_toast = toast
	_politics = StaffMapPolitics.create(view.terrain(), imported, palette)
	_card = StaffMapCountryCard.new()
	_card.position = Vector2(16, 130)
	hud.add_child(_card)
	if debug:
		_panel = StaffMapPoliticsPanel.new()
		_panel.position = Vector2(16, 130)
		_panel.stance_requested.connect(_on_stance_requested)
		_panel.escalation_requested.connect(_on_escalation_requested)
		_panel.strike_requested.connect(_on_strike_requested)
		_panel.stock_requested.connect(_on_stock_requested)
		hud.add_child(_panel)


func card() -> StaffMapCountryCard:
	return _card


func panel() -> StaffMapPoliticsPanel:
	return _panel


func politics() -> StaffMapPolitics:
	return _politics


## Recomputes the tint (and an open card) for `viewer`: on a stance change and a viewer change.
func refresh(viewer: int) -> void:
	_viewer = viewer
	var state := _simulation.state
	if _politics != null:
		_politics.apply(state, viewer)
	if _card.visible:
		_card.show_info(StaffMapCountryCard.info(state, viewer, _card.country_id()), _palette)
	if _panel != null and _panel.visible:
		_panel.show_state(state)


func tint_enabled() -> bool:
	return _politics != null and _politics.enabled()


func toggle_tint() -> void:
	if _politics != null:
		_politics.set_enabled(not _politics.enabled())


func open_card(country_id: StringName) -> void:
	_card.show_info(StaffMapCountryCard.info(_simulation.state, _viewer, country_id), _palette)
	if _panel != null:
		_panel.hide()


func close_card() -> bool:
	var was_open := _card.visible
	_card.hide()
	return was_open


func toggle_panel() -> void:
	if _panel == null:
		return
	if _panel.visible:
		_panel.hide()
		return
	_card.hide()
	_panel.show_state(_simulation.state)


## The country whose name lies under the ground point `ground` (hex units, x / z), &"" for none.
func country_name_at(ground: Vector2) -> StringName:
	var names := _view.get_node_or_null("Countries")
	if names == null or not names.visible:
		return &""
	for child in names.get_children():
		var label := child as Label3D
		if label == null:
			continue
		var box := label.get_aabb()
		# The label lies flat (rotated -90 degrees about x): local y runs north = -z.
		var local := ground - Vector2(label.position.x, label.position.z)
		if local.x >= box.position.x and local.x <= box.end.x:
			if -local.y >= box.position.y and -local.y <= box.end.y:
				var definition := CountryDefinition.find_by_iso(String(label.name))
				return definition.id if definition != null else &""
	return &""


func _on_stance_requested(country_id: StringName, stance: StringName, side: int) -> void:
	var state := _simulation.state
	var country := state.get_country(country_id)
	if country == null:
		return
	var problem := CountryRules.transition_problem(country, stance, side)
	if problem != "":
		_toast.call(problem, _palette.ui_alert)
		_panel.show_state(state)  # put the dropdown back on the real stance
		return
	for event in CountryRules.set_stance(state, country_id, stance, side, &"debug", -1):
		_simulation.event_emitted.emit(event)


## The panel's Raise / Lower: the plain EscalationRules functions (the same ones the real
## decisions use), their events re-emitted on the simulation like a command's.
func _on_escalation_requested(by: int, raise: bool) -> void:
	var state := _simulation.state
	if not state.result.is_empty():
		_toast.call(TranslationServer.translate("ORDER_REJECTED_OPERATION_OVER"), _palette.ui_alert)
		return
	var events: Array[Dictionary] = []
	if raise:
		events = EscalationRules.raise(state, by, &"decision")
	else:
		events = EscalationRules.lower(state, by, &"stand_down")
	for event in events:
		_simulation.event_emitted.emit(event)
	_panel.show_state(state)


## The panel's Strike: the real StrikeCommand through the simulation (a rejection shows its code
## as a toast, StaffMap._on_command_rejected). A negative player is the panel asking for a rebuild.
func _on_strike_requested(player: int, means: StringName, count: int, target: StringName) -> void:
	var state := _simulation.state
	if player < 0:
		_panel.show_state(state)
		return
	if player != state.current_player:
		_toast.call("wrong_player", _palette.ui_alert)
		return
	_simulation.execute(StrikeCommand.new(means, target, count))


## The panel's +stock: StrikeRules.add_stock with source `debug`, its events re-emitted.
func _on_stock_requested(player: int, means: StringName, count: int) -> void:
	for event in StrikeRules.add_stock(_simulation.state, player, means, count, &"debug"):
		_simulation.event_emitted.emit(event)
