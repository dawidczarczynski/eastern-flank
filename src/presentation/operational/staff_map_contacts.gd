class_name StaffMapContacts
extends RefCounted
## The contact view of the staff map (TASK-094a): keeps the queue of pending battles from the
## `battle_pending` / `battle_resolved` events, dims the map (scrim under the counters), rings
## the battle hex, shows the contact notice next to it and the queue at the left edge. Pure view:
## the debug button sends a ResolveBattleCommand through `execute` (an OperationalSimulation
## facade call supplied by the owner); Play battle is forwarded as `play_requested` (the owner
## hands the campaign to Session, TASK-094c), likewise Auto-resolve
## (`auto_requested`, TASK-120); nothing here changes the state.

signal focus_requested(coord: Vector2i)
signal play_requested
signal auto_requested

const SCRIM := Color(5 / 255.0, 7 / 255.0, 5 / 255.0, 0.55)
const RING_INNER := 44.0
const RING_OUTER := 56.0
const NOTICE_GAP := 140.0
const SCREEN_MARGIN := 16.0

var notice: StaffMapContactNotice
var queue: StaffMapContactQueue
var scrim: ColorRect
var ring: Control

var _entries: Array[Dictionary] = []  # {attacker_id, defender_id, at}
var _shown := false
var _key := ""  # attacker>defender of the battle shown, to centre once per battle
var _setup: BattleSetup  # the first pending battle as shown
var _palette: StaffMapPalette
var _execute: Callable  # (OperationalCommand) -> bool
var _locate: Callable  # (Vector2i) -> Vector2 screen position of a hex
var _viewport: Callable  # () -> Vector2


func _init(
	palette: StaffMapPalette,
	map_layer: CanvasLayer,
	hud: CanvasLayer,
	execute: Callable,
	locate: Callable,
	viewport: Callable,
	debug: bool
) -> void:
	_palette = palette
	_execute = execute
	_locate = locate
	_viewport = viewport
	scrim = ColorRect.new()
	scrim.name = "ContactScrim"
	scrim.color = SCRIM
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.hide()
	map_layer.add_child(scrim)
	map_layer.move_child(scrim, 0)  # under the counters: the battle's two stay bright
	ring = _Ring.new()
	ring.name = "ContactRing"
	ring.hide()
	map_layer.add_child(ring)
	map_layer.move_child(ring, 1)
	notice = StaffMapContactNotice.new()
	notice.set_debug(debug)
	notice.resolve_pressed.connect(resolve_as_draw)
	notice.play_pressed.connect(func() -> void: play_requested.emit())
	notice.auto_pressed.connect(func() -> void: auto_requested.emit())
	hud.add_child(notice)
	queue = StaffMapContactQueue.new()
	hud.add_child(queue)


## Result of a battle nobody fought: no winner, every company at its start strength.
static func draw_result(setup: BattleSetup) -> BattleResult:
	var result := BattleResult.new()
	result.winner = -1
	result.reason = &"turn_limit"
	result.turns = 0
	for company in setup.companies:
		var reported := BattleResult.Company.new()
		reported.player = company.player
		reported.unit_type = company.unit_type
		reported.ref = company.ref
		reported.strength_start = company.strength
		reported.strength_end = company.strength
		result.companies.append(reported)
	result.settle(setup)
	return result


## Keeps the queue of `battle_pending` / `battle_resolved`; other events are ignored.
func on_event(event: Dictionary) -> void:
	match event.get("type"):
		&"battle_pending":
			(
				_entries
				. append(
					{
						"attacker_id": event["attacker_id"],
						"defender_id": event["defender_id"],
						"at": event["at"],
					}
				)
			)
		&"battle_resolved":
			if not _entries.is_empty():
				_entries.pop_front()


## Rebuilds the queue from the state's pending battles (a staff map coming back from a battle
## missed their events): attacker / defender from the company refs, the defender's hex.
func sync(state: OperationalState) -> void:
	_entries.clear()
	_key = ""
	for setup in state.pending_battles:
		var ids := ContactBattle.formation_ids(setup)
		var defender := state.get_formation(ids[1])
		(
			_entries
			. append(
				{
					"attacker_id": ids[0],
					"defender_id": ids[1],
					"at": defender.coord if defender != null else Vector2i.ZERO,
				}
			)
		)


## Axial hex of the battle shown now (the defender's).
func active_hex() -> Vector2i:
	return _entries[0]["at"] if not _entries.is_empty() else Vector2i.ZERO


func pending_count() -> int:
	return _entries.size()


func is_active() -> bool:
	return _shown


## Shows or hides everything from the queue and the state. `allowed` is false while the counters
## slide (the notice waits until they stand). Returns true when a new battle became the active
## one, so the owner can centre the camera on its hex.
func refresh(state: OperationalState, viewer: int, allowed: bool) -> bool:
	var ready := allowed and not _entries.is_empty() and not state.pending_battles.is_empty()
	var first := _entries[0] if ready else {}
	var attacker := state.get_formation(first.get("attacker_id", &"")) if ready else null
	var defender := state.get_formation(first.get("defender_id", &"")) if ready else null
	if attacker == null or defender == null:
		ready = false
	var key := ""
	if ready:
		key = "%s>%s" % [first["attacker_id"], first["defender_id"]]
	var appeared := ready and key != _key
	_key = key
	_setup = state.pending_battles[0] if ready else null
	_shown = ready
	scrim.visible = ready
	ring.visible = ready
	if not ready:
		notice.hide()
		queue.hide()
		return false
	var places: Array[Vector2i] = []
	for entry in _entries:
		places.append(entry["at"])
	queue.show_places(places)
	notice.present(
		state,
		state.pending_battles[0],
		attacker,
		defender,
		first["at"],
		viewer,
		Vector2i(1, _entries.size()),
		_palette
	)
	layout()
	return appeared


## Puts ring and notice at the projected battle hex (call when the camera moved).
func layout() -> void:
	if not _shown or _entries.is_empty():
		return
	var at: Vector2 = _locate.call(_entries[0]["at"])
	ring.position = at
	var screen: Vector2 = _viewport.call()
	notice.reset_size()
	var size := notice.size
	# Right of the hex, centred on it, kept on screen (left of it when there is no room).
	var x := at.x + NOTICE_GAP
	if x + size.x > screen.x - SCREEN_MARGIN:
		x = at.x - NOTICE_GAP - size.x
	x = clampf(x, SCREEN_MARGIN, maxf(screen.x - size.x - SCREEN_MARGIN, SCREEN_MARGIN))
	var y := clampf(
		at.y - size.y * 0.5, SCREEN_MARGIN, maxf(screen.y - size.y - SCREEN_MARGIN, SCREEN_MARGIN)
	)
	notice.position = Vector2(x, y)


## Debug button: sends the draw for the first pending battle.
func resolve_as_draw() -> bool:
	if _execute.is_null() or _setup == null:
		return false
	return _execute.call(ResolveBattleCommand.new(draw_result(_setup)))


## The dashed alert ring around the battle hex (mockup 03).
class _Ring:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var colour := StaffMapContactNotice.ALERT
		var dashes := 28
		for i in dashes:
			var a := TAU * i / dashes
			draw_arc(Vector2.ZERO, RING_INNER, a, a + TAU / dashes * 0.6, 6, colour, 2.0, true)
		draw_arc(Vector2.ZERO, RING_OUTER, 0.0, TAU, 48, Color(colour, 0.5), 1.0, true)
