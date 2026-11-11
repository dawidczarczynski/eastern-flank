extends TestCase
## Battle auto-resolve (TASK-120): AutoResolveRules, BattleResult.settle and the shared result
## fields, AutoResolve.resolve (rejections, shape, rounds and fire, outcomes, determinism, no state
## change, speed), the `auto_mismatch` check of ResolveBattleCommand and auto entries of a
## CampaignRecord.

const Fixtures := preload("res://tests/fixtures.gd")
## Regenerated only on purpose (like the replay fixture).
const GOLDEN_MIRROR_7 := {
	"winner": 0,
	"reason": "broken",
	"turns": 9,
	"resolution": "auto",
	"field_holder": 0,
	"retreat": 1,
	"companies":
	[
		{
			"player": 0,
			"unit_type": "pl_mech_infantry",
			"ref": "t/0",
			"strength_start": 10,
			"strength_end": 0
		},
		{
			"player": 0,
			"unit_type": "pl_mech_infantry",
			"ref": "t/1",
			"strength_start": 10,
			"strength_end": 0
		},
		{
			"player": 0,
			"unit_type": "pl_mech_infantry",
			"ref": "t/2",
			"strength_start": 10,
			"strength_end": 0
		},
		{
			"player": 0,
			"unit_type": "m1a2_sepv3",
			"ref": "t/3",
			"strength_start": 10,
			"strength_end": 7
		},
		{
			"player": 1,
			"unit_type": "pl_mech_infantry",
			"ref": "t/4",
			"strength_start": 10,
			"strength_end": 0
		},
		{
			"player": 1,
			"unit_type": "pl_mech_infantry",
			"ref": "t/5",
			"strength_start": 10,
			"strength_end": 0
		},
		{
			"player": 1,
			"unit_type": "pl_mech_infantry",
			"ref": "t/6",
			"strength_start": 10,
			"strength_end": 0
		},
		{
			"player": 1,
			"unit_type": "m1a2_sepv3",
			"ref": "t/7",
			"strength_start": 10,
			"strength_end": 1
		},
	],
}


func _wins(kind: String, seeds: int) -> Dictionary:
	var wins := [0, 0]
	var losses := [0.0, 0.0]
	for s in range(1, seeds + 1):
		var result := AutoResolve.resolve(Fixtures.auto_case(kind, s))
		if result.winner >= 0:
			wins[result.winner] += 1
		for company in result.companies:
			losses[company.player] += company.losses()
	return {"wins": wins, "loss0": losses[0] / seeds, "loss1": losses[1] / seeds}


# --- rejections ---


func test_rejects_a_foreign_unit_type() -> void:
	var setup := Fixtures.auto_case("salvo")
	setup.companies[2].unit_type = &"homar_k"
	assert_true(AutoResolve.resolve(setup) == null)


func test_rejects_a_strength_out_of_range() -> void:
	var setup := Fixtures.auto_case("salvo")
	setup.companies[0].strength = 7
	assert_true(AutoResolve.resolve(setup) == null)
	setup.companies[0].strength = 0
	assert_true(AutoResolve.resolve(setup) == null)


func test_rejects_a_side_without_companies() -> void:
	var setup := Fixtures.auto_case("salvo")
	setup.companies.pop_back()
	assert_true(AutoResolve.resolve(setup) == null)


func test_rejects_wrong_condition_count() -> void:
	var setup := Fixtures.auto_case("salvo")
	setup.conditions.pop_back()
	assert_true(AutoResolve.resolve(setup) == null)


# --- shape and exact cases ---


func test_shape() -> void:
	var setup := Fixtures.auto_case("crush", 5)
	var result := AutoResolve.resolve(setup)
	assert_eq(result.resolution, &"auto")
	assert_eq(result.companies.size(), setup.companies.size())
	for i in setup.companies.size():
		var planned := setup.companies[i]
		var reported := result.companies[i]
		assert_eq(reported.player, planned.player)
		assert_eq(reported.unit_type, planned.unit_type)
		assert_eq(reported.ref, planned.ref)
		assert_eq(reported.strength_start, planned.strength)
		assert_true(reported.strength_end >= 0 and reported.strength_end <= planned.strength)
	var settled := BattleResult.from_dict(result.to_dict())
	settled.settle(setup)
	assert_eq([result.field_holder, result.retreat], [settled.field_holder, settled.retreat])


func test_salvo_is_exact_for_any_seed() -> void:
	for s in range(1, 21):
		var result := AutoResolve.resolve(Fixtures.auto_case("salvo", s))
		assert_eq(result.winner, 0)
		assert_eq(result.reason, &"eliminated")
		assert_eq(result.turns, 1)
		assert_eq(result.companies[2].strength_end, 0)
		assert_eq(result.companies[1].strength_end, 6)
		assert_true(result.companies[0].strength_end <= 3)
		assert_eq(result.field_holder, 0)
		assert_eq(result.retreat, -1)


