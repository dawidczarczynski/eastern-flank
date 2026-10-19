extends TestCase

const FACTIONS_DIR := "res://data/factions"
const INFANTRY := preload("res://data/units/infantry.tres")
const CAVALRY := preload("res://data/units/cavalry.tres")
const ARTILLERY := preload("res://data/units/rocket_artillery.tres")
const ABRAMS := preload("res://data/units/m1a2_sepv3.tres")


## Every .tres in data/factions (headless runs from the source tree, no .remap files).
func _faction_files() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(FACTIONS_DIR)
	assert_true(dir != null, "cannot open " + FACTIONS_DIR)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.ends_with(".tres"):
			result.append(FACTIONS_DIR.path_join(file))
	return result


func test_poland_and_russia_load_via_registry() -> void:
	var poland := FactionRegistry.get_faction(&"poland")
	var russia := FactionRegistry.get_faction(&"russia")
	assert_true(poland != null and russia != null)
	if poland == null or russia == null:
		return
	assert_eq(poland.display_name, "Poland")
	assert_eq(poland.short_name, "PL")
	assert_eq(poland.color, Color("#5b93d6"))
	assert_eq(poland.ink_color, Color("#0f1a26"))
	assert_eq(poland.vest_color, Color("#3d4529"))
	assert_eq(russia.display_name, "Russia")
	assert_eq(russia.short_name, "RU")
	assert_eq(russia.color, Color("#d76a52"))
	assert_eq(russia.ink_color, Color("#2a110b"))
	assert_eq(russia.vest_color, Color("#5d5840"))


func test_camo_values() -> void:
	var expected := {
		&"poland": PackedColorArray([Color("#4c5632"), Color("#3b3325"), Color("#22251d")]),
		&"russia": PackedColorArray([Color("#8a7f5a"), Color("#6b6446"), Color("#a89c76")]),
	}
	for faction_id: StringName in expected:
		assert_eq(FactionRegistry.get_faction(faction_id).camo, expected[faction_id])


func test_unknown_faction_is_null() -> void:
	assert_eq(FactionRegistry.get_faction(&"atlantis"), null)
	assert_false(FactionRegistry.has_faction(&"atlantis"))
	assert_true(FactionRegistry.has_faction(&"poland"))


func test_registry_ids_and_order() -> void:
	assert_eq(FactionRegistry.ids(), [&"poland", &"russia"] as Array[StringName])
	assert_eq(FactionRegistry.all().size(), 2)
	assert_eq(FactionRegistry.DEFAULT_IDS, [&"poland", &"russia"] as Array[StringName])


func test_every_faction_file_is_registered_with_a_unique_id() -> void:
	var files := _faction_files()
	assert_eq(files.size(), FactionRegistry.all().size(), "a .tres missing from _PATHS?")
	var seen := {}
	for path in files:
		var faction := load(path) as FactionDefinition
		assert_true(faction != null, "%s is not a FactionDefinition" % path)
		if faction == null:
			continue
		assert_false(seen.has(faction.id), "duplicate faction id '%s'" % faction.id)
		seen[faction.id] = true
		assert_true(FactionRegistry.get_faction(faction.id) == faction, "%s registered" % path)


func test_every_faction_is_complete() -> void:
	for faction in FactionRegistry.all():
		assert_false(faction.display_name.is_empty(), "%s display_name" % faction.id)
		var letters := faction.short_name.length()
		assert_true(letters >= 2 and letters <= 3, "%s short_name" % faction.id)
		assert_eq(faction.camo.size(), 3, "%s camo" % faction.id)
		assert_false(faction.roster.is_empty(), "%s roster" % faction.id)
		for entry: Variant in faction.roster:
			assert_true(entry is UnitDefinition, "%s roster entry %s" % [faction.id, str(entry)])


func test_rosters_hold_the_current_unit_types() -> void:
	assert_eq(
		_ids(FactionRegistry.get_faction(&"poland").roster),
		[&"infantry", &"m1a2_sepv3", &"rocket_artillery"]
	)
	assert_eq(
		_ids(FactionRegistry.get_faction(&"russia").roster),
		[&"infantry", &"cavalry", &"rocket_artillery"]
	)
	assert_eq(FactionRegistry.get_faction(&"poland").find_unit(&"m1a2_sepv3"), ABRAMS)
	assert_eq(FactionRegistry.get_faction(&"russia").find_unit(&"cavalry"), CAVALRY)


func test_default_forces() -> void:
	var poland := FactionRegistry.get_faction(&"poland")
	var russia := FactionRegistry.get_faction(&"russia")
	assert_eq(
		_ids(poland.default_force), [&"infantry", &"m1a2_sepv3", &"infantry", &"rocket_artillery"]
	)
	assert_eq(
		_ids(russia.default_force), [&"infantry", &"cavalry", &"infantry", &"rocket_artillery"]
	)
	for faction in FactionRegistry.all():
		for entry: UnitDefinition in faction.default_force:
			assert_true(faction.has_unit(entry), "%s fields %s" % [faction.id, entry.id])


func _ids(definitions: Array[UnitDefinition]) -> Array[StringName]:
	var result: Array[StringName] = []
	for definition in definitions:
		result.append(definition.id if definition != null else &"<null>")
	return result


func test_has_unit_compares_unit_ids() -> void:
	var faction := FactionDefinition.new()
	faction.roster = [INFANTRY]
	assert_true(faction.has_unit(INFANTRY))
	assert_false(faction.has_unit(CAVALRY))
	assert_false(faction.has_unit(null))
	assert_eq(faction.find_unit(&"cavalry"), null)


func test_translations() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("pl")
	assert_eq(String(TranslationServer.translate("Poland")), "Polska")
	assert_eq(String(TranslationServer.translate("Russia")), "Rosja")
	TranslationServer.set_locale("en")
	assert_eq(String(TranslationServer.translate("Poland")), "Poland")
	TranslationServer.set_locale(previous)


func test_game_state_defaults_to_the_default_pair() -> void:
	var state := GameState.new(HexGrid.new(), 2, 1)
	assert_eq(state.player_factions, [&"poland", &"russia"] as Array[StringName])
	assert_eq(state.faction_of(0).id, &"poland")
	assert_eq(state.faction_of(1).id, &"russia")


func test_faction_of_out_of_range_or_unknown_is_null() -> void:
	var state := GameState.new(HexGrid.new(), 2, 1)
	assert_eq(state.faction_of(2), null)
	assert_eq(state.faction_of(-1), null)
	state.player_factions = [&"poland", &"atlantis"]
	assert_eq(state.faction_of(1), null)


func test_factions_are_not_in_the_snapshot() -> void:
	var state := GameState.new(HexGrid.new(), 2, 1)
	var before := state.snapshot()
	state.player_factions = [&"russia", &"poland"]
	assert_eq(state.snapshot(), before)
