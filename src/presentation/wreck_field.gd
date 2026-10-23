class_name WreckField
extends Node3D
## Owner of all wrecks of a battle (TASK-065), a child of the Units node (same space as the unit
## views). It takes over a destroyed vehicle's body from its UnitView and relays the events that
## age or hide wrecks. View-only: it never reads or writes GameState.

## Graphics quality switches (GraphicsQuality.features), set by BattleController before use.
var quality: Dictionary = {}
var _wrecks: Array[WreckView] = []


## Moves the dying `view`'s body into a new WreckView at the same place, on tile `coord`.
func adopt(view: UnitView, coord: Vector2i) -> WreckView:
	var body := view.take_body()
	if body == null:
		return null
	var wreck := WreckView.new()
	wreck.name = "Wreck%d" % view.unit_id
	wreck.position = view.position
	add_child(wreck)
	wreck.setup(view.unit_id, coord, body, quality)
	_wrecks.append(wreck)
	return wreck


func wrecks() -> Array[WreckView]:
	return _wrecks


## The wreck standing on `coord` that is still shown, or null.
func visible_wreck_at(coord: Vector2i) -> WreckView:
	for wreck in _wrecks:
		if wreck.coord() == coord and not wreck.is_hidden():
			return wreck
	return null


## A unit finished a move on `to`.
func on_unit_moved(to: Vector2i) -> void:
	for wreck in _wrecks:
		wreck.on_unit_moved(to)


func on_turn_started() -> void:
	for wreck in _wrecks:
		wreck.on_turn_started()