func test_command_points_limit_the_firing_companies() -> void:
	var setup := Fixtures.auto_case("salvo")
	setup.conditions[0].command_points = 1
	setup.objectives.turn_limit = 1
	var result := AutoResolve.resolve(setup)
	assert_eq(result.reason, &"turn_limit")
	assert_eq(result.turns, 1)
	assert_eq(result.companies[2].strength_end, 3, "only one of the two companies fired")


func test_mutual_destruction_is_a_draw() -> void:
	var setup := Fixtures.auto_case("salvo")
	setup.companies.remove_at(1)
	setup.companies[0].strength = 4
	setup.companies[1].strength = 4
	setup.conditions[0].posture = &"march"
	setup.conditions[0].position_bonus = -1
	var result := AutoResolve.resolve(setup)
	assert_eq(result.winner, -1)
	assert_eq(result.reason, &"eliminated")
	assert_eq(result.companies[0].strength_end, 0)
	assert_eq(result.companies[1].strength_end, 0)
	assert_eq(result.field_holder, 1)
	assert_eq(result.retreat, -1)


# --- statistics ---


func test_overwhelming_force_wins_cheaply() -> void:
	var wins := 0
	var losses := 0.0
	for s in range(1, 101):
		var setup := Fixtures.auto_case("crush", s)
		var result := AutoResolve.resolve(setup)
		if result.winner == 0:
			wins += 1
			assert_true(
				result.companies[4].strength_end == 0 or result.retreat == 1,
				"the motor rifle company is destroyed or retreats"
			)
		for company in result.companies:
			if company.player == 0:
				losses += company.losses()
	assert_true(wins >= 95, "wins %d" % wins)
	assert_true(losses / 100.0 <= 4.0, "mean losses %f" % (losses / 100.0))


func test_equal_forces_are_costly() -> void:
	var stats := _wins("mirror", 200)
	assert_true(stats["loss0"] >= 12.0, "loss0 %f" % stats["loss0"])
	assert_true(stats["loss1"] >= 12.0, "loss1 %f" % stats["loss1"])
	assert_true(absi(stats["wins"][0] - stats["wins"][1]) <= 30, "wins %s" % [stats["wins"]])


func test_terrain_and_posture_count() -> void:
	var stats := _wins("fortress", 200)
	assert_true(stats["wins"][1] > stats["wins"][0], "wins %s" % [stats["wins"]])
	assert_true(stats["loss0"] > stats["loss1"], "%f vs %f" % [stats["loss0"], stats["loss1"]])


func test_turn_limit_draws() -> void:
	for s in range(1, 51):
		var setup := Fixtures.auto_case("mirror", s)
		setup.objectives.turn_limit = 1
		var result := AutoResolve.resolve(setup)
		assert_eq(result.winner, -1)
		assert_eq(result.reason, &"turn_limit")
		assert_eq(result.turns, 1)
		assert_eq(result.field_holder, 1)


# --- determinism, purity, speed ---


func test_deterministic() -> void:
	var setup := Fixtures.auto_case("mirror", 9)
	assert_eq(AutoResolve.resolve(setup).to_dict(), AutoResolve.resolve(setup).to_dict())
	var distinct := {}
	for s in range(1, 21):
		distinct[str(AutoResolve.resolve(Fixtures.auto_case("mirror", s)).to_dict())] = true
	assert_true(distinct.size() >= 2)


func test_golden_mirror_seed_7() -> void:
	var result := AutoResolve.resolve(Fixtures.auto_case("mirror", 7))
	assert_eq(result.to_dict(), GOLDEN_MIRROR_7)


func test_resolve_changes_no_state() -> void:
	var setup := Fixtures.auto_case("mirror", 3)
	var before := setup.to_dict()
	AutoResolve.resolve(setup)
	assert_eq(setup.to_dict(), before)
	var state := Operation.build(&"suwalki_gap", 1)
	assert_false(Fixtures.theatre_contact(state).is_empty())
	var snapshot := state.snapshot()
	var rng_state := state.rng.state
	AutoResolve.resolve(state.pending_battles[0])
	assert_eq(state.snapshot(), snapshot)
	assert_eq(state.rng.state, rng_state)


func test_speed() -> void:
	var rows: Array = []
	for player in 2:
		for i in 12:
			rows.append([player, &"pl_mech_infantry" if i % 2 == 0 else &"m1a2_sepv3", 10])
	var pl_pl: Array[StringName] = [&"poland", &"poland"]
	var setup := Fixtures.auto_setup(pl_pl, rows, [[&"advance", 0], [&"advance", 0]])
	var times: Array[int] = []
	for run in 50:
		setup.seed = run
		var start := Time.get_ticks_usec()
		AutoResolve.resolve(setup)
		times.append(Time.get_ticks_usec() - start)
	times.sort()
	assert_true(times[25] <= 4000, "median %d us" % times[25])
