# gdlint: disable=max-public-methods
class_name StaffMapStrikeHud
extends RefCounted
## The strike mode of the staff map (TASK-097b, GDD "Deep strikes") behind a few calls so StaffMap
## stays small: opens / closes the mode (key S, the turn bar button, Esc), keeps the picked means
## and salvo, shows which targets are legal, opens the confirm card and issues the commands
## (`StrikeCommand`, and `EscalateCommand` first for raise-and-strike) through the simulation; it
## also feeds the strike trail (arcs, bursts, interception marks) from the events. It only reads the
## state; every change goes through a command (rule 3).

signal open_changed(open: bool)
## The strike mode is open with a weapon picked (the staff map then shows the air defence cover).
signal cover_wanted_changed(wanted: bool)

## Events that may follow `strike_resolved` within its command (the report keeps collecting).
const TAIL_EVENTS: Array[StringName] = [
	&"installation_changed",
	&"installation_suppressed",
	&"formation_damaged",
	&"formation_destroyed",
	&"sanctuary_breached",
	&"escalation_changed",
	&"country_stance_changed",
	&"casus_belli_gained",
	&"operation_ended",
]
## Escalation causes of a strike itself (a decision or calm decay is another command).
const STRIKE_CAUSES: Array[StringName] = [&"sanctuary_breach", &"urban_strike"]

var _simulation: OperationalSimulation
var _palette: StaffMapPalette
var _viewer: Callable  # () -> int
var _toast: Callable  # (message: String, colour: Color)
var _panel: StaffMapStrikePanel
var _confirm: StaffMapStrikeConfirm
var _layer: StaffMapStrikeLayer
var _trail := StaffMapStrikeTrail.new()
var _open := false
var _means: StringName = &""
var _salvo := 1
var _hovered: StringName = &""
var _confirm_target: StringName = &""
var _confirm_raised := false
var _executing := false
var _cover_wanted := false
var _last_reject := ""
var _reports: StaffMapStrikeReports
var _pending := {}  # the strike_resolved being completed by the events of its command
var _stock_event := {}
var _launched := {}
var _reported_seq := 0  # the trail's strike sequence when the last report was made
var _names := {}  # formation id -> {name, max}: a destroyed formation is gone from the state


func _init(
	simulation: OperationalSimulation,
	palette: StaffMapPalette,
	hud: CanvasLayer,
	map_layer: Node,
	screen_of_hex: Callable,
	viewer: Callable,
	toast: Callable
) -> void:
	_simulation = simulation
	_palette = palette
	_viewer = viewer
	_toast = toast
	_panel = StaffMapStrikePanel.new()
	_panel.means_picked.connect(pick_means)
	_panel.salvo_set.connect(set_salvo)
	_panel.close_requested.connect(close)
	hud.add_child(_panel)
	_confirm = StaffMapStrikeConfirm.new()
	_confirm.confirmed.connect(confirm)
	_confirm.cancelled.connect(cancel)
	hud.add_child(_confirm)
	_reports = StaffMapStrikeReports.new(palette)
	_reports.attach(hud)
	_layer = StaffMapStrikeLayer.new()
	_layer.setup(palette, screen_of_hex, _trail)
	map_layer.add_child(_layer)
	simulation.command_rejected.connect(_on_rejected)
	_snapshot_names()


func panel() -> StaffMapStrikePanel:
	return _panel


func confirm_card() -> StaffMapStrikeConfirm:
	return _confirm


func reports() -> StaffMapStrikeReports:
	return _reports


func layer() -> StaffMapStrikeLayer:
	return _layer


func trail() -> StaffMapStrikeTrail:
	return _trail


func is_open() -> bool:
	return _open


## True while the mode is open with a weapon picked: the air defence cover is wanted on the map.
func wants_cover() -> bool:
	return _open and _means != &""


func _sync_cover() -> void:
	var wanted := wants_cover()
	if wanted != _cover_wanted:
		_cover_wanted = wanted
		cover_wanted_changed.emit(wanted)


func picked_means() -> StringName:
	return _means


func salvo() -> int:
	return _salvo


## True while the confirm card is up.
func is_confirming() -> bool:
	return _confirm.visible


