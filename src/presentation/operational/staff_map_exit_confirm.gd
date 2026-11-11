class_name StaffMapExitConfirm
extends StaffMapWindow
## Confirmation before the staff map leaves the operation for the main menu. Centred window (the
## strike confirm frame): "Leave the operation?" and, when the operation has changed since the last
## save, "Progress since the last save will be lost." with SAVE AND EXIT / EXIT WITHOUT SAVING /
## CANCEL; with nothing to lose just EXIT / CANCEL. Holds no rules: emits `save_and_exit`,
## `exit_confirmed` and `cancelled` (also on the X); the owner acts.

signal save_and_exit
signal exit_confirmed
signal cancelled

const WIDTH := 400.0

var _message: Label
var _save_exit: Button
var _exit: Button
var _cancel: Button


func _init() -> void:
	super(tr("EXIT OPERATION").to_upper())
	name = "ExitConfirm"
	custom_minimum_size = Vector2(WIDTH, 0)
	padding = Vector2(16, 14)
	close_requested.connect(func() -> void: cancelled.emit())
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 10)
	add_child(column)
	_message = MenuStyle.label("", HudTheme.mono(600, 0), 13, UiPalette.HUD_TEXT)
	_message.name = "Message"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(WIDTH - 34, 0)
	column.add_child(_message)
	_save_exit = _button(column, "SaveAndExit", tr("SAVE AND EXIT"))
	_save_exit.pressed.connect(func() -> void: save_and_exit.emit())
	_exit = _button(column, "Exit", tr("EXIT"))
	_exit.pressed.connect(func() -> void: exit_confirmed.emit())
	_cancel = _button(column, "Cancel", tr("CANCEL"))
	_cancel.pressed.connect(func() -> void: cancelled.emit())


## Shows the question for an operation with (`unsaved`) or without changes since the last save,
## centred in a viewport `viewport` wide and high.
func present(unsaved: bool, viewport: Vector2) -> void:
	_message.text = (
		tr("Progress since the last save will be lost. Save before leaving?")
		if unsaved
		else tr("Leave the operation and return to the main menu?")
	)
	_save_exit.visible = unsaved
	_exit.text = (tr("EXIT WITHOUT SAVING") if unsaved else tr("EXIT")).to_upper()
	show()
	reset_size()
	position = ((viewport - size) / 2.0).floor()


func save_and_exit_button() -> Button:
	return _save_exit


func exit_button() -> Button:
	return _exit


func cancel_button() -> Button:
	return _cancel


func message() -> String:
	return _message.text


func _button(column: VBoxContainer, node_name: String, text: String) -> Button:
	var b := MenuStyle.button(text)
	b.name = node_name
	b.focus_mode = Control.FOCUS_NONE
	column.add_child(b)
	return b
