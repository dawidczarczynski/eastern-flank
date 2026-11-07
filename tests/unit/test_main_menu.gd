extends TestCase
## The main menu (TASK-084, TASK-124): three buttons, two pages, language switch re-translates.

const Menu := preload("res://src/presentation/ui/main_menu.gd")
const TEMP := "user://test_menu_settings.cfg"

var _previous_locale: String
var _menu: Control


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))
	TranslationServer.set_locale("en")
	_menu = Menu.new()
	_menu.settings_path = TEMP
	_menu._ready()


func after_each() -> void:
	_menu.free()
	TranslationServer.set_locale(_previous_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


func test_menu_has_start_catalog_and_settings() -> void:
	assert_eq(_menu.start_button().text, "START SCENARIO")
	assert_eq(_menu.catalog_button().text, "UNIT CATALOG")
	assert_eq(_menu.settings_button().text, "SETTINGS")
	assert_eq(_menu.page(), "main")


func test_scenario_and_settings_pages_open_and_go_back() -> void:
	_menu.start_button().pressed.emit()
	assert_eq(_menu.page(), "scenario")
	_menu.scenario_back_button().pressed.emit()
	assert_eq(_menu.page(), "main")
	_menu.settings_button().pressed.emit()
	assert_eq(_menu.page(), "settings")
	_menu.settings_back_button().pressed.emit()
	assert_eq(_menu.page(), "main")


func test_language_button_switches_en_to_pl_and_back() -> void:
	assert_eq(_menu.language_button().text, "LANGUAGE: ENGLISH")
	_menu.language_button().pressed.emit()
	assert_eq(TranslationServer.get_locale(), "pl")
	assert_eq(_menu.language_button().text, "JĘZYK: POLSKI")
	assert_eq(_menu.start_button().text, "ROZPOCZNIJ SCENARIUSZ")
	assert_eq(_menu.catalog_button().text, "KATALOG JEDNOSTEK")
	assert_eq(_menu.settings_button().text, "USTAWIENIA")
	_menu.language_button().pressed.emit()
	assert_eq(TranslationServer.get_locale(), "en")
	assert_eq(_menu.start_button().text, "START SCENARIO")


func test_choice_is_stored_and_restored_on_the_next_start() -> void:
	_menu.language_button().pressed.emit()
	assert_eq(GameSettings.load_locale(TEMP), "pl")
	TranslationServer.set_locale("en")
	var next: Control = Menu.new()
	next.settings_path = TEMP
	next._ready()
	assert_eq(TranslationServer.get_locale(), "pl")
	assert_eq(next.start_button().text, "ROZPOCZNIJ SCENARIUSZ")
	next.free()


func test_scene_targets_exist() -> void:
	assert_true(ResourceLoader.exists(Menu.BATTLE_SCENE))
	assert_true(ResourceLoader.exists(Menu.CATALOG_SCENE))
	assert_eq(
		ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/ui/main_menu.tscn"
	)


func test_selecting_a_scenario_updates_the_preview_and_start_stores_the_choice() -> void:
	BattleOptions.menu_choice = ""
	assert_eq(_menu.selected_scenario(), "default_battle")
	assert_eq(_menu.scenario_button("default_battle").text, "IRON SHORE")
	_menu.scenario_button("suwalki_battle").pressed.emit()
	assert_eq(_menu.selected_scenario(), "suwalki_battle")
	assert_eq(_menu.preview().scenario(), "suwalki_battle")
	assert_eq(BattleOptions.chosen(PackedStringArray()), "default_battle")
	BattleOptions.menu_choice = "suwalki_battle"
	assert_eq(BattleOptions.chosen(PackedStringArray()), "suwalki_battle")
	BattleOptions.menu_choice = ""


func test_preview_geometry_is_built_for_every_scenario_and_cached() -> void:
	for scenario_name in Scenario.NAMES:
		var data := ScenarioPreview.geometry(scenario_name)
		assert_true((data["hexes"] as Array).size() > 0)
		assert_true((data["bounds"] as Rect2).size.x > 0.0)
		assert_true(ScenarioPreview.geometry(scenario_name) == data)


func test_sound_controls_persist() -> void:
	assert_eq(_menu.mute_button().text, "SOUND: ON")
	_menu.mute_button().pressed.emit()
	assert_eq(_menu.mute_button().text, "SOUND: OFF")
	_menu.master_slider().value_changed.emit(0.4)
	var stored := GameSettings.load_sound(TEMP)
	assert_true(stored["muted"])
	assert_eq(stored["master"], 0.4)
	SoundMix.apply(GameSettings.load_sound("user://does_not_exist.cfg"))  # restore the buses


func test_operation_button_opens_the_staff_map_entry() -> void:
	assert_eq(_menu.operation_button().text, "OPERATION")
	assert_eq(_menu.page(), "main")
	_menu.language_button().pressed.emit()
	assert_eq(_menu.operation_button().text, "OPERACJA")
