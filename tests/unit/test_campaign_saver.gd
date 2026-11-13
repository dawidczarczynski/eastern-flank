extends TestCase
## Campaign saves (TASK-094d): CampaignSaver writes a CampaignRecord atomically to a folder,
## finds the latest save and loads it back (from_dict + replay) – a corrupt file gives a message,
## never a crash; Session records the operation, a pending battle survives the save and Continue
## hands the replayed operation to the staff map.

const OPERATION := &"suwalki_gap"
const SEED := 1
const DIR := "user://test_campaigns"

var _simulation: OperationalSimulation


func before_each() -> void:
	_clear_dir()
	Session.abandon()
	_simulation = OperationalSimulation.new(Operation.build(OPERATION, SEED))
	Session.start_campaign(_simulation, OPERATION, SEED)


func after_all() -> void:
	_clear_dir()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	Session.abandon()


static func _clear_dir() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)


## The scripted contact of test_campaign_record: ru_mr_4 halts next to pl_tank_2 on turn 2.
func _contact() -> void:
	assert_true(
		_simulation.execute(IssueOrderCommand.new(&"ru_mr_4", Vector2i(16, 52), &"advance"))
	)
	for i in 3:
		assert_true(_simulation.execute(EndOperationalTurnCommand.new()))
	assert_eq(_simulation.state.pending_battles.size(), 1)


static func _setup_dicts(state: OperationalState) -> Array:
	return state.pending_battles.map(func(b: BattleSetup) -> Dictionary: return b.to_dict())


func test_save_and_load_with_a_pending_battle() -> void:
	_contact()
	var record := Session.record(1)
	assert_true(record != null)
	assert_eq(record.human_side, _simulation.state.player_sides[1])
	var path := CampaignSaver.path_for(String(OPERATION), DIR)
	assert_eq(path, DIR + "/suwalki_gap.json")
	assert_eq(CampaignSaver.save(record, path), OK)
	assert_true(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + ".tmp"), "the temp file is renamed")
	assert_eq(CampaignSaver.latest(DIR), path)
	var loaded := CampaignSaver.load_campaign(path)
	assert_eq(loaded["error"], "")
	var simulation: OperationalSimulation = loaded["simulation"]
	assert_eq(simulation.state.snapshot(), _simulation.state.snapshot())
	assert_eq(_setup_dicts(simulation.state), _setup_dicts(_simulation.state))
	assert_eq((loaded["record"] as CampaignRecord).to_dict(), record.to_dict())


func test_save_overwrites_the_slot() -> void:
	var path := CampaignSaver.path_for("slot", DIR)
	assert_eq(CampaignSaver.save(Session.record(0), path), OK)
	assert_true(_simulation.execute(EndOperationalTurnCommand.new()))
	assert_eq(CampaignSaver.save(Session.record(1), path), OK)
	var loaded := CampaignSaver.load_campaign(path)
	assert_eq(loaded["error"], "")
	assert_eq((loaded["record"] as CampaignRecord).commands.size(), 1)
	assert_eq((loaded["record"] as CampaignRecord).human_side, _simulation.state.player_sides[1])


func test_corrupt_or_missing_files_give_a_message() -> void:
	assert_eq(CampaignSaver.latest(DIR), "", "no save yet")
	var missing := CampaignSaver.load_campaign(DIR + "/none.json")
	assert_eq(missing["error"], "unreadable")
	assert_true(missing["simulation"] == null)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var cases := {
		"garbage": "{not json",
		"wrong": '{"version": 1}',
		"diverging":
		(
			'{"version": 1, "operation": "suwalki_gap", "seed": 1, "human_side": "nato", '
			+ '"commands": [{"type": "resolve_battle", "result": {"winner": 0, "reason": "x", '
			+ '"turns": 1, '
			+ '"resolution": "played", "field_holder": 0, "retreat": -1, "companies": []}}], "battles": []}'
		),
	}
	var expected := {"garbage": "corrupt", "wrong": "corrupt", "diverging": "replay_failed"}
	for name: String in cases:
		var path := CampaignSaver.path_for(name, DIR)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(cases[name])
		file.close()
		var loaded := CampaignSaver.load_campaign(path)
		assert_eq(loaded["error"], expected[name], name)
		assert_true(loaded["record"] == null and loaded["simulation"] == null, name)
		assert_false(CampaignSaver.message(loaded).is_empty(), name)


func test_no_record_while_a_battle_runs() -> void:
	_contact()
	assert_eq(Session.play_battle(_simulation, OPERATION, 0, {}), "")
	assert_true(Session.record(0) == null, "a battle in progress cannot be saved")
	Session.abandon()
	assert_true(Session.record(0) == null, "no campaign")


func test_played_battle_is_recorded_and_replays_in_full() -> void:
	_contact()
	assert_eq(Session.play_battle(_simulation, OPERATION, 1, {"zoom": 0.5}), "")
	var battle := GameSimulation.new(Scenario.from_setup(Session.battle))
	assert_true(MatchRunner.run(battle, 40))
	assert_true(Session.finish_battle(battle))
	assert_true(Session.take_simulation(OPERATION) == _simulation)
	var record := Session.record(1)
	assert_eq(record.battles.size(), 1)
	assert_eq(record.battles[0].commands.size(), battle.history.size())
	assert_eq(record.human_side, _simulation.state.player_sides[1])
	var replay := CampaignRecord.from_json(record.to_json()).replay(true)
	assert_true(replay["ok"], "full replay: %s" % replay)
	assert_eq(
		(replay["simulation"] as OperationalSimulation).state.snapshot(),
		_simulation.state.snapshot()
	)


func test_continue_hands_the_campaign_to_the_staff_map() -> void:
	_contact()
	var path := CampaignSaver.path_for(String(OPERATION), DIR)
	assert_eq(CampaignSaver.save(Session.record(1), path), OK)
	Session.abandon()
	var loaded := CampaignSaver.load_campaign(path)
	Session.resume(loaded["record"], loaded["simulation"])
	assert_true(Session.resuming())
	assert_eq(Session.operation_id, OPERATION)
	assert_eq(Session.seed_value, SEED)
	assert_eq(Session.human_player, 1)
	assert_eq(Session.view.get("viewer"), 1)
	var simulation := Session.take_simulation(OPERATION)
	assert_true(simulation == loaded["simulation"])
	assert_false(Session.resuming())
	assert_eq(_setup_dicts(simulation.state), _setup_dicts(_simulation.state))
	assert_eq(Session.record(1).to_dict(), (loaded["record"] as CampaignRecord).to_dict())
