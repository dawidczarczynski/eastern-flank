extends TestCase

const TEMP := "user://test_settings.cfg"

var _previous_locale: String


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


func test_missing_file_has_no_locale() -> void:
	assert_eq(GameSettings.load_locale(TEMP), "")


func test_locale_round_trips_through_the_file() -> void:
	assert_true(GameSettings.save_locale("pl", TEMP))
	assert_eq(GameSettings.load_locale(TEMP), "pl")
	assert_true(GameSettings.save_locale("en", TEMP))
	assert_eq(GameSettings.load_locale(TEMP), "en")


func test_unknown_locale_is_not_stored() -> void:
	assert_false(GameSettings.save_locale("xx", TEMP))
	assert_eq(GameSettings.load_locale(TEMP), "")


func test_normalize_strips_the_region() -> void:
	assert_eq(GameSettings.normalize("pl_PL"), "pl")
	assert_eq(GameSettings.normalize("en-US"), "en")
	assert_eq(GameSettings.normalize("de"), "")


func test_next_locale_cycles() -> void:
	assert_eq(GameSettings.next_locale("en"), "pl")
	assert_eq(GameSettings.next_locale("pl"), "en")
	assert_eq(GameSettings.next_locale("de"), "en", "an unknown locale starts at the first")


func test_set_locale_switches_the_game_and_stores_it() -> void:
	assert_eq(GameSettings.set_locale("pl", TEMP), "pl")
	assert_eq(TranslationServer.get_locale(), "pl")
	assert_eq(String(TranslationServer.translate("Language")), "Język")
	assert_eq(GameSettings.load_locale(TEMP), "pl")


func test_apply_saved_restores_the_stored_locale() -> void:
	GameSettings.save_locale("pl", TEMP)
	TranslationServer.set_locale("en")
	assert_eq(GameSettings.apply_saved(TEMP), "pl")
	assert_eq(TranslationServer.get_locale(), "pl")


func test_apply_saved_without_a_file_keeps_the_locale() -> void:
	TranslationServer.set_locale("en")
	assert_eq(GameSettings.apply_saved(TEMP), "en")