## S / the turn bar button: opens the mode, or closes it. When it cannot open (not the viewer's
## turn, battle pending, operation over) a toast says why. Returns whether it is open afterwards.
func toggle() -> bool:
	if _open:
		close()
		return false
	var problem := StaffMapStrike.open_problem(_simulation.state, _viewer.call())
	if problem != "":
		_toast.call(StaffMapStrike.problem_text(problem), _palette.ui_alert)
		return false
	_open = true
	_means = &""
	_salvo = 1
	_hovered = &""
	refresh()
	open_changed.emit(true)
	_sync_cover()
	return true


## Closes the mode and the confirm card; true when the mode was open.
func close() -> bool:
	var was_open := _open
	_open = false
	_confirm.hide()
	_panel.hide()
	_hovered = &""
	_layer.set_targets([] as Array[Dictionary], _viewer.call())
	_sync_cover()
	if was_open:
		open_changed.emit(false)
	return was_open


func pick_means(id: StringName) -> void:
	var state := _simulation.state
	var limit := StaffMapStrike.salvo_max(state, _viewer.call(), id)
	if not _open or limit < 1:
		return
	_means = id
	_salvo = clampi(_salvo, 1, limit)
	_confirm.hide()
	refresh()
	_sync_cover()


## The salvo slider (1 .. the largest legal salvo of the picked means).
func set_salvo(count: int) -> void:
	if _means == &"":
		return
	var limit := StaffMapStrike.salvo_max(_simulation.state, _viewer.call(), _means)
	_salvo = clampi(count, 1, maxi(limit, 1))
	refresh()


func step_salvo(delta: int) -> void:
	if _means == &"":
		return
	var limit := StaffMapStrike.salvo_max(_simulation.state, _viewer.call(), _means)
	_salvo = clampi(_salvo + delta, 1, maxi(limit, 1))
	refresh()


## Re-reads the state (after every event): closes the mode when it cannot stay open, clamps the
## salvo to the stock and updates the panel and the target glows.
func refresh() -> void:
	if not _open:
		return
	var state := _simulation.state
	var viewer: int = _viewer.call()
	if StaffMapStrike.open_problem(state, viewer) != "":
		close()
		return
	var limit := StaffMapStrike.salvo_max(state, viewer, _means)
	if _means != &"" and limit < 1:
		_means = &""
		_confirm.hide()
		_sync_cover()
	_salvo = clampi(_salvo, 1, maxi(limit, 1))
	_panel.set_side(
		StaffMapTurnBar.side_name(state, viewer),
		StaffMapFormations.side_colour(_palette, viewer),
		_palette.outcome_intercepted
	)
	_panel.show_state(
		StaffMapStrike.means_list(state, viewer),
		_means,
		_salvo,
		limit,
		StaffMapStrike.strikes_text(state),
		_hint()
	)
	_update_hover_line()
	_layer.set_targets(_target_marks(), viewer)


## The target a click / hover points at: the enemy formation of a counter, the enemy installation
## of a marker, else the first enemy target on the hex; &"" for none.
func target_at(counter_id: StringName, marker_id: StringName, hex: Vector2i) -> StringName:
	var player: int = _viewer.call()
	var state := _simulation.state
	for id: StringName in [counter_id, marker_id]:
		if id != &"" and not StrikeRules.find_target(state, player, id).is_empty():
			return id
	for target in StrikeRules.targets(state, player):
		if target["coord"] == hex:
			return target["id"]
	return &""


## A click on the map while the mode is open (the caller found the target under the cursor, &""
## for none): picks the target. Always consumes the click; true when the mode is open.
func click(target_id: StringName) -> bool:
	if not _open:
		return false
	if _confirm.visible or target_id == &"":
		return true
	if _means == &"":
		_toast.call(_t("Pick a means first"), _palette.ui_amber)
		return true
	var state := _simulation.state
	var player: int = _viewer.call()
	var view := StaffMapStrike.target_view(state, player, target_id, _means)
	if state.strikes_left < 1 and (view["legal"] or view["conditional"]):
		_toast.call(StaffMapStrike.problem_text("no_strikes_left"), _palette.ui_alert)
	elif view["legal"] or view["conditional"]:
		_confirm_target = target_id
		_confirm_raised = view["conditional"]
		_confirm.present(
			StaffMapStrike.confirm_model(state, player, target_id, _means, _salvo, _confirm_raised)
		)
		_panel.hide()
	else:
		_toast.call(view["reason_text"], _palette.ui_alert)
	return true


