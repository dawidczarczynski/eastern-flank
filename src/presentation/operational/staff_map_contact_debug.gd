class_name StaffMapContactDebug
extends RefCounted
## The staff map's debug contact-map preview (TASK-094b, F9 with --debug) behind a few calls, so
## StaffMap stays small: the model (StaffMapContactPreview), its panel (StaffMapContactPanel) and
## the cut's outline – a screen-space line (StaffMapRouteRibbon, constant pixel width under zoom
## and the 2.5D tilt) draped on the relief. While the panel is open, left clicks on the map pick
## the attacker / defender hex. "Open battle map" hands the built setup to the battle scene
## (BattleOptions.pending_setup); returning from that battle goes to the main menu.

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
## Outline points per hex unit along each edge (the line follows the relief between them).
const SAMPLES_PER_UNIT := 6.0

## Called with the built setup when "Open battle map" is pressed (default: change scene).
var open_battle: Callable

var _preview: StaffMapContactPreview
var _panel: StaffMapContactPanel
var _line: StaffMapRouteRibbon
var _relief: StaffMapRelief
var _colour: Color


func _init(
	view: StaffMapView,
	state: OperationalState,
	theatre: ImportedMap,
	palette: StaffMapPalette,
	hud: CanvasLayer
) -> void:
	_preview = StaffMapContactPreview.new(state, theatre)
	_relief = view.relief()
	_colour = palette.ui_amber
	_line = StaffMapRouteRibbon.new("ContactCut")
	view.add_child(_line)
	_panel = StaffMapContactPanel.new()
	_panel.position = Vector2(16, 130)
	_panel.open_pressed.connect(_on_open)
	hud.add_child(_panel)
	open_battle = _change_scene


func preview() -> StaffMapContactPreview:
	return _preview


func panel() -> StaffMapContactPanel:
	return _panel


func outline_line() -> StaffMapRouteRibbon:
	return _line


func is_open() -> bool:
	return _panel.visible


## Opens the panel at `top_left` (under the politics panel) or closes it; the outline stays only
## while it is open.
func toggle(top_left: Vector2) -> void:
	if _panel.visible:
		_panel.hide()
		_line.clear()
		return
	_panel.position = top_left
	_panel.show()
	_refresh()


## A left click on operational hex `c` while the panel is open; false when it is closed (the map
## handles the click as usual).
func click(c: Vector2i) -> bool:
	if not _panel.visible:
		return false
	_preview.pick(c)
	_refresh()
	return true


## Picks both hexes and builds (screenshot tool).
func pick_pair(attacker_hex: Vector2i, defender_hex: Vector2i) -> void:
	_preview.pick_pair(attacker_hex, defender_hex)
	_refresh()


func _refresh() -> void:
	_panel.show_lines(_preview.lines(), _preview.setup != null)
	var corners := _preview.outline()
	if corners.is_empty():
		_line.clear()
		return
	_line.show_line(_draped(corners), _colour)


## The closed outline as 3D points on the relief, each edge sampled so the line follows it.
func _draped(corners: PackedVector2Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in corners.size() - 1:
		var a := corners[i]
		var b := corners[i + 1]
		var steps := maxi(1, ceili(a.distance_to(b) * SAMPLES_PER_UNIT))
		for s in steps:
			points.append(_relief.surface_point(a.lerp(b, float(s) / steps)))
	points.append(_relief.surface_point(corners[corners.size() - 1]))
	return points


func _on_open() -> void:
	if _preview.setup != null:
		open_battle.call(_preview.setup)


func _change_scene(setup: BattleSetup) -> void:
	BattleOptions.pending_setup = setup
	_panel.get_tree().change_scene_to_file(BATTLE_SCENE)
