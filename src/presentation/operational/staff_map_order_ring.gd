class_name StaffMapOrderRing
extends RefCounted
## Order ring of the staff map: the battle unit ring (RadialRing + RingDetailCard, as in
## TargetRingController) opened on a hex by a right click with an own formation selected. Slots
## and cards come from StaffMapOrderRingModel (slot 5 INFO opens the full panel, TASK-151);
## choosing a slot builds IssueOrderCommand / CancelOrderCommand and hands it to `execute` (the
## staff map's simulation). The ring follows the
## hex through pan / zoom / tilt (`follow`) and stays on screen. Keys 1-4 pick a slot, Esc closes.

## A slot was accepted by the simulation: `action` is a posture id or &"cancel".
signal ordered(action: StringName)
## INFO was chosen (slot 5 / key I): open the full panel of that formation (TASK-151).
signal info_requested(formation_id: StringName)
signal closed

var _ring: RadialRing
var _card: RingDetailCard
var _model: Dictionary = {}  # StaffMapOrderRingModel.build() of the open ring, {} = closed
var _accent := UiPalette.AMBER
var _execute: Callable  # (OperationalCommand) -> bool
var _screen_of_hex: Callable  # (Vector2i) -> Vector2
var _viewport: Callable  # () -> Vector2
var _still_valid: Callable  # (StringName) -> bool: may that formation still be ordered?
var _avoid: Callable  # () -> Rect2: docked panel the card must not cover (empty = none)
var _clear: Callable  # () -> Rect2: screen part no bar / window covers (invalid = whole screen)


func _init(
	parent: Node,
	execute: Callable,
	screen_of_hex: Callable,
	viewport: Callable,
	still_valid: Callable,
	avoid := Callable(),
	clear := Callable()
) -> void:
	_execute = execute
	_screen_of_hex = screen_of_hex
	_viewport = viewport
	_still_valid = still_valid
	_avoid = avoid
	_clear = clear
	_ring = RadialRing.new()
	_ring.name = "OrderRing"
	_ring.hide()
	_ring.slot_hovered.connect(_on_slot_hovered)
	_ring.slot_pressed.connect(activate)
	_ring.dismissed.connect(close)
	parent.add_child(_ring)
	_card = RingDetailCard.new()
	_card.name = "OrderRingCard"
	parent.add_child(_card)


func is_open() -> bool:
	return not _model.is_empty()


## True for a ring opened on a counter (only CANCEL ORDER and INFO), false for a hex ring.
func is_on_counter() -> bool:
	return is_open() and _model.get("on_counter", false)


func hex() -> Vector2i:
	return _model["hex"] if is_open() else StaffMapRoutePreview.OFF


func formation_id() -> StringName:
	return _model["formation_id"] if is_open() else &""


func ring() -> RadialRing:
	return _ring


func card() -> RingDetailCard:
	return _card


## Slots of the open ring (RadialRing format); empty when closed.
func slots() -> Array[Dictionary]:
	return _ring.slots


## The posture of the hovered slot, &"" for none / CANCEL.
func hovered_posture() -> StringName:
	var slot := _ring.hovered
	if not is_open() or slot < 0 or slot >= OperationalPosture.NAMES.size():
		return &""
	return _model["slots"][slot]["action"]


## Opens the ring on `hex` for `formation`; the colour is the acting side's. `info_id` = the
## formation INFO is about when it is not `formation` (the hostile counter the ring was opened on).
func open(
	state: OperationalState,
	formation: Formation,
	hex_coord: Vector2i,
	accent: Color,
	on_counter := false,
	info_id := &""
) -> void:
	_model = StaffMapOrderRingModel.build(state, formation, hex_coord, on_counter)
	_model["info_id"] = info_id  # &"" = INFO is about the ordered formation itself
	_accent = accent
	var slots: Array[Dictionary] = []
	slots.assign(_model["slots"])
	_ring.slots = slots
	_ring.accent = accent
	_ring.hovered = -1
	_ring.show()
	_ring.move_to_front()
	_card.move_to_front()
	_refresh_card()
	follow()


func close() -> void:
	if not is_open():
		return
	_model = {}
	_ring.hovered = -1
	_ring.hide()
	_card.hide()
	closed.emit()


## Keys while the ring is open: Esc closes, I = INFO, 1-6 pick a slot. Returns true when used.
func handle_key(keycode: Key) -> bool:
	if not is_open():
		return false
	if keycode == KEY_ESCAPE:
		close()
		return true
	if keycode == KEY_I:
		activate(StaffMapOrderRingModel.SLOT_INFO)
		return true
	var slot: int = keycode - KEY_1
	if keycode >= KEY_KP_1:
		slot = keycode - KEY_KP_1
	if slot < 0 or slot >= RadialRingGeometry.SLOT_COUNT:
		return false
	activate(slot)
	return true


## Picks `slot`: an enabled one gives the order and closes the ring, a disabled one shows its
## reason on the card (also for a key press), an empty one does nothing.
func activate(slot: int) -> void:
	if not is_open() or slot < 0 or slot >= (_model["slots"] as Array).size():
		return
	var data: Dictionary = _model["slots"][slot]
	if data["empty"]:
		return
	if not data["enabled"]:
		_ring.hovered = slot
		_refresh_card()
		return
	var action: StringName = data["action"]
	if action == StaffMapOrderRingModel.INFO:
		var id: StringName = _model["formation_id"]
		if _model.get("info_id", &"") != &"":
			id = _model["info_id"]
		close()
		info_requested.emit(id)
		return
	var command: OperationalCommand
	if action == StaffMapOrderRingModel.CANCEL:
		command = CancelOrderCommand.new(_model["formation_id"])
	else:
		command = IssueOrderCommand.new(_model["formation_id"], _model["hex"], action)
	close()
	if _execute.call(command):
		ordered.emit(action)


## Keeps the ring on its hex (kept fully on screen) and the card beside it; closes the ring when
## its formation may no longer be ordered.
func follow() -> void:
	if not is_open():
		return
	if not _still_valid.call(_model["formation_id"]):
		close()
		return
	var viewport: Vector2 = _viewport.call()
	var avoid: Rect2 = _avoid.call() if _avoid.is_valid() else Rect2()
	var clear := Rect2(Vector2.ZERO, viewport)
	if _clear.is_valid():
		clear = _clear.call()
	# Work in clear-zone coordinates so the ring and card stay clear of the bars and windows.
	avoid.position -= clear.position
	var center := RadialRingGeometry.clamp_center_avoiding(
		(_screen_of_hex.call(_model["hex"]) as Vector2) - clear.position, clear.size, avoid
	)
	_ring.set_center(center + clear.position)
	if _card.visible:
		_card.position = (
			RadialRingGeometry.card_position_avoiding(center, clear.size, _card.card_size(), avoid)
			+ clear.position
		)


func _on_slot_hovered(_slot: int) -> void:
	_refresh_card()


## The hovered slot's card, else the summary.
func _refresh_card() -> void:
	var slot := _ring.hovered
	var detail: Dictionary = _model["summary"]
	if slot >= 0 and slot < (_model["details"] as Array).size():
		var slot_detail: Dictionary = _model["details"][slot]
		if not slot_detail.is_empty():
			detail = slot_detail
	_card.show_detail(detail, _accent)
	follow()
