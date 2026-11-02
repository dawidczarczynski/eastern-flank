extends Control
## Main menu (TASK-084): Start operation, Scenario, Language and Unit catalog. First scene.
## Presentation only: it switches scenes and the UI language (GameSettings stores the choice).

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const CATALOG_SCENE := "res://scenes/ui/unit_catalog.tscn"
const BUTTON_WIDTH := 340.0
const TITLE_SIZE := 52

## Where the language is stored (a test points it at a temp file).
var settings_path := GameSettings.PATH
var _start: Button
var _scenario: Button
var _scenario_name := BattleOptions.chosen(OS.get_cmdline_user_args())
var _language: Button
var _catalog: Button
var _title: Label
var _sound: Dictionary = {}  # GameSettings.load_sound(): master, ambient, muted
var _mute: Button
var _master_label: Label
var _master_slider: HSlider
var _ambient_label: Label
var _ambient_slider: HSlider


func _ready() -> void:
	Engine.max_fps = FramePacing.max_fps(true)
	GameSettings.apply_saved(settings_path)
	_sound = GameSettings.load_sound(settings_path)
	SoundMix.apply(_sound)
	_build()
	refresh_texts()
	if is_inside_tree():
		_start.grab_focus()


func _notification(what: int) -> void:
	FramePacing.apply_notification(what)


## Current language button text: "LANGUAGE: ENGLISH".
func language_text() -> String:
	return _language.text


func start_button() -> Button:
	return _start


func scenario_button() -> Button:
	return _scenario


func language_button() -> Button:
	return _language


func catalog_button() -> Button:
	return _catalog


func mute_button() -> Button:
	return _mute


func master_slider() -> HSlider:
	return _master_slider


func ambient_slider() -> HSlider:
	return _ambient_slider


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = UiPalette.BG_APP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	add_child(ScreenDecor.new())
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	column.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	centre.add_child(column)
	_title = MenuStyle.label("", HudTheme.display(700, 4), TITLE_SIZE, UiPalette.HUD_TEXT)
	column.add_child(_title)
	var hatch := HatchBar.new(UiPalette.AMBER, Vector2(BUTTON_WIDTH, 6), true)
	hatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(hatch)
	column.add_child(_spacer(18.0))
	_start = _add_button(column, _on_start_pressed)
	_scenario = _add_button(column, _on_scenario_pressed)
	_language = _add_button(column, _on_language_pressed)
	_catalog = _add_button(column, _on_catalog_pressed)
	column.add_child(_spacer(10.0))
	_mute = _add_button(column, _on_mute_pressed)
	_master_label = MenuStyle.label("", HudTheme.display(600, 2), 13, UiPalette.HUD_TEXT)
	column.add_child(_master_label)
	_master_slider = _add_slider(column, _sound["master"], _on_master_changed)
	_ambient_label = MenuStyle.label("", HudTheme.display(600, 2), 13, UiPalette.HUD_TEXT)
	column.add_child(_ambient_label)
	_ambient_slider = _add_slider(column, _sound["ambient"], _on_ambient_changed)
	var audio := AudioDirector.create(self, null, null, 1.0)
	audio.settings = _sound  # the menu edits this dictionary: clicks follow mute and volume
	audio.hook_tree(self)


func _add_button(parent: Control, handler: Callable) -> Button:
	var b := MenuStyle.button("")
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _add_slider(parent: Control, value: float, handler: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 24)
	slider.value_changed.connect(handler)
	parent.add_child(slider)
	return slider


func _spacer(height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


## Sets every text in the current language (also after a language switch).
func refresh_texts() -> void:
	_title.text = "EASTERN FLANK"
	_start.text = tr("Start operation").to_upper()
	var label: String = BattleOptions.LABELS.get(_scenario_name, _scenario_name)
	_scenario.text = ("%s: %s" % [tr("Scenario"), tr(label)]).to_upper()
	var locale := GameSettings.normalize(TranslationServer.get_locale())
	var native: String = GameSettings.LOCALE_NAMES.get(locale, locale)
	_language.text = ("%s: %s" % [tr("Language"), native]).to_upper()
	_catalog.text = tr("Unit catalog").to_upper()
	var state := tr("On") if not _sound["muted"] else tr("Off")
	_mute.text = ("%s: %s" % [tr("Sound"), state]).to_upper()
	_master_label.text = (
		("%s: %d%%" % [tr("Master volume"), roundi(_sound["master"] * 100.0)]).to_upper()
	)
	_ambient_label.text = (
		("%s: %d%%" % [tr("Ambient volume"), roundi(_sound["ambient"] * 100.0)]).to_upper()
	)


func _on_start_pressed() -> void:
	BattleOptions.menu_choice = _scenario_name
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _on_scenario_pressed() -> void:
	_scenario_name = BattleOptions.next_scenario(_scenario_name)
	refresh_texts()


func _on_language_pressed() -> void:
	GameSettings.set_locale(GameSettings.next_locale(TranslationServer.get_locale()), settings_path)
	refresh_texts()


func _on_catalog_pressed() -> void:
	get_tree().change_scene_to_file(CATALOG_SCENE)


func _on_mute_pressed() -> void:
	_sound["muted"] = not _sound["muted"]
	_store_sound()


func _on_master_changed(value: float) -> void:
	_sound["master"] = value
	_store_sound()


func _on_ambient_changed(value: float) -> void:
	_sound["ambient"] = value
	_store_sound()


func _store_sound() -> void:
	SoundMix.apply(_sound)
	GameSettings.save_sound(_sound, settings_path)
	refresh_texts()
