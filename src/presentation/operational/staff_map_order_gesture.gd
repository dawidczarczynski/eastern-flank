# gdlint: disable=max-public-methods
class_name StaffMapOrderGesture
extends RefCounted
## The order gesture of the staff map (TASK-153, docs/design/operational_map/order_lines_analysis.md
## sections 4 and 7, variant D "Armed line"): click an own counter (ARMED), move the cursor over a
## hex (AIMING, SNAPPED or INVALID), click it (COMMITTED, or CONFIRM first when the route has a
## border incident). Pure: no nodes, no simulation. The view feeds it clicks, hovers and a
## `verdict` of the hovered hex ({valid, reason, incident}, computed from the route preview) and
## executes the intents it returns, so the rules stay in the core (architecture rule 3).
## Click-click is the primary gesture; press-drag-release aiming is not built (decision 3).

enum State { IDLE, ARMED, AIMING, CONFIRM, COMMITTED, EDITING }
enum Aim { NONE, SNAPPED, INVALID }

## Intent types (the `type` key of what the input methods return).
const NONE := &"none"
const ARM := &"arm"  # {id}: select that own formation
const DISARM := &"disarm"  # deselect
const ISSUE := &"issue"  # {hex, posture}: execute IssueOrderCommand
const CONFIRM_NEEDED := &"confirm"  # {hex, posture}: execute it; the border prompt answers
const REJECT := &"reject"  # {reason}: refused without a command
const POSTURE := &"posture"  # {posture}: the picked posture changed
const EDIT := &"edit"  # {id}: the head of that issued order was grabbed (TASK-157)

const NO_HEX := Vector2i(-100000, -100000)
const SETTLE_SEC := 0.12  # the issued line settles from full to its issued opacity
const REASON_NO_ORDERS := "no_orders_left"

var _state := State.IDLE
var _aim := Aim.NONE
var _id: StringName = &""
var _hex := NO_HEX
var _reason := ""
var _posture: StringName = &""
var _suppressed_hex := NO_HEX  # after Esc: this hex does not aim again until the cursor leaves
var _elapsed := 0.0
var _blocked := true
var _was_editing := false  # the COMMITTED / CONFIRM order was an edit (fail() resumes it)
var _editing := false  # the armed formation's issued order is being re-aimed (EDITING)


## What disables the gesture: strike mode, a modal window, the counter slide, or a turn that is
## not the viewer's. A blocked gesture drops to IDLE and ignores every input.
func set_context(strike_mode: bool, modal: bool, sliding: bool, viewers_turn: bool) -> void:
	_blocked = strike_mode or modal or sliding or not viewers_turn
	if _blocked:
		_reset()


func is_blocked() -> bool:
	return _blocked


func state() -> State:
	return _state


func aim() -> Aim:
	return _aim


## The armed formation (&"" when IDLE).
func formation_id() -> StringName:
	return _id


## The aimed hex (NO_HEX unless AIMING / CONFIRM).
func hex() -> Vector2i:
	return _hex


## Why the aimed hex is invalid ("" when it is not).
func reason() -> String:
	return _reason


## The posture picked with keys 1-3 (&"" = the default of the target).
func posture() -> StringName:
	return _posture


## True while the cursor is being used to aim (AIMING or CONFIRM): the line flows then.
func is_aiming() -> bool:
	return _state == State.AIMING or _state == State.CONFIRM or (_editing and _hex != NO_HEX)


## The formation whose issued order is being re-aimed (&"" unless EDITING / its CONFIRM).
func edited_from() -> StringName:
	return _id if _editing else &""


## "FREE" for an order given this turn, "COSTS 1 ORDER" for an older one (TASK-157).
static func edit_cost_label(is_free: bool) -> String:
	return "FREE" if is_free else "COSTS 1 ORDER"


## 0 … 1 progress of the COMMITTED settle (0 outside it).
func settle() -> float:
	return clampf(_elapsed / SETTLE_SEC, 0.0, 1.0) if _state == State.COMMITTED else 0.0


## The view's selection changed to `id` (&"" = none): an own formation that may be ordered arms,
## anything else idles (a COMMITTED gesture keeps settling).
func select(id: StringName) -> void:
	if _blocked:
		return
	if id == &"":
		if _state != State.COMMITTED:
			_reset()
		return
	if id != _id:
		_posture = &""
		_editing = false
		_clear_aim()
		if _state != State.COMMITTED:
			_state = State.ARMED
	_id = id
	if _state == State.IDLE or _state == State.COMMITTED:
		_state = State.ARMED
		_elapsed = 0.0


## LMB click on the own counter `id`: IDLE (or another formation) -> ARMED; the armed one -> IDLE.
func click_own_counter(id: StringName) -> Dictionary:
	if _blocked:
		return _intent(NONE)
	if _state != State.IDLE and _state != State.COMMITTED and id == _id:
		_reset()
		return _intent(DISARM)
	if id != _id:
		_posture = &""
	_id = id
	_editing = false
	_clear_aim()
	_state = State.ARMED
	_elapsed = 0.0
	return _intent(ARM, {"id": id})


