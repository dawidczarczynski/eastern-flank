class_name OperationLabel
extends VBoxContainer
## "■ OP. <NAME>" above the terrain card (TASK-079): amber mono text over a thin 150×3 hatch.
## Hidden while the operation name is empty. Ignores the mouse.

var _label: Label


func _init() -> void:
	name = "OperationLabel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_theme_constant_override(&"separation", 5)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override(&"font", HudTheme.mono(600, 2))
	_label.add_theme_font_size_override(&"font_size", 11)
	_label.add_theme_color_override(&"font_color", UiPalette.AMBER)
	add_child(_label)
	var hatch := HatchBar.new(UiPalette.AMBER, Vector2(150, 3))
	hatch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(hatch)
	hide()


## `operation_name` is the untranslated GameState.operation_name.
func set_operation(operation_name: String) -> void:
	visible = operation_name != ""
	_label.text = "■ %s %s" % [tr("OP."), tr(operation_name)]
	_label.text = _label.text.to_upper()
