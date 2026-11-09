extends TestCase
## AutoResolveRules and the shared BattleResult fields (TASK-120).

const Fixtures := preload("res://tests/fixtures.gd")

# --- data ---


func test_shipped_rules() -> void:
	var rules := AutoResolveRules.shipped()
	assert_eq(rules.default_rounds, 8)
	assert_eq(rules.break_share, 50)
	assert_eq(rules.problem(), "")
	var file := load("res://data/battle/auto_resolve.tres") as AutoResolveRules
	assert_eq(file.default_rounds, 8)
	assert_eq(file.break_share, 50)


func test_rules_problems() -> void:
	var rules := AutoResolveRules.new()
	rules.default_rounds = 0
	assert_true(rules.problem() != "")
	rules.default_rounds = 1
	rules.break_share = 0
	assert_true(rules.problem() != "")
	rules.break_share = 101
	assert_true(rules.problem() != "")
	rules.break_share = 100
	assert_eq(rules.problem(), "")


# --- result fields ---


func _hand_result(winner: int, ends: Array) -> BattleResult:
	var result := BattleResult.new()
	result.winner = winner
	for player in ends.size():
		var company := BattleResult.Company.new()
		company.player = player
		company.strength_start = 5
		company.strength_end = ends[player]
		result.companies.append(company)
	return result


func test_settle() -> void:
	var setup := Fixtures.auto_case("mirror")
	var won := _hand_result(0, [3, 2])
	won.settle(setup)
	assert_eq([won.field_holder, won.retreat], [0, 1])
	var wiped := _hand_result(0, [3, 0])
	wiped.settle(setup)
	assert_eq([wiped.field_holder, wiped.retreat], [0, -1])
	var draw := _hand_result(-1, [3, 2])
	draw.settle(setup)
	assert_eq([draw.field_holder, draw.retreat], [1, -1])
	setup.attacker = -1
	draw.settle(setup)
	assert_eq([draw.field_holder, draw.retreat], [-1, -1])


func test_played_battle_settles_like_the_helper() -> void:
	var setup := Scenario.default_battle_setup(3)
	var state := Scenario.from_setup(setup)
	state.winner = 1
	state.end_reason = &"eliminated"
	var result := BattleResult.from_battle(setup, state)
	assert_eq(result.resolution, &"played")
	var again := BattleResult.from_dict(result.to_dict())
	again.settle(setup)
	assert_eq([result.field_holder, result.retreat], [again.field_holder, again.retreat])
	assert_eq(result.field_holder, 1)


func test_result_fields_round_trip_and_are_required() -> void:
	var result := AutoResolve.resolve(Fixtures.auto_case("salvo"))
	var d := result.to_dict()
	assert_eq(BattleResult.from_dict(d).to_dict(), d)
	for key in ["resolution", "field_holder", "retreat"]:
		var missing := d.duplicate(true)
		missing.erase(key)
		assert_true(BattleResult.from_dict(missing) == null, "without %s" % key)
	var other := d.duplicate(true)
	other["resolution"] = "magic"
	assert_true(BattleResult.from_dict(other) == null)
