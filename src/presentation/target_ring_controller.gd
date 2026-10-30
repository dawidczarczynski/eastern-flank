class_name TargetRingController
extends Node
## Input and HUD for attacking a target (TASK-089b), kept out of BattleController:
## - the target tag + crosshair cursor while the hovered enemy is a valid target of the selected
##   unit;
## - the unit ring: RMB click on a unit opens the HUD v3 radial ring on it (TargetRingModel: an
##   enemy gets 1 ATTACK + 2 INFO, an own unit 2 INFO), with the hovered action's detail card
##   beside it, or the unit's card once INFO is triggered (the only place the card shows).
##   It follows the unit every frame and closes on Esc, a click elsewhere, the end of the turn or
##   when input stops being allowed. ATTACK issues AttackCommand through GameSimulation.execute().

var _sim: GameSimulation
var _human := 0
var _unit_views: Dictionary  # unit id -> UnitView (shared with BattleController)
var _portrait_of: Callable  # (state, unit) -> Texture2D or null
var _input_allowed: Callable  # () -> bool
var _ring: RadialRing
var _card: RingDetailCard
var _info: UnitPopup
var _tag: TargetTag
var _model: Dictionary = {}  # TargetRingModel.build() of the open ring, {} = closed
var _info_pinned := false
var _tag_key := Vector2i(-1, -1)  # (hovered, selected) the tag shows, x -1 = none
var _tag_lines: Array[Dictionary] = []


## `hud_root` receives the ring, its cards and the tag (above the hover card).
func setup(
	sim: GameSimulation,
	human_player: int,
	hud_root: Control,
	unit_views: Dictionary,
	portrait_of: Callable,
	input_allowed: Callable
) -> void:
	name = "TargetRing"
	_sim = sim
	_human = human_player
	_unit_views = unit_views
	_portrait_of = portrait_of
	_input_allowed = input_allowed
	_tag = TargetTag.new()
	hud_root.add_child(_tag)
	_ring = RadialRing.new()
	_ring.hide()
	_ring.slot_hovered.connect(_on_slot_hovered)
	_ring.slot_pressed.connect(_activate)
	_ring.dismissed.connect(close)
	hud_root.add_child(_ring)
	_card = RingDetailCard.new()
	hud_root.add_child(_card)
	_info = UnitPopup.new()
	_info.name = "TargetInfo"
	_info.hide()
	hud_root.add_child(_info)


func is_open() -> bool:
	return not _model.is_empty()


## Opens the ring on `target_id` for `attacker_id` (-1 = nothing selected: ATTACK is disabled).
func open(attacker_id: int, target_id: int) -> void:
	var state := _sim.state
	_model = TargetRingModel.build(state, _human, attacker_id, target_id)
	_info_pinned = false
	var slots: Array[Dictionary] = []
	slots.assign(_model["slots"])
	_ring.slots = slots
	_ring.accent = UiPalette.faction_color(state, _human)
	_ring.hovered = -1
	_ring.show()
	for control: Control in [_ring, _card, _info]:
		control.move_to_front()  # above the other HUD panels
	_hide_tag()
	_refresh_side()
	follow()


func close() -> void:
	if not is_open():
		return
	_model = {}
	_ring.hovered = -1
	_ring.hide()
	_card.hide()
	_info.hide()


## A click that never became a camera drag on tile `coord` (Vector2i or null): with the ring open
## any click closes it (an RMB on a unit reopens it there); with it closed an RMB on a unit opens
## it. Returns true when the click was used.
func handle_click(button: MouseButton, coord: Variant, selected_id: int) -> bool:
	var clicked := _sim.state.unit_at(coord) if coord != null else null
	var on_unit := button == MOUSE_BUTTON_RIGHT and clicked != null and clicked.is_alive()
	if not is_open() and not on_unit:
		return false
	close()
	if on_unit:
		open(selected_id, clicked.id)
	return true


## Keys while the ring is open: Esc closes, 1-6 trigger a slot. Returns true when used.
func handle_key(keycode: Key) -> bool:
	if not is_open():
		return false
	if keycode == KEY_ESCAPE:
		close()
		return true
	var slot: int = keycode - KEY_1
	if slot < 0 or slot >= RadialRingGeometry.SLOT_COUNT:
		return false
	_activate(slot)
	return true