## Confirm: raise-and-strike executes Escalate first, then the strike. A rejection shows its
## code (the map's rejection toast); a strike rejected after a successful Escalate says that the
## level was raised. A strike that went through closes the mode (S opens it again); a rejected
## one keeps it open.
func confirm() -> void:
	if not _confirm.visible:
		return
	var target := _confirm_target
	var raised := _confirm_raised
	_confirm.hide()
	_executing = true
	var ok := true
	if raised:
		ok = _simulation.execute(EscalateCommand.new())
	var struck := false
	if ok:
		_last_reject = ""
		struck = _simulation.execute(StrikeCommand.new(_means, target, _salvo))
		if not struck and raised:
			_toast.call(StaffMapStrike.failed_after_raise_text(_last_reject), _palette.ui_alert)
	_executing = false
	flush_report()
	if struck:
		close()
		return
	_panel.show()
	refresh()


## Cancel / Esc on the confirm card: back to the mode.
func cancel() -> void:
	_confirm.hide()
	_panel.show()
	refresh()


## A key for the result report (J, Enter, Esc, ◂ ▸); false when it is not for the report.
func handle_report_key(keycode: Key) -> bool:
	return _reports.handle_key(keycode)


## Per frame: completes a pending report and runs the report timers (nothing while idle).
func tick(delta: float) -> void:
	if not _pending.is_empty():
		flush_report()
	_reports.tick(delta)


## Turns the collected strike (and what its command caused) into a report card.
func flush_report() -> void:
	if _pending.is_empty():
		return
	var event := _pending
	_pending = {}
	_reports.add(StaffMapStrikeText.report_model(_simulation.state, event, _trail), _reveal_delay())
	_snapshot_names()


## A key while the mode is open: Esc leaves the confirm card, then the mode; Enter confirms. False
## when the key is not used.
func handle_key(keycode: Key) -> bool:
	if not _open:
		return false
	if keycode == KEY_ESCAPE:
		if _confirm.visible:
			cancel()
		else:
			close()
		return true
	if keycode in [KEY_ENTER, KEY_KP_ENTER] and _confirm.visible:
		confirm()
		return true
	return false


## The hovered target (from the map) for the panel line and the glow ring.
func set_hover(target_id: StringName) -> void:
	if target_id == _hovered:
		return
	_hovered = target_id
	if _open:
		_update_hover_line()
		_layer.set_targets(_target_marks(), _viewer.call())


## "Reason" line of the installation hover card while the mode is open with a means picked: why the
## target cannot be struck, or "" when it can / the mode is off.
func hover_note(target_id: StringName) -> String:
	if not _open or _means == &"":
		return ""
	var view := StaffMapStrike.target_view(_simulation.state, _viewer.call(), target_id, _means)
	return "" if view["legal"] else view["reason_text"]


## True when `point` (screen) is on the panel or the confirm card.
func covers(point: Vector2) -> bool:
	return (
		(_panel.visible and _panel.get_global_rect().has_point(point))
		or (_confirm.visible and _confirm.get_global_rect().has_point(point))
		or _reports.covers(point)
	)


## Camera moved or the window resized: redraw the layer and place the cards.
func layout(viewport: Vector2, top: float) -> void:
	_layer.layout()
	_reports.layout(viewport, top)
	_panel.reset_size()
	_panel.position = Vector2(viewport.x - 16.0 - _panel.size.x, top)
	_confirm.reset_size()
	_confirm.position = Vector2((viewport.x - _confirm.size.x) / 2.0, viewport.y * 0.22)


## Feeds the trail and the result report; call it for every operational event.
func on_event(event: Dictionary) -> void:
	var state := _simulation.state
	_collect_report(event)
	if _trail.on_event(state, _viewer.call(), event):
		_layer.layout()
	match event.get("type"):
		&"operational_turn_started", &"operational_turn_ended", &"operation_ended":
			refresh()
	if (
		event.get("type") == &"operational_turn_started"
		and int(event.get("player", -1)) == _viewer.call()
	):
		_reports.clear()  # the reports go with the trail at the viewer's turn start
		_snapshot_names()
	if _open and event.get("type") in [&"strike_stock_changed", &"installation_changed"]:
		refresh()


