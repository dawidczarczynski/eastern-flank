extends TestCase
## Devtools look / performance switches and the arena unit editor (TASK-186b).
const Fixtures := preload("res://tests/fixtures.gd")


func after_each() -> void:
	DevTunables.deactivate()
	DevTunables.quality_choice = DevTunables.QualityChoice.AUTO
	DevTunables.true_size = false
	DevTunables.look_name = LookPreset.DEFAULT_PRESET
	DevTunables.grid_on = true
	DevTunables.fps_overlay = false
	DevTunables.unlock_camera = false
	VisualScale.reset()
	LookPreset.reset()


func test_defaults_are_todays_behaviour() -> void:
	DevTunables.activate()
	assert_eq(DevTunables.quality_override(), -1)
	assert_eq(DevTunables.scale_preset(), VisualScale.DEFAULT_PRESET)
	assert_eq(DevTunables.look_preset(), LookPreset.DEFAULT_PRESET)
	assert_true(DevTunables.grid_enabled())
	assert_false(DevTunables.fps_overlay)
	assert_eq(DevTunables.camera_min_distance(), CameraMath.MIN_DISTANCE)
	assert_eq(DevTunables.camera_max_distance(), CameraMath.MAX_DISTANCE)


func test_overrides_count_only_while_active() -> void:
	DevTunables.quality_choice = DevTunables.QualityChoice.LOW
	DevTunables.true_size = true
	DevTunables.look_name = &"overcast"
	DevTunables.grid_on = false
	DevTunables.unlock_camera = true
	assert_eq(DevTunables.quality_override(), -1)
	assert_eq(DevTunables.scale_preset(), VisualScale.DEFAULT_PRESET)
	assert_eq(DevTunables.look_preset(), LookPreset.DEFAULT_PRESET)
	assert_true(DevTunables.grid_enabled())
	assert_eq(DevTunables.camera_min_distance(), CameraMath.MIN_DISTANCE)
	DevTunables.activate()
	assert_eq(DevTunables.quality_override(), GraphicsQuality.Level.LOW)
	assert_eq(DevTunables.scale_preset(), VisualScale.TRUE_PRESET)
	assert_eq(DevTunables.look_preset(), &"overcast")
	assert_false(DevTunables.grid_enabled())


func test_quality_choices_map_to_levels() -> void:
	DevTunables.activate()
	DevTunables.quality_choice = DevTunables.QualityChoice.HIGH
	assert_eq(DevTunables.quality_override(), GraphicsQuality.Level.HIGH)


func test_unlocking_the_camera_halves_the_minimum_and_doubles_the_maximum() -> void:
	DevTunables.activate()
	DevTunables.unlock_camera = true
	assert_eq(DevTunables.camera_min_distance(), CameraMath.MIN_DISTANCE * 0.5)
	assert_eq(DevTunables.camera_max_distance(), CameraMath.MAX_DISTANCE * 2.0)
	assert_eq(CameraMath.zoom(CameraMath.MIN_DISTANCE, -50.0), CameraMath.MIN_DISTANCE * 0.5)
	DevTunables.unlock_camera = false
	assert_eq(CameraMath.zoom(CameraMath.MIN_DISTANCE, -50.0), CameraMath.MIN_DISTANCE)


func test_leaving_restores_the_default_scale_and_look() -> void:
	DevTunables.true_size = true
	DevTunables.look_name = &"overcast"
	DevTunables.activate()
	assert_true(VisualScale.is_true_size())
	DevTunables.deactivate()
	assert_false(VisualScale.is_true_size())


func test_fps_text_shows_frames_and_frame_time() -> void:
	assert_eq(FpsOverlay.format(60.0), "60 FPS  16.7 ms")
	assert_eq(FpsOverlay.format(0.0), "0 FPS  0.0 ms")


func _arena_with_unit() -> Array:
	var arena := ArenaController.new()
	var state := arena._initial_state()
	arena._sim = GameSimulation.new(state)
	var definition := Fixtures.generic_tank()
	var unit := state.add_unit(0, definition, Vector2i(2, 2))
	return [arena, unit]


