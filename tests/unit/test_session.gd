extends TestCase
## Session (TASK-094c): the campaign across the staff map <-> battle scene change. Headless smoke
## test of the whole hand-off: scripted contact -> Session.play_battle -> an AI-vs-AI run of the
## played battle (MatchRunner) -> Report to staff (finish_battle) -> the pending battle is gone
## and End turn works.

const Fixtures := preload("res://tests/fixtures.gd")
const OPERATION := &"suwalki_gap"

static var _state: OperationalState
var _simulation: OperationalSimulation


func before_all() -> void:
	_state = Operation.build(OPERATION, 1)


func after_all() -> void:
	_state = null
	Session.abandon()


func before_each() -> void:
	_state.pending_battles.clear()
	_simulation = OperationalSimulation.new(_state)
	Session.abandon()


func test_play_report_and_return() -> void:
	assert_false(Fixtures.theatre_contact(_state).is_empty())
	var before := _state.snapshot()
	var view := {"zoom": 0.5}
	assert_eq(Session.play_battle(_simulation, OPERATION, 1, view), "")
	assert_true(Session.in_battle())
	assert_eq(Session.human_player, 1)
	assert_eq(Session.view, view)
	assert_eq(Session.battle.map_id, ContactSettings.shipped().layer_for(_state.map_id))
	assert_true(Session.take_simulation(OPERATION) == null, "no return while the battle runs")
	var battle := GameSimulation.new(Scenario.from_setup(Session.battle))
	assert_false(Session.finish_battle(battle.state), "the battle is not over yet")
	assert_true(MatchRunner.run(battle, 40))
	assert_true(Session.finish_battle(battle.state), "Report to staff")
	assert_false(Session.in_battle())
	assert_eq(_state.pending_battles.size(), 0, "the battle is resolved")
	assert_true(Session.take_simulation(&"other_operation") == null)
	assert_true(Session.take_simulation(OPERATION) == _simulation, "the staff map gets it back")
	assert_true(Session.take_simulation(OPERATION) == null, "only once")
	assert_eq(_state.snapshot(), before, "no consequences yet (TASK-095)")
	var report := Session.take_report()
	var result: BattleResult = report["result"]
	assert_eq(result.winner, battle.state.winner)
	assert_eq(result.companies.size(), (report["setup"] as BattleSetup).companies.size())
	assert_true(Session.take_report().is_empty(), "the notice shows once")
	assert_true(_simulation.execute(EndOperationalTurnCommand.new()), "End turn is possible")


func test_play_without_a_pending_battle_changes_nothing() -> void:
	assert_eq(Session.play_battle(_simulation, OPERATION, 0, {}), "no_pending_battle")
	assert_false(Session.in_battle())
	assert_true(Session.simulation == null)


func test_abandon_drops_the_campaign_without_a_result() -> void:
	Fixtures.theatre_contact(_state)
	assert_eq(Session.play_battle(_simulation, OPERATION, 0, {}), "")
	Session.abandon()
	assert_false(Session.in_battle())
	assert_true(Session.take_simulation(OPERATION) == null)
	assert_true(Session.take_report().is_empty())
	assert_eq(_state.pending_battles.size(), 1, "the battle stays pending")