## LMB click on the head of the issued order of `id`: its re-aiming starts (EDITING); the old
## order stays until a replacement is issued (TASK-157).
func click_head(id: StringName) -> Dictionary:
	if _blocked:
		return _intent(NONE)
	if id != _id:
		_posture = &""
	_id = id
	_editing = true
	_clear_aim()
	_state = State.EDITING
	_elapsed = 0.0
	return _intent(EDIT, {"id": id})


## The cursor is over `hex` (NO_HEX = off the map); `verdict` = {valid, reason, incident} of an
## order there, `orders_left` the orders the side may still give this turn.
func hover(hex: Vector2i, verdict: Dictionary, orders_left: int) -> void:
	if _blocked or _state == State.IDLE or _state == State.COMMITTED or _state == State.CONFIRM:
		return
	if hex != _suppressed_hex:
		_suppressed_hex = NO_HEX
	if hex == NO_HEX or hex == _suppressed_hex:
		_clear_aim()
		_state = _idle_aim_state()
		return
	_state = _aim_state()
	_hex = hex
	_set_aim(verdict, orders_left)


## LMB click on the hex `hex` while armed: the intent to issue the order, to confirm it first, or
## the refusal (invalid hex, no orders left: no command at all).
func click_hex(hex: Vector2i, verdict: Dictionary, orders_left: int) -> Dictionary:
	if _blocked or _state == State.IDLE or _state == State.COMMITTED or _state == State.CONFIRM:
		return _intent(NONE)
	_state = _aim_state()
	_hex = hex
	_set_aim(verdict, orders_left)
	if _aim == Aim.INVALID:
		return _intent(REJECT, {"reason": _reason})
	var details := {"hex": hex, "posture": _posture}
	if verdict.get("incident", false):
		_state = State.CONFIRM
		return _intent(CONFIRM_NEEDED, details)
	_commit()
	return _intent(ISSUE, details)


## Enter on the border prompt: the order is being issued (CONFIRM -> COMMITTED).
func confirm() -> Dictionary:
	if _state == State.CONFIRM:
		_commit()
	return _intent(NONE)


## Esc: CONFIRM -> AIMING; from any other armed state (ARMED, AIMING, EDITING) one press leaves
## the order mode entirely (DISARM, picked posture included), so the aim line stops following
## the cursor.
func cancel() -> Dictionary:
	if _blocked or _state == State.IDLE or _state == State.COMMITTED:
		return _intent(NONE)
	if _state == State.CONFIRM:
		_state = _aim_state()
		return _intent(NONE)
	_reset()
	return _intent(DISARM)


## Key 1-3: the posture the next order is given in; the same key again drops it. Only while
## ARMED or AIMING.
func pick_posture(posture: StringName) -> Dictionary:
	if _blocked or not (_state in [State.ARMED, State.AIMING, State.EDITING]):
		return _intent(NONE)
	_posture = &"" if posture == _posture else posture
	return _intent(POSTURE, {"posture": _posture})


## Drops the picked posture (the view's own reasons: the order ring took over).
func clear_posture() -> void:
	_posture = &""


## The order was refused after all (the command rejected it): back to aiming.
func fail() -> void:
	if _state == State.COMMITTED or _state == State.CONFIRM:
		_editing = _editing or _was_editing
		_state = _aim_state() if _hex != NO_HEX else _idle_aim_state()
		_elapsed = 0.0


## Advances the COMMITTED settle by `delta` seconds; it ends in IDLE.
func tick(delta: float) -> void:
	if _state != State.COMMITTED:
		return
	_elapsed += delta
	if _elapsed >= SETTLE_SEC:
		_reset()


func _aim_state() -> State:
	return State.EDITING if _editing else State.AIMING


func _idle_aim_state() -> State:
	return State.EDITING if _editing else State.ARMED


func _commit() -> void:
	_was_editing = _editing
	_editing = false
	_state = State.COMMITTED
	_elapsed = 0.0
	_clear_aim()


func _set_aim(verdict: Dictionary, orders_left: int) -> void:
	if orders_left <= 0:
		_aim = Aim.INVALID
		_reason = REASON_NO_ORDERS
	elif verdict.get("valid", false):
		_aim = Aim.SNAPPED
		_reason = ""
	else:
		_aim = Aim.INVALID
		_reason = verdict.get("reason", "")


func _clear_aim() -> void:
	_aim = Aim.NONE
	_hex = NO_HEX
	_reason = ""


func _reset() -> void:
	_editing = false
	_was_editing = false
	_state = State.IDLE
	_id = &""
	_posture = &""
	_suppressed_hex = NO_HEX
	_elapsed = 0.0
	_clear_aim()


func _intent(type: StringName, details := {}) -> Dictionary:
	var intent := {"type": type}
	intent.merge(details)
	return intent
