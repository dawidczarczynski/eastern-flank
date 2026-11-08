class_name StaffMapPosturePicker
extends HBoxContainer
## Posture picker of the staff map (TASK-092d, look: docs/design/operational_map "Orders"):
## three buttons "[1] March  [2] Attack  [3] Defend" under the selected counter (keys 1 / 2 / 3).
## The display name of `advance` is "Attack" here (translation only). It only shows the posture
## it is given and emits `posture_chosen`; the staff map turns that into a command.

signal posture_chosen(posture: StringName)

const FONT_SIZE := 10
const HEIGHT := 22.0

var _buttons := {}  # posture id -> Button


func _init() -> void:
	name = "PosturePicker"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 3)
	for i in OperationalPosture.NAMES.size():
		var id := OperationalPosture.NAMES[i]
		var button := MenuStyle.button("", true)
		button.name = String(id).capitalize()
		button.custom_minimum_size = Vector2(0, HEIGHT)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override(&"font_size", FONT_SIZE)
		button.pressed.connect(posture_chosen.emit.bind(id))
		add_child(button)
		_buttons[id] = button
	hide()


## "[2] ATTACK": the caption of posture `id` (translated).
static func caption(id: StringName) -> String:
	var number := OperationalPosture.NAMES.find(id) + 1
	return "[%d] %s" % [number, TranslationServer.translate("POSTURE_" + String(id).to_upper())]


## Shows the picker with `current` pressed.
func show_posture(current: StringName) -> void:
	for id: StringName in _buttons:
		var button: Button = _buttons[id]
		button.text = caption(id).to_upper()
		button.set_pressed_no_signal(id == current)
	show()
	reset_size()


func pressed_posture() -> StringName:
	for id: StringName in _buttons:
		if (_buttons[id] as Button).button_pressed:
			return id
	return &""


func button(id: StringName) -> Button:
	return _buttons.get(id) as Button


func captions() -> PackedStringArray:
	var out := PackedStringArray()
	for id: StringName in OperationalPosture.NAMES:
		out.append((_buttons[id] as Button).text)
	return out
