class_name StaffMapWeaponCard
extends VBoxContainer
## The detail card of the strike panel (TASK-141b, strike_panel.html variant A): a 388 x 140 model
## stage (the 3D turntable of TASK-144, or the class glyph at 96 px while the weapon has no model),
## four chips (RANGE, SALVO, ACCURACY, INTERCEPT) and the platform line. Shows one StaffMapStrike
## means entry at a time (`show_entry`); a weapon at stock 0 is shown dimmed with "arrives only
## from allies".

const STAGE_SIZE := Vector2(388, 140)
const FLOOR := Color("#10130e")
const FLOOR_LIGHT := Color("#262c21")
const GLYPH_PX := 96.0
const DIM := 0.5

var _stage: Control
var _turntable: WeaponTurntable
var _glyph: StaffMapWeaponGlyph
var _tag: Label
var _chips := {}  # key -> value Label
var _platform: Label
var _shown: StringName = &""


func _init() -> void:
	name = "WeaponCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 8)
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.custom_minimum_size = STAGE_SIZE
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.draw.connect(_draw_stage)
	add_child(_stage)
	_turntable = WeaponTurntable.new()
	_turntable.name = "Turntable"
	_turntable.position = Vector2.ZERO
	_stage.add_child(_turntable)
	_glyph = StaffMapWeaponGlyph.new(&"missile", GLYPH_PX)
	_glyph.name = "ClassGlyph"
	_glyph.stroke = 1.2
	_glyph.colour = UiPalette.HUD_MUTED
	_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(_glyph)
	_tag = MenuStyle.label("", HudTheme.display(600, 2), 9, UiPalette.HUD_MUTED)
	_tag.name = "Tag"
	_tag.position = Vector2(8, 5)
	_stage.add_child(_tag)
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override(&"separation", 6)
	add_child(chips)
	for key: String in ["RANGE", "SALVO", "ACCURACY", "INTERCEPT"]:
		chips.add_child(_chip(key))
	_platform = MenuStyle.label("", HudTheme.mono(500, 0), 10, UiPalette.HUD_MUTED)
	_platform.name = "Platform"
	_platform.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_platform.custom_minimum_size = Vector2(STAGE_SIZE.x, 0)
	add_child(_platform)


func turntable() -> WeaponTurntable:
	return _turntable


## The means id shown now (&"" before the first `show_entry`).
func shown_id() -> StringName:
	return _shown


## True while the 3D model is shown, false for the class glyph stand-in.
func shows_model() -> bool:
	return _turntable.visible


func chip_text(key: String) -> String:
	return (_chips[key] as Label).text


func platform_text() -> String:
	return _platform.text


func tag_text() -> String:
	return _tag.text


## Shows a StaffMapStrike.means_list entry.
func show_entry(entry: Dictionary) -> void:
	_shown = entry["id"]
	var has_model := _turntable.show_weapon(_shown)
	_turntable.visible = has_model
	_glyph.visible = not has_model
	_glyph.glyph = entry["glyph"]
	_stage.modulate = Color(DIM, DIM, DIM) if not entry["enabled"] else Color.WHITE
	var tag := entry["designation"] as String
	tag += (" · " if tag != "" else "") + (entry["class_text"] as String)
	_tag.text = tag.to_upper()
	_set_chip("RANGE", entry["range_text"])
	_set_chip("SALVO", "≤ %d" % entry["max_salvo"])
	_set_chip("ACCURACY", "%d %%" % entry["accuracy"])
	_set_chip("INTERCEPT", entry["intercept_word"])
	_platform.text = (
		tr("Arrives only from allies (support package)")
		if not entry["enabled"]
		else _capitalised(tr(entry["platform"]))
	)
	_platform.tooltip_text = entry["intercept_text"]
	_stage.queue_redraw()


func _chip(key: String) -> Control:
	var chip := PanelContainer.new()
	chip.name = key.capitalize()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := MenuStyle.box(UiPalette.CARD, UiPalette.CARD_EDGE)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override(&"panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 0)
	chip.add_child(column)
	column.add_child(MenuStyle.label(tr(key), HudTheme.display(600, 1), 9, UiPalette.HUD_MUTED))
	var value := MenuStyle.label("", HudTheme.mono(600, 0), 13, UiPalette.HUD_TEXT)
	value.name = "Value"
	column.add_child(value)
	_chips[key] = value
	return chip


func _set_chip(key: String, text: String) -> void:
	(_chips[key] as Label).text = text.to_upper()


static func _capitalised(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else ""


func _draw_stage() -> void:
	var rect := Rect2(Vector2.ZERO, _stage.size)
	_stage.draw_rect(rect, FLOOR)
	# A soft lit floor under the model: a flat ellipse near the bottom.
	_stage.draw_set_transform(
		Vector2(rect.size.x / 2.0, rect.size.y * 0.88), 0.0, Vector2(1.0, 0.18)
	)
	_stage.draw_circle(Vector2.ZERO, rect.size.x * 0.34, Color(FLOOR_LIGHT, 0.7))
	_stage.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_stage.draw_rect(rect, UiPalette.CARD_EDGE, false, 1.0)
