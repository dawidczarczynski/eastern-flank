class_name StaffMapDecisionsHud
extends RefCounted
## The POLITICS tab of the right dock (TASK-117, TASK-174b) behind a few calls: fills / hides the
## panel (the owner, StaffMap, opens the dock around it: key H, the command bar button), issues the
## chosen decision through the simulation and keeps the tab current. Only reads the state; changes
## happen by commands.

## The X, Esc or H asked to close the tab: the owner closes the dock.
signal close_requested

var _simulation: OperationalSimulation
var _palette: StaffMapPalette
var _viewer: Callable  # () -> int
var _panel: StaffMapDecisionsPanel


func _init(simulation: OperationalSimulation, palette: StaffMapPalette, viewer: Callable) -> void:
	_simulation = simulation
	_palette = palette
	_viewer = viewer
	_panel = StaffMapDecisionsPanel.new()
	_panel.decision_chosen.connect(_on_chosen)
	_panel.close_requested.connect(close_requested.emit)


func panel() -> StaffMapDecisionsPanel:
	return _panel


func is_open() -> bool:
	return _panel.visible


## Rebuilds the tab from the state and shows it (the owner has opened the dock).
func open() -> void:
	_panel.show_state(_simulation.state, _palette, _viewer.call())


## Closes the tab through the owner (the dock closes and hides the panel); true when it was open.
func close() -> bool:
	if not _panel.visible:
		return false
	close_requested.emit()
	return true


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


## A key while the tab is open; false when it is closed or the key is not the tab's.
func handle_key(keycode: Key) -> bool:
	return is_open() and _panel.handle_key(keycode)
