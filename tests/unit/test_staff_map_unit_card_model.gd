extends TestCase
## Unit info tag / card model (TASK-151): own formations in full, hostile ones only what intel
## allows, and the brief / chip decision.

const Fixtures := preload("res://tests/fixtures.gd")

var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


func test_own_formation_shows_strength_posture_and_order() -> void:
	var f := Fixtures.formation(&"a", 0, Vector2i.ZERO, 30, 40)
	f.posture = &"march"
	var m := StaffMapUnitCardModel.build(f, 0)
	assert_true(m["own"])
	assert_true(m["known"])
	assert_eq(m["lit"], 4)
	assert_eq(m["strength_text"], "30 / 40")
	assert_eq(m["posture_text"], "MARCH")
	assert_eq(m["order_text"], StaffMapUnitCardModel.order_text(f))
	assert_eq(m["side_text"], "OWN")


func test_hostile_formation_shows_only_the_estimate() -> void:
	var f := Fixtures.formation(&"b", 1, Vector2i.ZERO, 12, 40)
	f.posture = &"advance"
	f.order = FormationOrder.new(Vector2i(2, 0))
	var m := StaffMapUnitCardModel.build(f, 0)
	assert_false(m["own"])
	assert_false(m["known"])
	assert_eq(m["lit"], 0, "no gauge")
	assert_eq(m["strength"], -1, "the real strength never reaches the card")
	assert_eq(m["max_strength"], -1)
	assert_eq(m["posture_text"], "?")
	assert_eq(m["order_text"], "?")
	assert_eq(m["side_text"], "HOSTILE")
	assert_false(String(m["strength_text"]).contains("12"))


func test_the_viewer_decides_who_is_hostile() -> void:
	var f := Fixtures.formation(&"c", 1)
	assert_true(StaffMapUnitCardModel.build(f, 1)["own"])


func test_order_text_names_the_destination() -> void:
	var f := Fixtures.formation(&"d", 0)
	f.order = FormationOrder.new(Vector2i(3, 0))
	var namer := func(_c: Vector2i) -> String: return "Kaliningrad"
	assert_eq(StaffMapUnitCardModel.order_text(f, namer), "→ KALININGRAD")
	assert_true(StaffMapUnitCardModel.order_text(f).begins_with("→ "))


func test_abbreviate_leaves_a_name_that_fits() -> void:
	assert_eq(
		StaffMapUnitCardModel.abbreviate("2ND TANK BATTALION", 24, "en"), "2ND TANK BATTALION"
	)


func test_abbreviate_shortens_only_as_much_as_needed() -> void:
	var name := "1ST MECHANISED BATTALION"
	assert_eq(StaffMapUnitCardModel.abbreviate(name, 20, "en"), "1ST MECH BATTALION")
	assert_eq(StaffMapUnitCardModel.abbreviate(name, 12, "en"), "1ST MECH BN")


func test_abbreviate_keeps_unknown_words() -> void:
	assert_eq(
		StaffMapUnitCardModel.abbreviate("PARTISAN DETACHMENT GROUP", 10, "en"),
		"PARTISAN DETACHMENT GROUP"
	)


func test_polish_abbreviations_apply_only_until_the_name_fits() -> void:
	var name := "3. BATALION ZMECHANIZOWANY"
	assert_eq(StaffMapUnitCardModel.abbreviate(name, 26, "pl"), name)
	assert_eq(StaffMapUnitCardModel.abbreviate(name, 22, "pl"), "3. BATALION ZMECH")
	assert_eq(StaffMapUnitCardModel.abbreviate(name, 12, "pl"), "3. BAON ZMECH")
	assert_eq(
		StaffMapUnitCardModel.abbreviate("1. BATALION PIECHOTY ZMOTORYZOWANEJ", 22, "pl"),
		"1. BAON PIECHOTY ZMOT"
	)
	assert_eq(
		StaffMapUnitCardModel.abbreviate("15. BRYGADA ZMECHANIZOWANA", 20, "pl"),
		"15. BRYGADA ZMECH"
	)
	assert_eq(StaffMapUnitCardModel.abbreviate("16. PUŁK ARTYLERII", 10, "pl"), "16. PUŁK ART")


func test_the_language_decides_which_table_is_used() -> void:
	assert_eq(StaffMapUnitCardModel.abbreviate("1ST BATTALION", 5, "pl"), "1ST BATTALION")
	assert_eq(StaffMapUnitCardModel.abbreviate("1. BATALION", 5, "en"), "1. BATALION")
	TranslationServer.set_locale("pl")
	assert_eq(StaffMapUnitCardModel.abbreviate("1. BATALION", 5), "1. BAON", "default = locale")
	TranslationServer.set_locale("en")
	assert_eq(StaffMapUnitCardModel.abbreviate("1. BATALION", 5), "1. BATALION")


func test_upper_handles_polish_diacritics() -> void:
	assert_eq(StaffMapUnitCardModel.upper("pułk łączności żółć"), "PUŁK ŁĄCZNOŚCI ŻÓŁĆ")
	assert_eq(StaffMapUnitCardModel.upper("Batalion Czołgów"), "BATALION CZOŁGÓW")


func test_a_long_name_is_shortened_to_the_strip_title() -> void:
	var f := Fixtures.formation(&"e", 0)
	f.display_name = "1st Lithuanian Mechanised Battalion"
	var m := StaffMapUnitCardModel.build(f, 0)
	assert_true(String(m["name"]).length() <= StaffMapUnitCardModel.NAME_MAX_CHARS)
	assert_eq(m["name"], "1ST LITHUANIAN MECH BN")


func test_abbreviate_polish_genitive_squad_name_fits_the_strip() -> void:
	var name := "DRUŻYNA PIECHOTY ZMECHANIZOWANEJ"
	var short := StaffMapUnitCardModel.abbreviate(name, StaffMapUnitCardModel.NAME_MAX_CHARS, "pl")
	assert_eq(short, "DRUŻYNA PIECHOTY ZMECH")
