extends TestCase
## The main menu (TASK-084): three buttons, the language switch re-translates at once and is stored.

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


func test_menu_has_start_language_and_catalog() -> void:
	assert_eq(_menu.start_button().text, "START OPERATION")
	assert_eq(_menu.language_button().text, "LANGUAGE: ENGLISH")
	assert_eq(_menu.catalog_button().text, "UNIT CATALOG")


func test_language_button_switches_en_to_pl_and_back() -> void:
	_menu.language_button().pressed.emit()
	assert_eq(TranslationServer.get_locale(), "pl")
	assert_eq(_menu.language_button().text, "JĘZYK: POLSKI")
	assert_eq(_menu.start_button().text, "ROZPOCZNIJ OPERACJĘ")
	assert_eq(_menu.catalog_button().text, "KATALOG JEDNOSTEK")
	_menu.language_button().pressed.emit()
	assert_eq(TranslationServer.get_locale(), "en")
	assert_eq(_menu.start_button().text, "START OPERATION")


func test_choice_is_stored_and_restored_on_the_next_start() -> void:
	_menu.language_button().pressed.emit()
	assert_eq(GameSettings.load_locale(TEMP), "pl")
	TranslationServer.set_locale("en")
	var next: Control = Menu.new()
	next.settings_path = TEMP
	next._ready()
	assert_eq(TranslationServer.get_locale(), "pl")
	assert_eq(next.start_button().text, "ROZPOCZNIJ OPERACJĘ")
	next.free()


func test_scene_targets_exist() -> void:
	assert_true(ResourceLoader.exists(Menu.BATTLE_SCENE))
	assert_true(ResourceLoader.exists(Menu.CATALOG_SCENE))
	assert_eq(
		ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/ui/main_menu.tscn"
	)
