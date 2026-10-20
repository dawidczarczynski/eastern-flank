extends TestCase
## Game data (data/units/*.tres) agrees with the unit catalog (docs/design/units/units/<id>/
## unit.json, TASK-037). Test-only read of the catalog: the game itself never reads docs/.

const UNITS_DIR := "res://data/units"
const CATALOG := "res://docs/design/units/units/%s/unit.json"


func _catalog_entry(unit_id: StringName) -> Dictionary:
	var path := CATALOG % unit_id
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	return json.data


func test_every_unit_matches_its_catalog_entry() -> void:
	var checked := 0
	for file in DirAccess.get_files_at(UNITS_DIR):
		if not file.ends_with(".tres"):
			continue
		var definition := load(UNITS_DIR.path_join(file)) as UnitDefinition
		var entry := _catalog_entry(definition.id)
		assert_false(entry.is_empty(), "%s has a readable catalog entry" % definition.id)
		if entry.is_empty():
			continue
		checked += 1
		assert_eq(entry.get("real_name"), definition.display_name, "%s real_name" % definition.id)
		assert_eq(entry.get("class"), String(definition.unit_class), "%s class" % definition.id)
		assert_eq(entry.get("mobility"), String(definition.mobility), "%s mobility" % definition.id)
		var operators: Array = entry.get("operators", [])
		for faction in FactionRegistry.all():
			if faction.has_unit(definition):
				assert_true(
					String(faction.id) in operators,
					"%s: %s is not among the catalog operators" % [definition.id, faction.id]
				)
	assert_true(checked > 0, "at least one unit checked")
