extends TestCase

const DIR := "user://test_match_saver"
const PATH := DIR + "/nested/match.json"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "/nested"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func test_save_creates_folders_and_writes_loadable_record() -> void:
	var sim := GameSimulation.new(Scenario.default_battle(7))
	sim.execute(EndTurnCommand.new())
	var record := MatchRecord.from_simulation(sim, 7)
	assert_eq(MatchSaver.save(record, PATH), OK)
	var loaded := MatchRecord.from_json(FileAccess.get_file_as_string(PATH))
	assert_true(loaded != null, "saved file parses back")
	if loaded == null:
		return
	assert_eq(loaded.seed, 7)
	assert_eq(loaded.commands.size(), 1)
	assert_eq(loaded.commands, record.commands)


func test_default_path() -> void:
	assert_eq(MatchSaver.LAST_MATCH_PATH, "user://matches/last_match.json")
