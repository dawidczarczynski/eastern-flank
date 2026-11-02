extends TestCase
## SoundPlanner (TASK-123): which sound plays for which event, unit and camera state.

const UNITS_DIR := "res://data/units"
const BANK_PATH := "res://data/audio/sound_bank.tres"


func _unit(id: String) -> UnitDefinition:
	return load("%s/%s.tres" % [UNITS_DIR, id]) as UnitDefinition


func _planner() -> SoundPlanner:
	return SoundPlanner.new(load(BANK_PATH) as SoundBank)


func test_ui_actions_map_to_sound_ids() -> void:
	assert_eq(SoundPlanner.ui_sound(&"press"), &"ui_click")
	assert_eq(SoundPlanner.ui_sound(&"hover"), &"ui_hover")
	assert_eq(SoundPlanner.ui_sound(&"select_unit"), &"ui_select")
	assert_eq(SoundPlanner.ui_sound(&"move_order"), &"ui_move")
	assert_eq(SoundPlanner.ui_sound(&"attack_order"), &"ui_attack")
	assert_eq(SoundPlanner.ui_sound(&"rejected"), &"ui_error")
	assert_eq(SoundPlanner.ui_sound(&"toggle"), &"ui_toggle")
	assert_eq(SoundPlanner.ui_sound(&"nonsense"), &"")


func test_tank_infantry_and_mlrs_fire_differently() -> void:
	var tank := SoundPlanner.fire_sound(_unit("t72b3"))
	var infantry := SoundPlanner.fire_sound(_unit("pl_mech_infantry"))
	var mlrs := SoundPlanner.fire_sound(_unit("homar_k"))
	assert_eq(tank, &"tank_cannon")
	assert_eq(infantry, &"infantry_fight")
	assert_eq(mlrs, &"mlrs_rocket")
	assert_true(tank != infantry and infantry != mlrs and tank != mlrs)


func test_explosion_rules() -> void:
	assert_eq(SoundPlanner.impact_sound(3, true, false), &"explosion_large", "a death")
	assert_eq(SoundPlanner.impact_sound(3, false, false), &"explosion_small", "a hit")
	assert_eq(SoundPlanner.impact_sound(0, false, false), &"", "a miss with direct fire")
	assert_eq(SoundPlanner.impact_sound(0, false, true), &"explosion_small", "a rocket still lands")
	assert_true(SoundPlanner.impact_gain_db(0, true) < SoundPlanner.impact_gain_db(2, true))


func test_move_loops_per_unit() -> void:
	assert_eq(SoundPlanner.move_loops(_unit("t72b3")), [&"engine_diesel_heavy", &"move_tracks"])
	assert_eq(
		SoundPlanner.move_loops(_unit("bm27_uragan")), [&"engine_diesel_light", &"move_wheels"]
	)
	assert_eq(SoundPlanner.move_loops(_unit("ru_motor_rifle")), [] as Array[StringName])


func test_loop_envelope_ramps_within_half_a_second() -> void:
	assert_true(SoundPlanner.RAMP_TIME <= 0.5)
	var start := SoundPlanner.loop_envelope(true, 0.0)
	var running := SoundPlanner.loop_envelope(true, SoundPlanner.RAMP_TIME)
	assert_true(start.x < running.x, "pitch rises at start")
	assert_true(start.y < running.y, "volume rises at start")
	assert_eq(running, Vector2(1.0, 1.0))
	var stopped := SoundPlanner.loop_envelope(false, SoundPlanner.RAMP_TIME)
	assert_true(stopped.x < 1.0, "pitch falls at stop")
	assert_eq(stopped.y, 0.0, "silent when the stop ramp is over")


func test_ambient_needs_close_camera_and_forest() -> void:
	var p := _planner()
	var near := p.ambient_for(10.0, 0.8)
	assert_eq(near["id"], &"forest_ambience")
	assert_true(near["volume"] > 0.0)
	assert_eq(p.ambient_for(40.0, 0.8)["volume"], 0.0, "zoomed out")
	assert_eq(p.ambient_for(10.0, 0.05)["volume"], 0.0, "hardly any forest")
	assert_eq(p.ambient_for(10.0, 0.0)["volume"], 0.0, "no forest")


func test_forest_fraction_counts_tiles_around_the_centre() -> void:
	var grid := HexGrid.new()
	for c in _disc(2):
		grid.set_terrain(c, Terrain.Type.PLAINS)
	assert_eq(SoundPlanner.forest_fraction(grid, Vector2i.ZERO, 2), 0.0)
	for c in _disc(2):
		grid.set_terrain(c, Terrain.Type.FOREST)
	assert_eq(SoundPlanner.forest_fraction(grid, Vector2i.ZERO, 2), 1.0)
	grid.set_terrain(Vector2i.ZERO, Terrain.Type.PLAINS)
	var fraction := SoundPlanner.forest_fraction(grid, Vector2i.ZERO, 1)
	assert_true(absf(fraction - 6.0 / 7.0) < 0.001, "6 of 7 tiles: %f" % fraction)
	assert_eq(SoundPlanner.forest_fraction(grid, Vector2i(50, 50), 1), 0.0, "off the map")


func _disc(radius: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			if Hex.distance(Vector2i.ZERO, Vector2i(q, r)) <= radius:
				tiles.append(Vector2i(q, r))
	return tiles
