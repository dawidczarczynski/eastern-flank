class_name StaffMapStrikeConfirm
extends FramedPanel
## The confirm card of a strike on the staff map (TASK-097b): the target, "means × salvo", the
## optional first line "Escalate to ..." of raise-and-strike, the escalation lines (the danger line
## in red) and Confirm / Cancel. Look: the contact notice frame. Pure view: StaffMapStrikeHud feeds
## it with StaffMapStrike.confirm_model() and listens to the signals.

signal confirmed
signal cancelled

const WIDTH := 400.0
const ALERT := Color("#e07c5e")

var _title: Label
var _means: Label
var _raise: Label
var _lines: VBoxContainer
var _confirm: Button
var _cancel: Button


func _init() -> void:
	super()
	name = "StrikeConfirm"
	mouse_filter = Control.MOUSE_FILTER_STOP
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = Vector2(WIDTH, 0)
	chamfers = Vector4(0, 16, 0, 16)
	padding = Vector2(16, 14)
	tab_color = ALERT
	line_color = Color(ALERT, 0.45)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 8)
	add_child(column)
	_title = MenuStyle.label("", HudTheme.display(700, 1), 22, UiPalette.HUD_TEXT)
	_title.name = "Title"
	column.add_child(_title)
	_means = MenuStyle.label("", HudTheme.mono(600, 0), 13, UiPalette.AMBER)
	_means.name = "Means"
	column.add_child(_means)
	_raise = MenuStyle.label("", HudTheme.mono(700, 0), 11, UiPalette.AMBER)
	_raise.name = "RaiseLine"
	_raise.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_raise.custom_minimum_size = Vector2(WIDTH - 34, 0)
	column.add_child(_raise)
	_lines = VBoxContainer.new()
	_lines.name = "Lines"
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override(&"separation", 4)
	column.add_child(_lines)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	column.add_child(row)
	_confirm = MenuStyle.button("")
	_confirm.name = "Confirm"
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.pressed.connect(func() -> void: confirmed.emit())
	row.add_child(_confirm)
	_cancel = MenuStyle.button("")
	_cancel.name = "Cancel"
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel.pressed.connect(func() -> void: cancelled.emit())
	row.add_child(_cancel)
	StaffMapCloseButton.attach(self).pressed.connect(func() -> void: cancelled.emit())
	hide()


## Shows the card for a StaffMapStrike.confirm_model().
func present(model: Dictionary) -> void:
	tab_text = tr("CONFIRM STRIKE").to_upper()
	_title.text = (model["title"] as String).to_upper()
	_means.text = (model["means_line"] as String).to_upper()
	_raise.text = model["raise_line"]
	_raise.visible = _raise.text != ""
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	for line: Dictionary in model["lines"]:
		var danger: bool = line["danger"]
		var label := MenuStyle.label(
			line["text"],
			HudTheme.mono(600 if danger else 500, 0),
			11,
			ALERT if danger else UiPalette.HUD_TEXT
		)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(WIDTH - 34, 0)
		_lines.add_child(label)
	_confirm.text = (tr("CONFIRM") + "  [ENTER]").to_upper()
	_cancel.text = (tr("CANCEL") + "  [ESC]").to_upper()
	show()
	reset_size()


func title_text() -> String:
	return _title.text


func means_text() -> String:
	return _means.text


func raise_text() -> String:
	return _raise.text if _raise.visible else ""


## The escalation lines as shown, in order.
func line_texts() -> Array[String]:
	var texts: Array[String] = []
	for child in _lines.get_children():
		if not child.is_queued_for_deletion():
			texts.append((child as Label).text)
	return texts


func press_confirm() -> void:
	_confirm.pressed.emit()


func press_cancel() -> void:
	_cancel.pressed.emit()
