extends TestCase
## Auto-resolve with battle conditions (TASK-099a): the command-point cap by attack value, free
## fire-support volleys, determinism, the auto_mismatch re-computation and monotonic sweeps.

const Fixtures := preload("res://tests/fixtures.gd")


func test_zero_command_points_means_everyone_fires() -> void:
	var setup := Fixtures.auto_case("salvo")
	setup.objectives.turn_limit = 1
	var open := AutoResolve.resolve(setup)
	setup.conditions[0].command_points = 2
	assert_eq(AutoResolve.resolve(setup).to_dict(), open.to_dict(), "2 points = both fire")
	setup.conditions[0].command_points = 0
	assert_eq(AutoResolve.resolve(setup).to_dict(), open.to_dict())


func test_weaker_company_sits_out_first() -> void:
	var pl_ru: Array[StringName] = [&"poland", &"russia"]
	var attacker_of := func(id: StringName) -> int:
		return FactionRegistry.get_faction(&"poland").find_unit(id).attack
	assert_true(attacker_of.call(&"m1a2_sepv3") > attacker_of.call(&"pl_mech_infantry"))
	# The infantry is first in setup order, the tank second; with one point the tank fires.
	var setup := (
		Fixtures
		. auto_setup(
			pl_ru,
			[
				[0, &"pl_mech_infantry", 10],
				[0, &"m1a2_sepv3", 10],
				[1, &"ru_motor_rifle", 10],
			],
			[[&"advance", 0], [&"advance", 0]]
		)
	)
	setup.conditions[0].command_points = 1
	setup.objectives.turn_limit = 1
	var capped := AutoResolve.resolve(setup)
	setup.companies.remove_at(0)
	setup.conditions[0].command_points = 0
	var tank_alone := AutoResolve.resolve(setup)
	# Same dice draws: one shooter, the tank, in both runs.
	assert_eq(capped.companies[2].strength_end, tank_alone.companies[1].strength_end)


func test_fire_support_adds_free_volleys() -> void:
	var setup := Fixtures.auto_case("salvo")
	setup.objectives.turn_limit = 1
	var plain := AutoResolve.resolve(setup)
	setup.conditions[0].fire_support = 2
	var supported := AutoResolve.resolve(setup)
	assert_true(supported.companies[2].strength_end <= plain.companies[2].strength_end)


func test_volleys_stop_after_the_missions() -> void:
	# fire_support 1 helps in round 1 only; a one-round fight with 1 or 5 missions is identical.
	var setup := Fixtures.auto_case("mirror", 5)
	setup.objectives.turn_limit = 1
	setup.conditions[0].fire_support = 1
	var one := AutoResolve.resolve(setup)
	setup.conditions[0].fire_support = 5
	assert_eq(AutoResolve.resolve(setup).to_dict(), one.to_dict())


func test_deterministic_with_conditions() -> void:
	var setup := Fixtures.auto_case("mirror", 9)
	setup.conditions[0].command_points = 2
	setup.conditions[1].fire_support = 2
	assert_eq(AutoResolve.resolve(setup).to_dict(), AutoResolve.resolve(setup).to_dict())


func test_auto_mismatch_recomputation_passes_with_conditions() -> void:
	var setup := Fixtures.auto_case("mirror", 9)
	setup.conditions[0].command_points = 2
	setup.conditions[1].fire_support = 2
	var result := AutoResolve.resolve(setup)
	var again := AutoResolve.resolve(setup)
	assert_eq(result.to_dict(), again.to_dict())
	assert_eq(result.resolution, BattleResult.AUTO)


func _wins(player: int, points: int, missions: int, seeds: int) -> int:
	var wins := 0
	for s in seeds:
		var setup := Fixtures.auto_case("mirror", s + 1)
		setup.conditions[player].command_points = points
		setup.conditions[player].fire_support = missions
		setup.conditions[1 - player].command_points = 2
		if AutoResolve.resolve(setup).winner == player:
			wins += 1
	return wins


func test_more_command_points_never_lower_the_win_share() -> void:
	assert_true(_wins(0, 3, 0, 200) >= _wins(0, 1, 0, 200))


func test_more_fire_support_never_lowers_the_win_share() -> void:
	assert_true(_wins(0, 2, 3, 200) >= _wins(0, 2, 0, 200))
