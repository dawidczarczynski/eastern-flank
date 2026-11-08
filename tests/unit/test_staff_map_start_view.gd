extends TestCase
## The staff map opens on the side to play when no --side is given (follow on): Russia moves first
## in the operation, so the first turn must already show its formations as own (regression: the
## view stayed on NATO until the first End turn, so no order could be given to Russia).

var _map: StaffMap


func before_each() -> void:
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = -1
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)


func after_each() -> void:
	_map.free()


func test_viewer_starts_on_the_side_to_play() -> void:
	assert_true(_map.build_now(), "staff map builds")
	var sim := _map.simulation()
	assert_eq(_map.viewer_player, sim.state.current_player, "viewer is the side to play")
	assert_eq(
		sim.state.current_player, sim.state.first_player, "the first turn belongs to first_player"
	)


func test_click_that_gives_an_order_deselects_the_formation() -> void:
	assert_true(_map.build_now(), "staff map builds")
	var sim := _map.simulation()
	for f in sim.state.formations:
		if f.owner_id != sim.state.current_player:
			continue
		for dq in [3, -3, 4, -4]:
			var hex: Vector2i = f.coord + Vector2i(dq, 0)
			_map.select_formation(f.id)
			_map.click_at(_map._screen_of_hex(hex))
			if f.order != null:
				assert_eq(_map.selected_formation(), &"", "deselected after the order")
				return
	assert_true(false, "no formation could be ordered by a click")
