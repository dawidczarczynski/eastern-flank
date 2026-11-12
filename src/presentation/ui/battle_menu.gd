class_name BattleMenu
extends Control
## The hamburger menu of the battle (same look and behaviour as the staff map's): the button in
## the top-left corner opens a window with SAVE (scenario battles only) and the exit row, which
## asks first. A campaign battle's exit is LEAVE BATTLE: the owner finishes the fight by
## auto-resolve from the state reached (Session.leave_battle); any other battle returns to the
## main menu. Holds no rules: emits `save_pressed` and `leave_confirmed`, the owner acts.

signal save_pressed
signal leave_confirmed

const CAMPAIGN_QUESTION := (
	"The battle is finished automatically from the positions reached and its result goes to "
	+ "the operation. Leave the battle?"
)
const MENU_QUESTION := "Leave the battle and return to the main menu?"

var _campaign: bool
var _button: StaffMapMenuButton
var _window: StaffMapMenuWindow
var _confirm: StaffMapExitConfirm


func _init(campaign := false, can_save := false) -> void:
	_campaign = campaign
	name = "BattleMenu"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_button = StaffMapMenuButton.new()
	_button.pressed.connect(toggle)
	add_child(_button)
	_window = StaffMapMenuWindow.new("LEAVE BATTLE" if campaign else "EXIT TO MAIN MENU", can_save)
	_window.save_pressed.connect(
		func() -> void:
			close()
			save_pressed.emit()
	)
	_window.exit_pressed.connect(request_exit)
	_window.close_requested.connect(func() -> void: close())
	add_child(_window)
	_confirm = StaffMapExitConfirm.new("LEAVE BATTLE" if campaign else "EXIT TO MAIN MENU")
	_confirm.exit_confirmed.connect(
		func() -> void:
			_confirm.close()
			leave_confirmed.emit()
	)
	_confirm.cancelled.connect(func() -> void: cancel_exit())
	add_child(_confirm)


func button() -> StaffMapMenuButton:
	return _button


func window() -> StaffMapMenuWindow:
	return _window


func confirm() -> StaffMapExitConfirm:
	return _confirm


## True while the menu or its question is on screen (the battle ignores the map then).
func is_open() -> bool:
	return _window.is_open() or _confirm.visible


## The hamburger / Esc with nothing to close: opens or closes the menu.
func toggle() -> void:
	if _window.is_open():
		close()
		return
	if _confirm.visible:
		return
	_window.open_centered(_viewport_size())
	_button.set_lit(true)


## Closes the menu; true when it was open.
func close() -> bool:
	var was_open := _window.close()
	_button.set_lit(false)
	return was_open


## The exit row: asks first.
func request_exit() -> void:
	close()
	_confirm.present_question(
		CAMPAIGN_QUESTION if _campaign else MENU_QUESTION,
		"LEAVE BATTLE" if _campaign else "EXIT",
		_viewport_size()
	)


## Dismisses the exit question; true when it was open.
func cancel_exit() -> bool:
	return _confirm.close()


## Esc: closes the question, then the menu; true when something was closed.
func close_topmost() -> bool:
	return cancel_exit() or close()


func _viewport_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
