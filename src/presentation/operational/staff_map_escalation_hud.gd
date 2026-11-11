class_name StaffMapEscalationHud
extends RefCounted
## Everything about the escalation ladder on the staff map (TASK-115) behind a few calls, so
## StaffMap stays small: the ladder card, the toast of every change (with who joined at Regional
## war) and the end notice. Only reads the state / events; the chip lives in the turn bar.

signal menu_requested

var _simulation: OperationalSimulation
var _palette: StaffMapPalette
var _toast: Callable  # (message: String, colour: Color)
var _card: StaffMapLadderCard
var _end: StaffMapEndNotice
var _changed_text := ""
var _changed_colour := Color.WHITE
var _joined: Array[String] = []


func _init(
	simulation: OperationalSimulation, palette: StaffMapPalette, hud: CanvasLayer, toast: Callable
) -> void:
	_simulation = simulation
	_palette = palette
	_toast = toast
	_card = StaffMapLadderCard.new()
	hud.add_child(_card)
	_end = StaffMapEndNotice.new()
	_end.z_index = 100  # above the toasts, below nothing
	_end.menu_pressed.connect(func() -> void: menu_requested.emit())
	hud.add_child(_end)
	# A resumed operation may already be over.
	if not simulation.state.result.is_empty():
		_show_end(_ended_event(simulation.state))


func card() -> StaffMapLadderCard:
	return _card


func end_notice() -> StaffMapEndNotice:
	return _end


## Opens the ladder card, or closes it when open.
func toggle_card() -> void:
	if _card.visible:
		_card.hide()
	else:
		_card.show_state(_simulation.state, _palette)


## Closes the card; true when it was open.
func close_card() -> bool:
	var was_open := _card.visible
	_card.hide()
	return was_open


## Places the card centred under the turn bar (`bar_bottom` = its lower edge).
func place(viewport_width: float, bar_bottom: float) -> void:
	_card.reset_size()
	_card.position = Vector2((viewport_width - _card.size.x) / 2.0, bar_bottom + 6.0)


func refresh() -> void:
	if _card.visible:
		_card.show_state(_simulation.state, _palette)


## Reacts to one operational event: a toast per change, the joiners, the end notice.
func on_event(event: Dictionary) -> void:
	var state := _simulation.state
	match event.get("type"):
		&"escalation_changed":
			_joined.clear()
			_changed_text = StaffMapEscalation.change_text(state, event)
			var level: int = event["level"]
			_changed_colour = (
				_palette.ui_alert
				if level > int(event["previous"])
				else StaffMapEscalation.CALM_COLOUR
			)
			_toast.call(_changed_text, _changed_colour)
			refresh()
		&"country_stance_changed":
			if event.get("cause") == &"ladder" and event.get("stance") != &"neutral":
				var definition := CountryDefinition.find(StringName(event["country"]))
				if definition != null:
					_joined.append(TranslationServer.translate(definition.display_name))
					var text := (
						"%s · %s"
						% [
							_changed_text,
							TranslationServer.translate("joins: %s") % ", ".join(_joined)
						]
					)
					_toast.call(text, _changed_colour)
		&"operation_ended":
			_show_end(event)
			if event.get("reason") == &"nuclear_use":
				_end.play()  # grey, black, then the notice


func _show_end(event: Dictionary) -> void:
	var state := _simulation.state
	_card.hide()
	_end.present(StaffMapEscalation.end_lines(state, event), _palette)


static func _ended_event(state: OperationalState) -> Dictionary:
	return {
		"winner": state.result.get("winner", -1),
		"by": state.result.get("by", 0),
		"reason": state.result.get("reason", &""),
	}
