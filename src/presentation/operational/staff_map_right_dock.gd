class_name StaffMapRightDock
extends RefCounted
## Pure model of the right-hand tabbed dock of the staff map (TASK-174a, variant B of
## docs/design/operational_map/slide_in_panels.html): one 420 px dock, one section at a time
## tab, `close` closes, a selection closes the dock (not in strike mode) and it then stays
## closed until a key or a bar button opens it; the last open tab is remembered for the next
## open. No node.
enum Tab { STRIKE, POLITICS, JOURNAL }

const WIDTH := 420.0

var _open := false
var _tab := Tab.STRIKE


func is_open() -> bool:
	return _open


## The open tab (meaningful while open).
func tab() -> Tab:
	return _tab


func is_tab_open(tab_id: Tab) -> bool:
	return _open and _tab == tab_id


## The tab the next plain open shows: the last one that was open (STRIKE on first use).
func remembered_tab() -> Tab:
	return _tab


## Opens the dock on `tab_id`, or switches an open dock to it (never two sections).
func open(tab_id: Tab) -> void:
	_tab = tab_id
	_open = true


func open_remembered() -> void:
	open(_tab)


## The key of `tab_id`: opens, switches, or closes when that tab is already open.
## Returns whether the dock is open afterwards.
func toggle(tab_id: Tab) -> bool:
	if is_tab_open(tab_id):
		close()
		return false
	open(tab_id)
	return true


## Closes the dock; true when it was open. The tab stays remembered.
func close() -> bool:
	var was_open := _open
	_open = false
	return was_open


## A unit was selected (selection, INFO ring, key I): closes the dock unless the strike mode is
## open (a map click there is a target pick). True when it closed.
func on_selection(strike_mode: bool) -> bool:
	if strike_mode:
		return false
	return close()


## Screen px the dock covers on the right.
func inset() -> float:
	return WIDTH if _open else 0.0


## The minimum width of the map: the screen minus the dock, open or not (no zoom jump on open).
static func min_map_width(viewport_width: float) -> float:
	return viewport_width - WIDTH
