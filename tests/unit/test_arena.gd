extends TestCase
## The dev arena's starting state: flat, empty, two sides, nothing ends the battle.


func test_arena_starts_empty_flat_and_without_victory_conditions() -> void:
	var arena := ArenaController.new()
	var state := arena._initial_state()
	arena.free()
	assert_true(state != null)
	assert_eq(state.player_count, 2)
	assert_eq(state.units.size(), 0)
	assert_true(state.objectives.conditions.is_empty())
	for c in state.grid.coords():
		assert_eq(state.grid.get_terrain(c), Terrain.Type.PLAINS)
	assert_eq(
		state.grid.coords().size(), ArenaController.ARENA_WIDTH * ArenaController.ARENA_HEIGHT
	)


func test_ending_the_turn_on_an_empty_arena_passes_the_command_without_ending_the_battle() -> void:
	var arena := ArenaController.new()
	var state := arena._initial_state()
	arena.free()
	var sim := GameSimulation.new(state)
	assert_true(sim.execute(EndTurnCommand.new()))
	assert_eq(state.current_player, 1)
	assert_false(state.is_over())
