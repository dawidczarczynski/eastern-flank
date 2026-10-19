extends TestCase

const UNITS_DIR := "res://data/units"
const CAVALRY := preload("res://data/units/cavalry.tres")
## Label above the unit = the abbreviation of its class, the same for every unit of the class.
const CLASS_SHORT_NAMES := {&"infantry": "INF", &"tank": "TNK", &"mlrs": "ART"}


func _definitions() -> Array[UnitDefinition]:
	var result: Array[UnitDefinition] = []
	for file in DirAccess.get_files_at(UNITS_DIR):
		if file.ends_with(".tres"):
			result.append(load(UNITS_DIR.path_join(file)) as UnitDefinition)
	return result


func test_unit_classes() -> void:
	var expected := {
		&"infantry": &"infantry",
		&"cavalry": &"tank",
		&"m1a2_sepv3": &"tank",
		&"rocket_artillery": &"mlrs",
	}
	var definitions := _definitions()
	assert_eq(definitions.size(), expected.size())
	for definition in definitions:
		assert_eq(definition.unit_class, expected.get(definition.id, &"?"), String(definition.id))


func test_short_name_is_the_class_abbreviation() -> void:
	for definition in _definitions():
		assert_eq(
			definition.short_name,
			CLASS_SHORT_NAMES.get(definition.unit_class, "?"),
			String(definition.id)
		)


func test_class_labels_translate() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("pl")
	assert_eq(String(TranslationServer.translate("TNK")), "CZOŁ")
	assert_eq(String(TranslationServer.translate("CLASS_TANK")), "Czołg")
	assert_eq(String(TranslationServer.translate("CLASS_MLRS")), "Artyleria rakietowa")
	assert_eq(String(TranslationServer.translate("CLASS_INFANTRY")), "Piechota")
	TranslationServer.set_locale("en")
	assert_eq(String(TranslationServer.translate("TNK")), "TNK")
	assert_eq(String(TranslationServer.translate("CLASS_TANK")), "Tank")
	TranslationServer.set_locale(previous)


## Poland's tank: real designation, generic tank stats until TASK-039a derives its own.
func test_m1a2_sepv3_definition() -> void:
	var tank: UnitDefinition = load("res://data/units/m1a2_sepv3.tres")
	var cavalry: UnitDefinition = CAVALRY
	assert_eq(tank.id, &"m1a2_sepv3")
	assert_eq(tank.display_name, "M1A2 SEPv3 Abrams")
	assert_eq(
		[tank.max_hp, tank.move_points, tank.attack, tank.defense, tank.attack_range],
		[cavalry.max_hp, cavalry.move_points, cavalry.attack, cavalry.defense, cavalry.attack_range]
	)
