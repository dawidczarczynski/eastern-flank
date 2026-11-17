extends TestCase
## Tactical AI of rocket artillery (TASK-170b, GDD "Formations"): an `mlrs` company fires from
## where it stands when it can, otherwise advances only to the first tile that puts an enemy in
## range, never inside its minimum range and at least ARTILLERY_STANDOFF hexes behind the
## front-most own direct-fire company.

const Fixtures := preload("res://tests/fixtures.gd")

var state: GameState
var sim: GameSimulation
var attacks: Array[Dictionary] = []


## An open 0 m plain of radius 15; player 0 is the AI.
func before_each() -> void:
	var grid := Fixtures.plains_grid(15)
	for c in grid.coords():
		grid.set_elevation(c, 0.0)
	state = GameState.new(grid, 2, 1)
	sim = GameSimulation.new(state)
	attacks.clear()
	sim.event_emitted.connect(
		func(e: Dictionary) -> void:
			if e["type"] == &"unit_attacked" and not e["counter"]:
				attacks.append(e)
	)


## Rocket artillery (3 move points) that hits from `min_hexes` to `max_hexes` hexes.
static func _artillery(max_hexes: int, min_hexes: int = 3) -> UnitDefinition:
	var definition := Fixtures.fighter(6, 1, 6)
	definition.id = &"test_mlrs"
	definition.unit_class = &"mlrs"
	return Fixtures.set_range(
		definition, max_hexes, max_hexes, min_hexes, UnitDefinition.FIRE_INDIRECT
	)


## A weak enemy that cannot shoot back beyond 1 hex.
static func _target() -> UnitDefinition:
	return Fixtures.fighter(2, 1, 10, 1)


## A direct-fire company of the AI (range 1) that cannot reach anything this turn.
static func _infantry() -> UnitDefinition:
	var definition := Fixtures.fighter(4, 2, 10, 1)
	definition.move_points = 0
	return definition


func _attacks_by(unit: Unit) -> int:
	return attacks.filter(func(e: Dictionary) -> bool: return e["attacker_id"] == unit.id).size()


func test_artillery_with_an_enemy_in_range_fires_without_moving() -> void:
	var gun := state.add_unit(0, _artillery(8), Vector2i(-6, 0))
	state.add_unit(1, _target(), Vector2i(0, 0))
	AiPlayer.new().take_turn(sim)
	assert_eq(gun.coord, Vector2i(-6, 0))
	assert_eq(_attacks_by(gun), 1)


func test_artillery_advances_only_to_the_first_tile_in_range() -> void:
	var gun := state.add_unit(0, _artillery(6), Vector2i(-8, 0))
	var enemy := state.add_unit(1, _target(), Vector2i(0, 0))
	state.add_unit(0, _infantry(), Vector2i(-2, 0))
	AiPlayer.new().take_turn(sim)
	assert_eq(Hex.distance(gun.coord, enemy.coord), 6)
	assert_eq(Hex.distance(gun.coord, Vector2i(-8, 0)), 2)
	assert_eq(_attacks_by(gun), 1)


## The front-most own direct-fire company stands 7 hexes from the enemy, so the guns stay at
## 9 or more – out of their 8-hex range: they close up to 9 and hold their fire.
func test_artillery_stays_two_hexes_behind_the_front() -> void:
	var gun := state.add_unit(0, _artillery(8), Vector2i(-11, 0))
	var enemy := state.add_unit(1, _target(), Vector2i(0, 0))
	state.add_unit(0, _infantry(), Vector2i(-7, 0))
	AiPlayer.new().take_turn(sim)
	assert_eq(Hex.distance(gun.coord, enemy.coord), 9)
	assert_eq(_attacks_by(gun), 0)


## Out of range and ahead of its own infantry: the guns fall back rather than end their move
## nearer the enemy than the infantry.
func test_artillery_ahead_of_the_front_falls_back() -> void:
	var gun := state.add_unit(0, _artillery(3), Vector2i(-5, 0))
	var enemy := state.add_unit(1, _target(), Vector2i(0, 0))
	state.add_unit(0, _infantry(), Vector2i(-8, 1))
	AiPlayer.new().take_turn(sim)
	assert_true(Hex.distance(gun.coord, enemy.coord) >= 8, str(gun.coord))


## Inside its minimum range the guns cannot fire: they move out of it (never closer) and fire.
func test_artillery_inside_its_minimum_range_moves_out_and_fires() -> void:
	var gun := state.add_unit(0, _artillery(8, 3), Vector2i(-2, 0))
	var enemy := state.add_unit(1, _target(), Vector2i(0, 0))
	AiPlayer.new().take_turn(sim)
	assert_true(Hex.distance(gun.coord, enemy.coord) >= 3, str(gun.coord))
	assert_eq(_attacks_by(gun), 1)


## Never advances inside its minimum range to get in range: an enemy only hittable from 3..4
## hexes, the front far ahead – the guns stop at 4, not nearer.
func test_artillery_never_moves_inside_its_minimum_range() -> void:
	var gun := state.add_unit(0, _artillery(4, 3), Vector2i(-6, 0))
	var enemy := state.add_unit(1, _target(), Vector2i(0, 0))
	AiPlayer.new().take_turn(sim)
	assert_eq(Hex.distance(gun.coord, enemy.coord), 4)
	assert_eq(_attacks_by(gun), 1)


## Objectives are for the direct-fire companies: guns in range keep firing from where they stand.
func test_artillery_does_not_rush_an_objective() -> void:
	var hexes: Array[Vector2i] = [Vector2i(-3, 0)]
	state.set_objectives(
		Fixtures.objectives(
			0, hexes, [1], [Fixtures.condition(VictoryCondition.Kind.TAKE_HEXES, 0, hexes)]
		)
	)
	var gun := state.add_unit(0, _artillery(8), Vector2i(-6, 0))
	state.add_unit(1, _target(), Vector2i(0, 0))
	AiPlayer.new().take_turn(sim)
	assert_eq(gun.coord, Vector2i(-6, 0))
	assert_eq(_attacks_by(gun), 1)


## In a 7 v 7 contact battle no AI rocket-artillery company ever stands inside its minimum range
## of the nearest enemy, nor nearer the enemy than its side's front-most direct-fire company
## after its own move while it could stand farther back.
func test_contact_battle_artillery_stays_behind_the_line() -> void:
	var battle := Scenario.build("contact_battle", 3, FactionRegistry.DEFAULT_IDS)
	var game := GameSimulation.new(battle)
	var ai := AiPlayer.new()
	var checked := 0
	while not battle.is_over() and battle.turn <= 6:
		var player := battle.current_player
		ai.take_turn(game)
		for unit in battle.units_of(player):
			if not unit.definition.is_indirect() or not unit.is_alive():
				continue
			var nearest := _nearest_enemy_distance(battle, unit)
			assert_true(nearest >= unit.definition.min_hexes(), "%s at %d" % [unit.coord, nearest])
			checked += 1
	assert_true(checked > 0)


static func _nearest_enemy_distance(battle: GameState, unit: Unit) -> int:
	var best := 1 << 30
	for other: Unit in battle.units.values():
		if other.owner_id != unit.owner_id and other.is_alive():
			best = mini(best, Hex.distance(unit.coord, other.coord))
	return best
