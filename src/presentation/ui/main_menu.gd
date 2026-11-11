# gdlint: disable=max-public-methods
extends Control
## Main menu (TASK-084, TASK-124; layout of docs/design/operational_map/main_menu.html, variant A:
## logo and menu on the right over MenuBackdrop – the staff map breaking into the battle): Continue
## (the latest campaign save, TASK-094d), Start scenario, Operation (staff map, TASK-093a), Unit
## catalog and Settings. The scenario and the settings are separate pages of this scene, each with
## a Back button (Esc does the same).
## Presentation only: it switches scenes and the UI language (GameSettings stores the choice).

const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const CATALOG_SCENE := "res://scenes/ui/unit_catalog.tscn"
const STAFF_MAP_SCENE := "res://scenes/operational/staff_map.tscn"
const BUTTON_WIDTH := 340.0
const EDGE_MARGIN := 64.0  # gap between the menu column and the screen edge
const LOGO := preload("res://assets/branding/logo_light.png")
const SCENARIO_WIDTH := 860.0
const PREVIEW_SIZE := Vector2(480, 340)

## Where the language is stored (a test points it at a temp file).
var settings_path := GameSettings.PATH
## Where the campaign saves are (a test points it at a temp folder).
var save_dir := CampaignSaver.DIR
var _continue: Button  # main page: loads the latest campaign save
var _continue_note: Label  # why Continue is disabled / why the save did not load
var _continue_problem := ""  # translation key of the last failed load
var _scenario_name := BattleOptions.chosen(OS.get_cmdline_user_args())
var _start: Button  # main page: opens the scenario page
var _operation: Button  # main page: opens the operational staff map
var _catalog: Button
var _settings: Button
var _backdrop: MenuBackdrop
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
	Session.abandon()  # the menu is outside any campaign (TASK-094c); Continue loads a save
	_build()
	refresh_texts()
	refresh_continue()
	if is_inside_tree():
		_start.grab_focus()


func _notification(what: int) -> void:
	FramePacing.apply_notification(what)


## Current language button text: "LANGUAGE: ENGLISH".
func language_text() -> String:
	return _language.text


func continue_button() -> Button:
	return _continue


## The text under Continue ("" when it is enabled and nothing failed).
func continue_note() -> String:
	return _continue_note.text if _continue_note.visible else ""


## Enables Continue when a campaign save exists; otherwise the note says why not.
func refresh_continue() -> void:
	var has_save := CampaignSaver.latest(save_dir) != ""
	_continue.disabled = not has_save
	var key := _continue_problem if has_save else "MENU_CONTINUE_NONE"
	_continue_note.text = tr(key) if key != "" else ""
	_continue_note.visible = key != ""
	_continue_note.add_theme_color_override(
		&"font_color", UiPalette.DISABLED if _continue_problem != "" else UiPalette.HUD_MUTED
	)
	_continue.tooltip_text = _continue_note.text


## Continue: loads the latest save (validated by its replay) into Session and opens the staff map.
## False (the note says why, the menu stays) when there is no save or it cannot be loaded.
func continue_campaign() -> bool:
	var path := CampaignSaver.latest(save_dir)
	var loaded := CampaignSaver.load_campaign(path) if path != "" else {}
	if loaded.is_empty() or loaded["error"] != "":
		_continue_problem = "CAMPAIGN_LOAD_" + String(loaded.get("error", "unreadable")).to_upper()
		if not loaded.is_empty():
			push_warning("Cannot load %s: %s" % [path, loaded["detail"]])
		refresh_continue()
		return false
	_continue_problem = ""
	Session.resume(loaded["record"], loaded["simulation"])
	if is_inside_tree():
		get_tree().change_scene_to_file(STAFF_MAP_SCENE)
	return true


func start_button() -> Button:
	return _start


func operation_button() -> Button:
	return _operation


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
	_backdrop = MenuBackdrop.new()
	add_child(_backdrop)
	add_child(ScreenDecor.new())
	var main_column := _column(BUTTON_WIDTH)
	_main_page = main_column.get_parent()
	_build_main(main_column)
	var scenario_column := _column(SCENARIO_WIDTH)
	_scenario_page = scenario_column.get_parent()
	_build_scenarios(scenario_column)
	var settings_column := _column(BUTTON_WIDTH)
	_settings_page = settings_column.get_parent()
	_build_settings(settings_column)
	var audio := AudioDirector.create(self, null, null, 1.0)
	audio.settings = _sound  # the menu edits this dictionary: clicks follow mute and volume
	audio.hook_tree(self)
	show_page("main")


## A page: a column of `width` on the right of the screen over a gradient that fades the backdrop
## into the panel colour (docs/design/operational_map/main_menu.html, variant A). Returns the
## column; its
## parent is the page (shown / hidden by show_page).
func _column(width: float) -> VBoxContainer:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(UiPalette.PANEL_STRONG, 0.0), UiPalette.PANEL_STRONG])
	gradient.offsets = PackedFloat32Array([0.0, 0.26])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0)
	shade.texture = texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	shade.offset_left = -(width + EDGE_MARGIN + 96.0)
	shade.offset_right = 0.0
	page.add_child(shade)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	column.anchor_left = 1.0
	column.anchor_right = 1.0
	column.anchor_top = 0.5
	column.anchor_bottom = 0.5
	column.offset_left = -(width + EDGE_MARGIN)
	column.offset_right = -EDGE_MARGIN
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	page.add_child(column)
	return column


func _build_main(column: VBoxContainer) -> void:
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(
		BUTTON_WIDTH, BUTTON_WIDTH * LOGO.get_height() / LOGO.get_width()
	)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(logo)
	var hatch := HatchBar.new(UiPalette.AMBER, Vector2(BUTTON_WIDTH, 6), true)
	hatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(hatch)
	column.add_child(_spacer(26.0))
	_continue = _add_button(column, continue_campaign)
	_continue_note = MenuStyle.label("", HudTheme.display(600, 2), 13, UiPalette.HUD_MUTED)
	column.add_child(_continue_note)
	_start = _add_button(column, show_page.bind("scenario"))
	_operation = _add_button(column, _on_operation_pressed)
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
		var b := MenuStyle.plate("", true)
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
	var b := MenuStyle.plate("")
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
	_backdrop.refresh_texts()
	_continue.text = tr("MENU_CONTINUE").to_upper()
	_start.text = tr("Start scenario").to_upper()
	_operation.text = tr("Operation").to_upper()
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
	refresh_continue()


func _on_operation_pressed() -> void:
	get_tree().change_scene_to_file(STAFF_MAP_SCENE)


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
