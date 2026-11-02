extends TestCase
## The sound bank (TASK-123): every sound id used by a unit or the planner has streams, and every
## stream file exists.

const BANK_PATH := "res://data/audio/sound_bank.tres"
const UNITS_DIR := "res://data/units"
const THIRD_PARTY := "res://assets/third_party/"


func _bank() -> SoundBank:
	return load(BANK_PATH) as SoundBank


func test_bank_loads() -> void:
	assert_true(_bank() != null)


func test_every_planner_id_is_in_the_bank() -> void:
	var bank := _bank()
	for id in SoundPlanner.all_ids():
		assert_true(bank.has_id(id), "missing sound id " + str(id))
		assert_true(bank.streams_of(id).size() >= 1, "no stream for " + str(id))


func test_every_unit_sound_id_is_in_the_bank() -> void:
	var bank := _bank()
	for file in DirAccess.get_files_at(UNITS_DIR):
		if not file.ends_with(".tres"):
			continue
		var definition := load(UNITS_DIR.path_join(file)) as UnitDefinition
		assert_true(bank.has_id(definition.fire_sound), "%s fire_sound" % definition.id)
		for id in SoundPlanner.move_loops(definition):
			assert_true(bank.has_id(id), "%s loop %s" % [definition.id, id])


func test_every_stream_file_exists() -> void:
	var bank := _bank()
	for id in bank.ids():
		for path in bank.streams_of(id):
			assert_true(FileAccess.file_exists(path), "%s: missing file %s" % [id, path])


func test_variants_per_one_shot() -> void:
	var bank := _bank()
	for id in SoundPlanner.all_ids():
		if not bank.is_loop(id) and id != &"ui_toggle":
			assert_true(bank.streams_of(id).size() >= 1, str(id))


func test_third_party_streams_are_credited() -> void:
	var credited := {}
	for entry: Dictionary in JSON.parse_string(
		FileAccess.get_file_as_string(THIRD_PARTY + "credits.json")
	):
		for file: String in entry["files"]:
			credited[file] = true
	var bank := _bank()
	for id in bank.ids():
		for path in bank.streams_of(id):
			if path.begins_with(THIRD_PARTY):
				assert_true(credited.has(path.trim_prefix(THIRD_PARTY)), "uncredited " + path)


func test_ambient_settings_are_sane() -> void:
	var bank := _bank()
	assert_true(bank.ambient_max_distance > 7.0 and bank.ambient_max_distance < 46.0)
	assert_true(bank.ambient_min_forest > 0.0 and bank.ambient_min_forest < 1.0)
	assert_true(bank.ambient_fade > 0.0)
	assert_true(bank.max_one_shots >= 8)
