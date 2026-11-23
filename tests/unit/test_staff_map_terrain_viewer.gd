extends TestCase
## The devtools terrain viewer's picker (StaffMap.terrain_viewer): the bare map – no AI side, the
## HUD, the counters and the order overlays hidden – and nothing but Esc / G reacting to keys.


func test_the_picker_shows_the_bare_map() -> void:
	var map := StaffMap.new()
	map.auto_build = false
	map.terrain_viewer = true
	(Engine.get_main_loop() as SceneTree).root.add_child(map)
	assert_true(map.build_now(), "staff map builds")
	assert_eq(map.ai_side, -1)
	var hud := map.get_node("HUD") as CanvasLayer
	assert_false(hud.visible)
	assert_false(map.front_line().visible)
	var counters := map.get_node("CounterLayer")
	var shown := 0
	for child in counters.get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			shown += 1
	assert_eq(shown, 1, "only the place names stay")
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	var turn_before := map.simulation().state.turn
	map._unhandled_input(enter)
	assert_eq(map.simulation().state.turn, turn_before, "End turn is not reachable")
	map.queue_free()
