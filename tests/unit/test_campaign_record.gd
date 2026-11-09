extends TestCase
## CampaignRecord (TASK-094d, ADR 0015 §4): an operation as id + seed + operational commands +
## played battles. Strict to_dict / from_dict (JSON round trip), fast replay (identical snapshot
## and events, results from the record), full replay (re-plays every battle and catches a
## tampered result) and a record with a pending battle restores it.
## The live run: ru_mr_4 advances on pl_tank_2 (contact on turn 2), the AI plays the battle, it is
## resolved, then two more End turns – three rounds with one contact.

const OPERATION := &"suwalki_gap"
const SEED := 1
const ATTACKER := &"ru_mr_4"
const DESTINATION := Vector2i(16, 52)

static var _record: CampaignRecord  # the whole run
static var _pending_record: CampaignRecord  # saved while the battle was pending
static var _snapshot: Dictionary
static var _pending_snapshot: Dictionary
static var _pending_dicts: Array
static var _events: Array[Dictionary] = []
static var _final_dicts: Array


func before_all() -> void:
	var state := Operation.build(OPERATION, SEED)
	var sim := OperationalSimulation.new(state)
	_events.clear()
	sim.event_emitted.connect(func(event: Dictionary) -> void: _events.append(event))
	assert_true(sim.execute(IssueOrderCommand.new(ATTACKER, DESTINATION, &"advance")))
	for i in 3:
		assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(state.pending_battles.size(), 1, "the scripted contact happened")
	_pending_record = CampaignRecord.from_simulation(sim, SEED, &"russia", [])
	_pending_snapshot = state.snapshot()
	_pending_dicts = _setup_dicts(state)
	var prepared := ContactBattle.prepare(state)
	var battle := GameSimulation.new(Scenario.from_setup(prepared))
	assert_true(MatchRunner.run(battle, 40), "the AI plays the battle to its end")
	var result := BattleResult.from_battle(prepared, battle.state)
	assert_true(sim.execute(ResolveBattleCommand.new(result)))
	var entry := CampaignRecord.Battle.played(
		prepared, BattleReplay.command_dicts(battle.history), result
	)
	for i in 2:
		assert_true(sim.execute(EndOperationalTurnCommand.new()))
	_record = CampaignRecord.from_simulation(sim, SEED, &"russia", [entry])
	_snapshot = state.snapshot()
	_final_dicts = _setup_dicts(state)


func after_all() -> void:
	_record = null
	_pending_record = null
	_events.clear()


static func _setup_dicts(state: OperationalState) -> Array:
	return state.pending_battles.map(func(b: BattleSetup) -> Dictionary: return b.to_dict())


func _copy(record: CampaignRecord) -> CampaignRecord:
	return CampaignRecord.from_dict(record.to_dict().duplicate(true))


func test_record_holds_the_run() -> void:
	assert_eq(_record.operation_id, OPERATION)
	assert_eq(_record.seed, SEED)
	assert_eq(_record.human_side, &"russia")
	assert_eq(_record.commands.size(), 7, "order, 3 + 2 End turns, resolve")
	assert_eq(_record.commands[4]["type"], ResolveBattleCommand.TYPE)
	assert_eq(_record.battles.size(), 1)
	assert_eq(_record.battles[0].resolution, &"played")
	assert_false(_record.battles[0].commands.is_empty(), "the tactical commands are kept")


func test_json_round_trip() -> void:
	var back := CampaignRecord.from_json(_record.to_json())
	assert_true(back != null, "the JSON loads back")
	assert_eq(back.to_dict(), _record.to_dict())
	var dict := _record.to_dict()
	assert_eq(dict["version"], CampaignRecord.VERSION)
	assert_eq((dict["battles"] as Array)[0]["resolution"], "played")


func test_from_dict_rejects_malformed_records() -> void:
	var good := _record.to_dict()
	assert_true(CampaignRecord.from_dict(good) != null)
	for key: String in ["version", "operation", "seed", "human_side", "commands", "battles"]:
		var broken := good.duplicate(true)
		broken.erase(key)
		assert_true(CampaignRecord.from_dict(broken) == null, "missing %s" % key)
	var cases: Array[Dictionary] = []
	var wrong_version := good.duplicate(true)
	wrong_version["version"] = CampaignRecord.VERSION + 1
	cases.append(wrong_version)
	var float_seed := good.duplicate(true)
	float_seed["seed"] = 1.5
	cases.append(float_seed)
	var bad_command := good.duplicate(true)
	(bad_command["commands"] as Array)[0] = {"type": "nope"}
	cases.append(bad_command)
	var bad_setup := good.duplicate(true)
	((bad_setup["battles"] as Array)[0] as Dictionary)["setup"] = {"seed": 1}
	cases.append(bad_setup)
	var bad_result := good.duplicate(true)
	((bad_result["battles"] as Array)[0] as Dictionary)["result"] = "won"
	cases.append(bad_result)
	var bad_tactical := good.duplicate(true)
	((bad_tactical["battles"] as Array)[0] as Dictionary)["commands"] = [{"type": "teleport"}]
	cases.append(bad_tactical)
	var bad_resolution := good.duplicate(true)
	((bad_resolution["battles"] as Array)[0] as Dictionary)["resolution"] = "guessed"
	cases.append(bad_resolution)
	for i in cases.size():
		assert_true(CampaignRecord.from_dict(cases[i]) == null, "malformed case %d" % i)
	assert_true(CampaignRecord.from_json("{not json") == null)
	assert_true(CampaignRecord.from_json("[1, 2]") == null)