func test_editing_hp_moves_and_flags_goes_to_the_state() -> void:
	var pair := _arena_with_unit()
	var arena: ArenaController = pair[0]
	var unit: Unit = pair[1]
	arena._selected_unit_id = unit.id
	arena.set_selected_hp(3)
	assert_eq(unit.hp, 3)
	arena.set_selected_moves(0)
	assert_eq(unit.moves_left, 0)
	arena.set_selected_dug(true)
	arena.set_selected_ambush(true)
	assert_true(unit.dug)
	assert_true(unit.ambush)
	arena.free()


func test_edited_values_are_clamped_to_the_unit_range() -> void:
	var pair := _arena_with_unit()
	var arena: ArenaController = pair[0]
	var unit: Unit = pair[1]
	arena._selected_unit_id = unit.id
	arena.set_selected_hp(0)
	assert_eq(unit.hp, 1)
	arena.set_selected_hp(9999)
	assert_eq(unit.hp, unit.definition.max_hp)
	arena.set_selected_moves(9999)
	assert_eq(unit.moves_left, unit.definition.move_points)
	arena.set_selected_moves(-4)
	assert_eq(unit.moves_left, 0)
	arena.free()


func test_editing_without_a_selection_changes_nothing() -> void:
	var pair := _arena_with_unit()
	var arena: ArenaController = pair[0]
	var unit: Unit = pair[1]
	var hp := unit.hp
	arena.set_selected_hp(1)
	arena.set_selected_dug(true)
	assert_eq(unit.hp, hp)
	assert_false(unit.dug)
	arena.free()


func test_stat_edit_changes_only_the_selected_units_copy() -> void:
	var pair := _arena_with_unit()
	var arena: ArenaController = pair[0]
	var unit: Unit = pair[1]
	var shared := unit.definition
	var shared_range := shared.max_range_m
	arena._selected_unit_id = unit.id
	arena.set_selected_stat(2000, &"max_range_m")
	arena.set_selected_stat(7, &"attack")
	assert_eq(unit.definition.max_range_m, 2000)
	assert_eq(unit.definition.attack, 7)
	assert_true(unit.definition != shared)
	assert_eq(shared.max_range_m, shared_range)
	arena.reset_selected_stats()
	assert_true(unit.definition == shared)
	arena.free()


func test_stat_edit_keeps_ranges_ordered_and_hp_within_max() -> void:
	var pair := _arena_with_unit()
	var arena: ArenaController = pair[0]
	var unit: Unit = pair[1]
	arena._selected_unit_id = unit.id
	arena.set_selected_stat(5000, &"effective_range_m")
	assert_true(unit.definition.max_range_m >= 5000)
	arena.set_selected_stat(1000, &"max_range_m")
	assert_true(unit.definition.effective_range_m <= 1000)
	arena.set_selected_stat(1, &"max_hp")
	assert_eq(unit.hp, 1)
	arena.set_selected_fire_mode(UnitDefinition.FIRE_INDIRECT)
	assert_true(unit.definition.is_indirect())
	arena.free()


func test_ignoring_line_of_sight_is_a_state_switch() -> void:
	var pair := _arena_with_unit()
	var arena: ArenaController = pair[0]
	var state: GameState = arena._sim.state
	var far := Vector2i(10, 2)
	state.smoke_hexes.append({"coord": Vector2i(6, 2), "owner": 0})
	var blocked := not state.has_line_of_sight(Vector2i(2, 2), Vector2i(9, 2))
	arena.set_ignore_line_of_sight(true)
	assert_true(blocked)
	assert_true(state.has_line_of_sight(Vector2i(2, 2), Vector2i(9, 2)))
	assert_true(state.has_line_of_sight(Vector2i(2, 2), far))
	arena.set_ignore_line_of_sight(false)
	assert_false(state.has_line_of_sight(Vector2i(2, 2), Vector2i(9, 2)))
	arena.free()
