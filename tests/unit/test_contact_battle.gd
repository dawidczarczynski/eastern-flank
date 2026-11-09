extends TestCase
## Playing a contact battle (TASK-094c): ContactBattle.prepare cuts the first pending battle's map
## without changing it, the battle starts exactly from it (strengths, conditions, seed,
## factions) and plays deterministically, and the played result closes it through
## ResolveBattleCommand.

const Fixtures := preload("res://tests/fixtures.gd")

static var _state: OperationalState


func before_all() -> void:
	_state = Operation.build(&"suwalki_gap", 1)


func after_all() -> void:
	_state = null


func after_each() -> void:
	_state.pending_battles.clear()


func _contact(skip := 0) -> BattleSetup:
	assert_false(Fixtures.theatre_contact(_state, skip).is_empty(), "a contact is scripted")
	assert_eq(_state.pending_battles.size(), 1)
	return _state.pending_battles[0]


func test_prepare_without_pending_battle_is_null() -> void:
	assert_true(ContactBattle.prepare(_state) == null)
	assert_eq(ContactBattle.problem(_state), "no_pending_battle")


func test_formation_ids_and_hexes_follow_the_company_refs() -> void:
	var pending := _contact()
	var ids := ContactBattle.formation_ids(pending)
	assert_eq(ids.size(), 2)
	var attacker := _state.get_formation(ids[0])
	var defender := _state.get_formation(ids[1])
	assert_eq(attacker.owner_id, pending.attacker)
	assert_eq(defender.owner_id, 1 - pending.attacker)
	assert_eq(ContactBattle.hexes(_state, pending), [attacker.coord, defender.coord])


func test_prepared_battle_uses_the_setup_exactly() -> void:
	var pending := _contact()
	var before := pending.to_dict()
	var played := ContactBattle.prepare(_state)
	assert_true(played != null, "the battle map is cut")
	assert_eq(pending.to_dict(), before, "the pending setup is not changed")
	assert_eq(played.map_id, ContactSettings.shipped().layer_for(_state.map_id))
	assert_eq(played.seed, pending.seed)
	assert_eq(played.factions, pending.factions)
	assert_eq(played.attacker, pending.attacker)
	for p in pending.conditions.size():
		assert_eq(played.conditions[p].to_dict(), pending.conditions[p].to_dict())
		assert_eq(played.missions[p].to_dict(), pending.missions[p].to_dict())
	var battle := Scenario.from_setup(played)
	assert_true(battle != null, "the battle opens")
	assert_eq(battle.units.size(), pending.companies.size())
	for i in pending.companies.size():
		var unit := battle.get_unit(i + 1)
		assert_eq(unit.owner_id, pending.companies[i].player, "company %d owner" % i)
		assert_eq(unit.hp, pending.companies[i].strength, "company %d strength" % i)
		assert_eq(unit.definition.id, pending.companies[i].unit_type)
	assert_eq(battle.player_factions, pending.factions)
	assert_eq(battle.rng.seed, pending.seed, "GameState.rng is seeded from the setup")


func test_same_setup_and_commands_give_the_same_result() -> void:
	_contact()
	var played := ContactBattle.prepare(_state)
	var first := GameSimulation.new(Scenario.from_setup(played))
	assert_true(MatchRunner.run(first, 40), "the AI plays the battle to its end")
	assert_true(first.state.is_over())
	var second := GameSimulation.new(Scenario.from_setup(played))
	for command: Command in first.history:
		assert_true(second.execute(CommandCodec.from_dict(command.to_dict())))
	assert_eq(
		BattleResult.from_battle(played, second.state).to_dict(),
		BattleResult.from_battle(played, first.state).to_dict()
	)


func test_played_result_resolves_the_pending_battle() -> void:
	_contact()
	var played := ContactBattle.prepare(_state)
	var battle := GameSimulation.new(Scenario.from_setup(played))
	assert_true(MatchRunner.run(battle, 40))
	var simulation := OperationalSimulation.new(_state)
	var command := ResolveBattleCommand.new(BattleResult.from_battle(played, battle.state))
	assert_eq(command.result.winner, battle.state.winner)
	assert_true(simulation.execute(command), "the result matches the pending battle")
	assert_eq(_state.pending_battles.size(), 0)
	assert_eq(ContactBattle.problem(_state), "no_pending_battle")