func test_fast_replay_is_identical() -> void:
	var replay := CampaignRecord.from_json(_record.to_json()).replay()
	assert_true(replay["ok"], "replay: %s" % replay)
	var sim: OperationalSimulation = replay["simulation"]
	assert_eq(sim.state.snapshot(), _snapshot)
	assert_eq(replay["events"], _events)
	assert_eq(sim.history.size(), _record.commands.size())
	assert_eq(_setup_dicts(sim.state), _final_dicts, "the same battles are pending")


func test_full_replay_replays_the_battle() -> void:
	var replay := _record.replay(true)
	assert_true(replay["ok"], "full replay: %s" % replay)
	assert_eq((replay["simulation"] as OperationalSimulation).state.snapshot(), _snapshot)


func test_tampered_result_is_caught_by_the_full_replay() -> void:
	var dict := _record.to_dict().duplicate(true)
	var company: Dictionary = (
		((dict["battles"] as Array)[0] as Dictionary)["result"] as Dictionary
	)["companies"][0]
	company["strength_end"] = 0 if int(company["strength_end"]) > 0 else 1
	# The resolve command carries the same (tampered) result, so the record is consistent.
	(dict["commands"] as Array)[4] = {
		"type": ResolveBattleCommand.TYPE,
		"result": ((dict["battles"] as Array)[0] as Dictionary)["result"],
	}
	var tampered := CampaignRecord.from_dict(dict)
	assert_true(tampered != null)
	assert_true(tampered.replay()["ok"], "the fast replay trusts the record")
	var full := tampered.replay(true)
	assert_false(full["ok"])
	assert_eq(full["error"], "battle_diverged")
	assert_eq(full["battle"], 0)
	assert_eq(full["index"], 4)


func test_resolve_command_and_battle_entry_must_agree() -> void:
	var dict := _record.to_dict().duplicate(true)
	var result: Dictionary = ((dict["battles"] as Array)[0] as Dictionary)["result"]
	result["turns"] = int(result["turns"]) + 1
	var replay := CampaignRecord.from_dict(dict).replay()
	assert_false(replay["ok"])
	assert_eq(replay["error"], "invalid_record")
	assert_eq(replay["index"], 4)


func test_battle_count_must_match_the_resolve_commands() -> void:
	var missing := _copy(_record)
	missing.battles.clear()
	assert_eq(missing.replay()["error"], "invalid_record")
	var extra := _copy(_pending_record)
	extra.battles.append(_record.battles[0])
	assert_eq(extra.replay()["error"], "invalid_record")


func test_pending_battle_is_restored() -> void:
	var back := CampaignRecord.from_json(_pending_record.to_json())
	var replay := back.replay(true)
	assert_true(replay["ok"], "replay: %s" % replay)
	var state := (replay["simulation"] as OperationalSimulation).state
	assert_eq(state.snapshot(), _pending_snapshot)
	assert_eq(_setup_dicts(state), _pending_dicts, "same BattleSetup, same seed")


func test_replay_rejects_unknown_operation_side_and_diverging_commands() -> void:
	var unknown := _copy(_pending_record)
	unknown.operation_id = &"no_such_operation"
	assert_eq(unknown.replay()["error"], "unknown_operation")
	var side := _copy(_pending_record)
	side.human_side = &"martians"
	assert_eq(side.replay()["error"], "invalid_side")
	var diverging := _copy(_pending_record)
	diverging.commands.append(EndOperationalTurnCommand.new().to_dict())
	var replay := diverging.replay()
	assert_eq(replay["error"], "diverged")
	assert_eq(replay["index"], 4)
	assert_eq(replay["reason"], "battle_pending")


func test_human_player_maps_the_side() -> void:
	var state := (_pending_record.replay()["simulation"] as OperationalSimulation).state
	assert_eq(_pending_record.human_player(state), state.player_sides.find(&"russia"))
	assert_true(_pending_record.human_player(state) >= 0)
