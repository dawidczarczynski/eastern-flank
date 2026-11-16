extends TestCase
## The T+1 march reach contour on the staff map (TASK-155): shown only while a formation is armed
## or aimed, always the march reach, recomputed only on a change, read-only. One StaffMap is
## shared by the tests.

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
	_map.select_formation(&"")


func _own() -> Formation:
	for f in _map.simulation().state.formations:
		if f.owner_id == 0:
			return f
	return null


func test_hidden_while_nothing_is_armed() -> void:
	assert_false(_map.reach_contour().visible)


func test_shown_for_an_armed_formation_with_the_march_reach() -> void:
	var layer := _map.reach_contour()
	var state := _map.simulation().state
	var f := _own()
	layer.refresh(state, f, true)
	assert_true(layer.visible)
	var posture := OperationalPosture.find(&"march")
	var expected := OperationalRoutes.reach(state, f, OperationalOrders.budget(f, posture))
	assert_eq(layer.reach(), expected)
	assert_false(layer.reach().is_empty())
	layer.refresh(state, f, false)
	assert_false(layer.visible)


func test_nothing_recomputes_without_a_change() -> void:
	var layer := _map.reach_contour()
	var state := _map.simulation().state
	var f := _own()
	layer.refresh(state, f, true)
	var before := layer.rebuild_count()
	layer.refresh(state, f, true)
	layer.refresh(state, f, true)
	assert_eq(layer.rebuild_count(), before)
	var origin := f.coord
	f.coord += Vector2i(1, 0)
	layer.refresh(state, f, true)
	assert_eq(layer.rebuild_count(), before + 1, "a moved formation recomputes")
	f.coord = origin
	layer.refresh(state, f, false)


func test_the_view_never_changes_the_state() -> void:
	var state := _map.simulation().state
	var before := state.snapshot()
	_map.reach_contour().refresh(state, _own(), true)
	assert_eq(state.snapshot(), before)
