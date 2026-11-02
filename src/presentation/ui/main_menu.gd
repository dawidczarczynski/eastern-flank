extends Control
## Main menu (TASK-084, TASK-124): Start scenario, Unit catalog and Settings. The scenario and the
## settings are separate pages of this scene, each with a Back button (Esc does the same).
## Presentation only: it switches scenes and the UI language (GameSettings stores the choice).

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const CATALOG_SCENE := "res://scenes/ui/unit_catalog.tscn"
const BUTTON_WIDTH := 340.0
const SCENARIO_WIDTH := 860.0
const PREVIEW_SIZE := Vector2(480, 340)
const TITLE_SIZE := 52

## Where the language is stored (a test points it at a temp file).
var settings_path := GameSettings.PATH
var _scenario_name := BattleOptions.chosen(OS.get_cmdline_user_args())
var _start: Button  # main page: opens the scenario page
var _catalog: Button
var _settings: Button
var _title: Label
var _main_page: Control
var _scenario_page: Control
var _settings_page: Control
var _scenario_buttons: Dictionary = {}  # scenario name -> Button
var _preview: ScenarioPreview
var _begin: Button  # scenario page: starts the battle
var _scenario_back: Button
var _scenario_title: Label
var _language: Button
var _settings_back: Button
var _settings_title: Label
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


func catalog_button() -> Button:
	return _catalog


func settings_button() -> Button:
	return _settings


func begin_button() -> Button:
	return _begin


func scenario_back_button() -> Button:
	return _scenario_back


func settings_back_button() -> Button:
	return _settings_back


func scenario_button(scenario_name: String) -> Button:
	return _scenario_buttons[scenario_name]


func preview() -> ScenarioPreview:
	return _preview


func selected_scenario() -> String:
	return _scenario_name


func language_button() -> Button:
	return _language


func mute_button() -> Button:
	return _mute


func master_slider() -> HSlider:
	return _master_slider


func ambient_slider() -> HSlider:
	return _ambient_slider


## The visible page: "main", "scenario" or "settings".
func page() -> String:
	if _scenario_page.visible:
		return "scenario"
	return "settings" if _settings_page.visible else "main"


func show_page(page_name: String) -> void:
	_main_page.visible = page_name == "main"
	_scenario_page.visible = page_name == "scenario"
	_settings_page.visible = page_name == "settings"
	if not is_inside_tree():
		return
	match page_name:
		"main":
			_start.grab_focus()
		"scenario":
			_begin.grab_focus()
		"settings":
			_settings_back.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		if page() != "main":
			show_page("main")
			get_viewport().set_input_as_handled()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = UiPalette.BG_APP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	add_child(ScreenDecor.new())
	_main_page = _page(BUTTON_WIDTH)
	_build_main(_main_page.get_child(0))
	_scenario_page = _page(SCENARIO_WIDTH)
	_build_scenarios(_scenario_page.get_child(0))
	_settings_page = _page(BUTTON_WIDTH)
	_build_settings(_settings_page.get_child(0))
	var audio := AudioDirector.create(self, null, null, 1.0)
	audio.settings = _sound  # the menu edits this dictionary: clicks follow mute and volume
	audio.hook_tree(self)
	show_page("main")


## A centred page holding one column of `width`; returns the page (the column is its child 0).
func _page(width: float) -> Control:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	column.custom_minimum_size = Vector2(width, 0)
	centre.add_child(column)
	return centre


func _build_main(column: VBoxContainer) -> void:
	_title = MenuStyle.label("", HudTheme.display(700, 4), TITLE_SIZE, UiPalette.HUD_TEXT)
	column.add_child(_title)
	var hatch := HatchBar.new(UiPalette.AMBER, Vector2(BUTTON_WIDTH, 6), true)
	hatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(hatch)
	column.add_child(_spacer(18.0))
	_start = _add_button(column, show_page.bind("scenario"))
	_catalog = _add_button(column, _on_catalog_pressed)
	_settings = _add_button(column, show_page.bind("settings"))


