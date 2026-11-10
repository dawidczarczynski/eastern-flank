class_name StaffMapDecisionsHud
extends RefCounted
## The Politics screen of the staff map (TASK-117) behind a few calls: opens / closes it (key H, the
## command bar button), issues the chosen decision through the simulation and keeps the sheet
## current. Only reads the state; changes happen by commands.

var _simulation: OperationalSimulation
var _palette: StaffMapPalette
var _viewer: Callable  # () -> int
var _panel: StaffMapDecisionsPanel


func _init(
	simulation: OperationalSimulation, palette: StaffMapPalette, hud: CanvasLayer, viewer: Callable
) -> void:
	_simulation = simulation
	_palette = palette
	_viewer = viewer
	_panel = StaffMapDecisionsPanel.new()
	_panel.decision_chosen.connect(_on_chosen)
	_panel.close_requested.connect(close)
	hud.add_child(_panel)


func panel() -> StaffMapDecisionsPanel:
	return _panel


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if _panel.visible:
		_panel.hide()
	else:
		_panel.show_state(_simulation.state, _palette, _viewer.call())


## Closes the panel; true when it was open.
func close() -> bool:
	var was_open := _panel.visible
	_panel.hide()
	return was_open


func refresh() -> void:
	_panel.refresh()


func _on_chosen(id: StringName, country: StringName) -> void:
	var command := StaffMapDecisionsModel.command(id, country)
	var before := _simulation.state.decisions_left
	if command != null:
		_simulation.execute(command)
	if _simulation.state.decisions_left < before:
		_panel.set_result(id)
	else:
		_panel.refresh()


## A key while the sheet is open (the map takes none); false when it is closed.
func handle_key(keycode: Key) -> bool:
	return is_open() and _panel.handle_key(keycode)
