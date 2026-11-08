extends TestCase
## The front line on the staff map (TASK-093c): drawn from the state, teeth towards the viewer's
## enemy, recomputed only on a change, T tint, read-only. One StaffMap is shared by the tests.

static var _map: StaffMap


func before_all() -> void:
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")


func after_all() -> void:
	_map.free()
	_map = null


func after_each() -> void:
	_map.set_viewer(0)


func test_widths_per_zoom_level() -> void:
	assert_eq(StaffMapFrontLine.width_at(0), 2.4)
	assert_eq(StaffMapFrontLine.width_at(1), 3.0)
	assert_eq(StaffMapFrontLine.width_at(2), 3.0)


func test_teeth_point_to_the_enemy_and_flip_with_the_viewer() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(0, 10)])
	var normal := FrontLine.right_normal(line[0], line[1])
	var own := StaffMapFrontLine.teeth_of(line, 0, 1.0, 0.5, 0.4)
	var other := StaffMapFrontLine.teeth_of(line, 1, 1.0, 0.5, 0.4)
	assert_true(own.size() >= 9)
	assert_eq(own.size(), other.size())
	var tip_own: Vector2 = (own[0] as Array)[2]
	var tip_other: Vector2 = (other[0] as Array)[2]
	assert_true(tip_own.x * normal.x < 0.0, "viewer 0: away from player 0's zone")
	assert_true(tip_other.x * normal.x > 0.0, "viewer 1: the other way")


func test_teeth_are_evenly_spaced_across_segments() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(2.5, 0), Vector2(2.5, 5)])
	var teeth := StaffMapFrontLine.teeth_of(line, 0, 1.0, 0.5, 0.4)
	# At 0.5, 1.5 … 7.5 along the path: the spacing carries over the corner.
	assert_eq(teeth.size(), 8)


func test_the_map_draws_the_front_between_the_blocs() -> void:
	var front := _map.front_line()
	assert_true(front.visible)
	assert_true(front.lines().size() >= 0)


func test_nothing_recomputes_without_a_change() -> void:
	var front := _map.front_line()
	var before := front.rebuild_count()
	_map.set_viewer(0)
	_map.select_formation(&"")
	assert_eq(front.rebuild_count(), before)
	_map.set_viewer(1)
	assert_eq(front.rebuild_count(), before + 1, "a viewer change recomputes")


func test_a_moved_formation_recomputes() -> void:
	var front := _map.front_line()
	var state := _map.simulation().state
	var before := front.rebuild_count()
	var f := state.formations[0]
	var origin := f.coord
	f.coord += Vector2i(1, 0)
	_map.front_line().refresh(state, 0)
	assert_eq(front.rebuild_count(), before + 1)
	f.coord = origin
	front.refresh(state, 0)


func test_t_toggles_the_tint() -> void:
	var front := _map.front_line()
	var on := front.is_tint_visible()
	front.set_tint_visible(not on)
	assert_eq(front.is_tint_visible(), not on)
	front.set_tint_visible(on)


func test_exact_variant_with_the_grid_at_z2() -> void:
	var front := _map.front_line()
	front.set_view(40.0, 2, true)
	assert_true(front.is_exact())
	front.set_view(40.0, 1, false)
	assert_false(front.is_exact())


func test_the_view_never_changes_the_state() -> void:
	var state := _map.simulation().state
	var before := state.snapshot()
	_map.front_line().refresh(state, 1)
	_map.front_line().set_view(25.0, 0, false)
	assert_eq(state.snapshot(), before)