## Gathers a strike for its report: the stock change and the launch come first, `strike_resolved`
## opens the report, the escalation events of the same command complete it.
func _collect_report(event: Dictionary) -> void:
	var type: StringName = event.get("type", &"")
	match type:
		&"strike_stock_changed":
			if event.get("source") == &"strike":
				_stock_event = event
		&"strike_launched":
			_launched = event
		&"strike_resolved":
			flush_report()
			_pending = event.duplicate()
			_pending["viewer"] = _viewer.call()
			_pending["escalation"] = []
			if _launched.get("target") == event["target"]:
				_pending["coord"] = _launched["coord"]
			var after := _stock_event.get("total", -1) as int
			if _stock_event.get("player") == event["player"] and after >= 0:
				_pending["stock_after"] = after
				_pending["stock_before"] = after - int(_stock_event["count"])
			if _names.has(event["target"]):
				_pending["target_name"] = _names[event["target"]]["name"]
				_pending["target_max"] = _names[event["target"]]["max"]
		_:
			if _pending.is_empty():
				return
			if type == &"escalation_changed" and not event.get("cause") in STRIKE_CAUSES:
				flush_report()
			elif type == &"escalation_changed" or type == &"operation_ended":
				_pending["escalation"].append(event)
			elif type == &"installation_suppressed":
				if event.get("id") == _pending.get("target"):
					_pending["suppression"] = event
			elif not type in TAIL_EVENTS:
				flush_report()


## The card waits until the strike's last impact was seen on the map (TASK-147); a strike the
## trail did not draw (fog) uses the default delay.
func _reveal_delay() -> float:
	var delay := StaffMapStrikeReports.REVEAL_DELAY
	if _trail.strike_sequence() > _reported_seq:
		_reported_seq = _trail.strike_sequence()
		delay = _trail.seconds_to_last_impact() + StaffMapStrikeReports.IMPACT_REVEAL_SECONDS
	return delay


func _snapshot_names() -> void:
	_names.clear()
	for formation in _simulation.state.formations:
		_names[formation.id] = {
			"name": TranslationServer.translate(formation.display_name),
			"max": formation.max_strength(),
		}


func _t(key: String) -> String:
	return TranslationServer.translate(key)


func _hint() -> String:
	if _means == &"":
		return _t("Pick a means, then a target on the map. Esc leaves.")
	var means: StrikeMeansDefinition = _simulation.state.strike_means.get(_means)
	var weapon := _t(means.display_name) if means != null else ""
	var line := StaffMapStrikeText.salvo_line(weapon, _salvo)
	return "%s – %s" % [line, _t("Click a glowing target. Esc leaves.")]


func _update_hover_line() -> void:
	_panel.set_odds({})
	if _hovered == &"" or _means == &"":
		_panel.set_hover_text("")
		return
	var state := _simulation.state
	var view := StaffMapStrike.target_view(state, _viewer.call(), _hovered, _means)
	var target_label := StaffMapStrike.target_name(state, _hovered)
	if view["legal"]:
		_panel.set_hover_text("%s – %s" % [target_label, _t("click to strike")], _layer_colour())
		_panel.set_odds(StaffMapAirDefence.odds_for_target(state, _viewer.call(), _means, _hovered))
	elif view["conditional"]:
		_panel.set_hover_text("%s – %s" % [target_label, view["reason_text"]], _palette.ui_amber)
	else:
		_panel.set_hover_text("%s – %s" % [target_label, view["reason_text"]], _palette.ui_alert)


func _layer_colour() -> Color:
	return StaffMapFormations.side_colour(_palette, _viewer.call())


## Glow marks of every enemy target for the picked means (none before a means is picked).
func _target_marks() -> Array[Dictionary]:
	var marks: Array[Dictionary] = []
	if _means == &"":
		return marks
	var state := _simulation.state
	var player: int = _viewer.call()
	for target in StrikeRules.targets(state, player):
		var view := StaffMapStrike.target_view(state, player, target["id"], _means)
		var status := &"illegal"
		if view["legal"]:
			status = &"legal"
		elif view["conditional"]:
			status = &"conditional"
		(
			marks
			. append(
				{
					"coord": target["coord"],
					"installation": target["kind"] == &"installation",
					"status": status,
					"hovered": target["id"] == _hovered,
				}
			)
		)
	return marks


func _on_rejected(command: OperationalCommand, reason: String) -> void:
	if command is StrikeCommand:
		_last_reject = reason
