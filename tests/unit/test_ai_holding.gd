extends TestCase
## A defending AI side (HOLD_HEXES and no TAKE_HEXES – the defender of a contact battle,
## TASK-170b) waits for the enemy around its objective instead of marching out to meet it; it
## still moves to fire when it can reach a firing tile.

const Fixtures := preload("res://tests/fixtures.gd")
const GOAL := Vector2i(5, 0)

var state: GameState
var sim: GameSimulation
var attacks: Array[Dictionary] = []


## An open plain; player 1 (the AI, to move) holds GOAL and already stands on it; player 0 must
## take it.
func before_each() -> void:
	var grid := Fixtures.plains_grid(15)
	for c in grid.coords():
		grid.set_elevation(c, 0.0)
	state = GameState.new(grid, 2, 1)
	var hexes: Array[Vector2i] = [GOAL]
	(
		state
		. set_objectives(
			(
				Fixtures
				. objectives(
					12,
					hexes,
					[1],
					[
						Fixtures.condition(VictoryCondition.Kind.TAKE_HEXES, 0, hexes),
						Fixtures.condition(VictoryCondition.Kind.HOLD_HEXES, 1, hexes),
					]
				)
			)
		)
	)
	state.add_unit(1, Fixtures.fighter(4, 2), GOAL)
	sim = GameSimulation.new(state)
	attacks.clear()
	sim.event_emitted.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"unit_attacked" and not e["counter"]:
				attacks.append(e)
	)


func _ai_turn() -> void:
	sim.execute(EndTurnCommand.new())
	AiPlayer.new().take_turn(sim)


func test_defender_out_of_reach_falls_back_to_its_objective() -> void:
	var defender := state.add_unit(1, Fixtures.fighter(4, 2), Vector2i(8, 0))
	var enemy := state.add_unit(0, Fixtures.fighter(4, 2), Vector2i(13, 0))
	_ai_turn()
	assert_true(Hex.distance(defender.coord, GOAL) < 3, str(defender.coord))
	assert_true(Hex.distance(defender.coord, enemy.coord) > 5, str(defender.coord))
	assert_eq(attacks.size(), 0)


func test_defender_still_moves_to_fire_when_it_can() -> void:
	var defender := state.add_unit(1, Fixtures.fighter(4, 2), Vector2i(8, 0))
	var enemy := state.add_unit(0, Fixtures.fighter(4, 2), Vector2i(11, 0))
	_ai_turn()
	assert_eq(Hex.distance(defender.coord, enemy.coord), 1)
	assert_eq(attacks.size(), 1)


## The attacker of the same battle still closes in on the enemy.
func test_attacker_still_closes_in() -> void:
	var hexes: Array[Vector2i] = [GOAL]
	(
		state
		. set_objectives(
			(
				Fixtures
				. objectives(
					12,
					hexes,
					[0],
					[
						Fixtures.condition(VictoryCondition.Kind.TAKE_HEXES, 1, hexes),
						Fixtures.condition(VictoryCondition.Kind.HOLD_HEXES, 0, hexes),
					]
				)
			)
		)
	)
	var attacker := state.add_unit(1, Fixtures.fighter(4, 2), Vector2i(8, 0))
	state.add_unit(0, Fixtures.fighter(4, 2), Vector2i(13, 0))
	_ai_turn()
	assert_eq(attacker.coord.x, 11)
