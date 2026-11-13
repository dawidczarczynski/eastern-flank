extends TestCase
## Battle conditions from installations (TASK-099a): BattleConditionsRules data and mapping, and
## the conditions ContactRules._build_setup fills.

const TestContact := preload("res://tests/unit/test_contact.gd")


static func _inst(class_id: StringName, owner: int, integrity: int) -> Installation:
	var installation := Installation.new()
	installation.id = StringName("i_%s_%d_%d" % [class_id, owner, integrity])
	installation.class_id = class_id
	installation.owner = owner
	installation.integrity = integrity
	return installation


static func _list(items: Array) -> Array[Installation]:
	var out: Array[Installation] = []
	for item: Installation in items:
		out.append(item)
	return out


func _points(items: Array, player := 0) -> int:
	return BattleConditionsRules.for_side(_list(items), player).command_points


func _missions(items: Array, player := 0) -> int:
	return BattleConditionsRules.for_side(_list(items), player).fire_support


func test_shipped_data() -> void:
	var rules := BattleConditionsRules.shipped()
	assert_eq(rules.problem(), "")
	assert_eq(rules.command_points_base, 4)
	assert_eq(rules.command_points_floor, 25)
	assert_eq(rules.fire_support_base, 2)
	assert_eq(rules.fire_support_floor, 0)
	assert_eq(rules.fire_support_attack, 4)
	assert_eq(rules.fire_support_shots, 6)


func test_one_c2_scales_with_integrity() -> void:
	assert_eq(_points([_inst(&"c2", 0, 100)]), 4)
	assert_eq(_points([_inst(&"c2", 0, 50)]), 2)
	assert_eq(_points([_inst(&"c2", 0, 10)]), 1)
	assert_eq(_points([_inst(&"c2", 0, 0)]), 1, "floor, never 0 (0 = unlimited)")


func test_mean_over_several_c2() -> void:
	assert_eq(_points([_inst(&"c2", 0, 100), _inst(&"c2", 0, 0)]), 2)


func test_no_installation_of_the_class_loses_nothing() -> void:
	assert_eq(_points([_inst(&"depot", 0, 0)]), 4)
	assert_eq(_missions([_inst(&"depot", 0, 0)]), 2)
	assert_eq(_points([]), 4)


func test_airfields() -> void:
	assert_eq(_missions([_inst(&"airfield", 0, 100)]), 2)
	assert_eq(_missions([_inst(&"airfield", 0, 50)]), 1)
	assert_eq(_missions([_inst(&"airfield", 0, 24)]), 0)
	assert_eq(_missions([_inst(&"airfield", 0, 0)]), 0)


func test_half_rounds_up() -> void:
	var rules := BattleConditionsRules.new()
	var list := _list([_inst(&"airfield", 0, 50)])
	assert_eq(BattleConditionsRules.scaled(3, 0, list, 0, &"airfield"), 2)
	assert_eq(rules.problem(), "")


func test_only_own_installations_count() -> void:
	var items := [
		_inst(&"c2", 0, 100),
		_inst(&"c2", 1, 0),
		_inst(&"airfield", 0, 0),
		_inst(&"airfield", 1, 100),
	]
	assert_eq(_points(items, 0), 4)
	assert_eq(_points(items, 1), 1)
	assert_eq(_missions(items, 0), 0)
	assert_eq(_missions(items, 1), 2)


func test_other_fields_untouched() -> void:
	var conditions := BattleConditionsRules.for_side(_list([_inst(&"c2", 0, 0)]), 0)
	assert_eq(conditions.ammunition, 100)
	assert_eq(conditions.morale, 100)
	assert_eq(conditions.posture, &"")
	assert_eq(conditions.position_bonus, 0)


func test_contact_battle_gets_conditions_from_installations() -> void:
	var state := TestContact._state()
	state.player_factions = [&"poland", &"russia"]
	state.installations.append(_inst(&"c2", 0, 100))
	state.installations.append(_inst(&"c2", 1, 10))
	state.installations.append(_inst(&"airfield", 0, 50))
	state.installations.append(_inst(&"airfield", 1, 100))
	var attacker := state.formation_at(Vector2i.ZERO)
	var defender := state.formation_at(Vector2i(4, 1))
	var setup := ContactRules._build_setup(state, attacker, defender)
	assert_eq(setup.conditions[0].command_points, 4)
	assert_eq(setup.conditions[1].command_points, 1)
	assert_eq(setup.conditions[0].fire_support, 1)
	assert_eq(setup.conditions[1].fire_support, 2)
	assert_eq(setup.conditions[0].posture, attacker.posture)


func test_scenario_battles_keep_defaults() -> void:
	var setup := Scenario.default_battle_setup(1)
	for conditions in setup.conditions:
		assert_eq(conditions.command_points, 0)
		assert_eq(conditions.fire_support, 0)