## Tag + crosshair for `hovered` (or null) while `selected_id` is selected; `hidden` during a
## camera drag, event playback and after game over. Returns true when the tag is shown. Called
## every frame; the tag is rebuilt only on a new pair.
func update_tag(selected_id: int, hovered: Unit, hidden: bool, mouse: Vector2) -> bool:
	# A HUD control under the cursor (end turn button) hides the tag: _hovered_hex keeps the map
	# tile under it.
	if hidden or is_open() or hovered == null or get_viewport().gui_get_hovered_control() != null:
		_hide_tag()
		return false
	var key := Vector2i(hovered.id, selected_id)
	if key != _tag_key:
		_tag_key = key
		_tag_lines = HudModel.attack_tag(_sim.state, selected_id, hovered.id)
		if not _tag_lines.is_empty():
			_tag.show_lines(_tag_lines)
			_tag.move_to_front()
	if _tag_lines.is_empty():
		_tag.hide()
		CrosshairCursor.set_active(false)
		return false
	_tag.position = TargetTag.placement(
		mouse, get_viewport().get_visible_rect().size, _tag.tag_size()
	)
	_tag.show()
	CrosshairCursor.set_active(true)
	return true


## Keeps the ring (and its card) on the target's projected position; closes it when the target
## is gone or input stops being allowed (event playback, the AI's turn).
func follow() -> void:
	if not is_open():
		return
	var screen: Variant = screen_position(_model["target_id"])
	var target := _sim.state.get_unit(_model["target_id"])
	if screen == null or target == null or not target.is_alive() or not _input_allowed.call():
		close()
		return
	var viewport := get_viewport().get_visible_rect().size
	var center := RadialRingGeometry.clamp_center(screen, viewport)
	_ring.set_center(center)
	if _card.visible:
		_card.position = RadialRingGeometry.card_position(center, viewport, _card.card_size())
	if _info.visible:
		_info.position = RadialRingGeometry.card_position(center, viewport, _info.card_size())


## Screen position of a unit's view, or null when it has none or it is behind the camera.
func screen_position(unit_id: int) -> Variant:
	var view: UnitView = _unit_views.get(unit_id)
	var camera := get_viewport().get_camera_3d()
	if view == null or camera == null or camera.is_position_behind(view.global_position):
		return null
	return camera.unproject_position(view.global_position)


func _process(_delta: float) -> void:
	follow()


func _exit_tree() -> void:
	CrosshairCursor.set_active(false)


func _hide_tag() -> void:
	_tag_key = Vector2i(-1, -1)
	_tag_lines = []
	if _tag != null:
		_tag.hide()
	CrosshairCursor.set_active(false)


func _activate(slot: int) -> void:
	if not is_open() or slot >= (_model["slots"] as Array).size():
		return
	var data: Dictionary = _model["slots"][slot]
	match data["action"]:
		&"attack":
			if data["enabled"]:
				var command := AttackCommand.new(_model["attacker_id"], _model["target_id"])
				close()
				_sim.execute(command)
			else:
				_ring.hovered = slot  # a key press shows why it is unavailable
				_refresh_side()
		&"info":
			_info_pinned = not _info_pinned
			_refresh_side()


func _on_slot_hovered(_slot: int) -> void:
	_refresh_side()


## Beside the ring: the unit's card once INFO was triggered (while INFO or nothing is hovered),
## else the hovered action's detail card, else the unit summary.
func _refresh_side() -> void:
	var slot := _ring.hovered
	var show_info := _info_pinned and (slot == -1 or slot == TargetRingModel.SLOT_INFO)
	_info.visible = false
	_card.visible = false
	if show_info:
		var target := _sim.state.get_unit(_model["target_id"])
		_info.show_model(UnitPopupModel.build(_sim.state, target, _human))
		_info.set_portrait(_portrait_of.call(_sim.state, target))
		_info.show()
	else:
		var detail: Dictionary = _model["summary"]
		if slot == TargetRingModel.SLOT_ATTACK and not (_model["attack"] as Dictionary).is_empty():
			detail = _model["attack"]
		elif slot == TargetRingModel.SLOT_INFO:
			detail = _model["info"]
		_card.show_detail(detail, _ring.accent)
	follow()


## Debug only (screenshot hooks): where to put `target_id` so `attacker_id` can attack it: where
## it stands when it already is a valid target, else a free tile next to the attacker, east first.
static func debug_target_tile(state: GameState, attacker_id: int, target_id: int) -> Vector2i:
	if AttackCommand.valid_targets(state, attacker_id).has(target_id):
		return state.get_unit(target_id).coord
	var origin := state.get_unit(attacker_id).coord
	for direction: Vector2i in Hex.DIRECTIONS:
		var coord := origin + direction
		if state.grid.has_tile(coord) and state.unit_at(coord) == null:
			return coord
	return origin


## Debug only (screenshot hooks, _process is disabled there): opens the ring on `target_id` with
## `slot` hovered (-1 = none); INFO is also triggered, so its shot shows the unit's card.
func debug_open(attacker_id: int, target_id: int, slot: int) -> void:
	close()
	open(attacker_id, target_id)
	_info_pinned = slot == TargetRingModel.SLOT_INFO
	_ring.hovered = slot
	_refresh_side()