func _build_scenarios(column: VBoxContainer) -> void:
	_scenario_title = MenuStyle.label("", HudTheme.display(700, 4), 28, UiPalette.HUD_TEXT)
	column.add_child(_scenario_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	column.add_child(row)
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 8)
	list.custom_minimum_size = Vector2(BUTTON_WIDTH, 0)
	row.add_child(list)
	var group := ButtonGroup.new()
	for scenario_name in Scenario.NAMES:
		var b := MenuStyle.button("", true)
		b.button_group = group
		b.pressed.connect(_select_scenario.bind(scenario_name))
		list.add_child(b)
		_scenario_buttons[scenario_name] = b
	_preview = ScenarioPreview.new()
	_preview.custom_minimum_size = PREVIEW_SIZE
	row.add_child(_preview)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 12)
	column.add_child(buttons)
	_scenario_back = _add_button(buttons, show_page.bind("main"))
	_begin = _add_button(buttons, _on_begin_pressed)
	_select_scenario(_scenario_name)


func _build_settings(column: VBoxContainer) -> void:
	_settings_title = MenuStyle.label("", HudTheme.display(700, 4), 28, UiPalette.HUD_TEXT)
	column.add_child(_settings_title)
	_language = _add_button(column, _on_language_pressed)
	_mute = _add_button(column, _on_mute_pressed)
	_master_label = MenuStyle.label("", HudTheme.display(600, 2), 13, UiPalette.HUD_TEXT)
	column.add_child(_master_label)
	_master_slider = _add_slider(column, _sound["master"], _on_master_changed)
	_ambient_label = MenuStyle.label("", HudTheme.display(600, 2), 13, UiPalette.HUD_TEXT)
	column.add_child(_ambient_label)
	_ambient_slider = _add_slider(column, _sound["ambient"], _on_ambient_changed)
	column.add_child(_spacer(10.0))
	_settings_back = _add_button(column, show_page.bind("main"))


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
	_start.text = tr("Start scenario").to_upper()
	_catalog.text = tr("Unit catalog").to_upper()
	_settings.text = tr("Settings").to_upper()
	_scenario_title.text = tr("Start scenario").to_upper()
	for scenario_name: String in _scenario_buttons:
		var label: String = BattleOptions.LABELS.get(scenario_name, scenario_name)
		(_scenario_buttons[scenario_name] as Button).text = tr(label).to_upper()
	_begin.text = tr("Start").to_upper()
	_scenario_back.text = "‹ " + tr("Back").to_upper()
	_settings_title.text = tr("Settings").to_upper()
	_settings_back.text = "‹ " + tr("Back").to_upper()
	var locale := GameSettings.normalize(TranslationServer.get_locale())
	var native: String = GameSettings.LOCALE_NAMES.get(locale, locale)
	_language.text = ("%s: %s" % [tr("Language"), native]).to_upper()
	var state := tr("On") if not _sound["muted"] else tr("Off")
	_mute.text = ("%s: %s" % [tr("Sound"), state]).to_upper()
	_master_label.text = (
		("%s: %d%%" % [tr("Master volume"), roundi(_sound["master"] * 100.0)]).to_upper()
	)
	_ambient_label.text = (
		("%s: %d%%" % [tr("Ambient volume"), roundi(_sound["ambient"] * 100.0)]).to_upper()
	)


## Selects `scenario_name` in the list and shows its preview.
func _select_scenario(scenario_name: String) -> void:
	_scenario_name = scenario_name
	(_scenario_buttons[scenario_name] as Button).set_pressed_no_signal(true)
	_preview.show_scenario(scenario_name)


func _on_begin_pressed() -> void:
	BattleOptions.menu_choice = _scenario_name
	get_tree().change_scene_to_file(BATTLE_SCENE)


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
