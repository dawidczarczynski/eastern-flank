extends TestCase
## The objectives layer of the staff map (TASK-175b, TASK-177): markers per own / neutral objective,
## the main link's two end markers and tag (no route), redraws only on a matching change, the key /
## Map options toggle forced on by the window, marker click.

static var _map: StaffMap
static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func before_each() -> void:
	_map.close_objectives()
	var layer := _map.objectives_layer()
	layer.set_enabled(true)
	layer.set_selected(-1)


func test_layer_shows_only_the_viewers_objectives_and_is_on_by_default() -> void:
	var layer := _map.objectives_layer()
	var rows := layer.rows()
	assert_eq(rows.size(), 3, "NATO: its link, Chernyakhovsk, Grodno")
	assert_eq(rows[0]["kind"], StaffMapObjectivesModel.GAP)
	for row in rows:
		assert_true(row["yours"])
	assert_true(layer.is_shown())


func test_main_tag_hangs_between_the_two_ends() -> void:
	var layer := _map.objectives_layer()
	var def := _map.simulation().state.definition
	var row: Dictionary = layer.rows()[0]
	assert_eq(row["tag"], "SUWAŁKI ↔ KAUNAS ▪ CONNECTED +%d" % def.gap_open_points)
	var a := _map._screen_of_hex(def.nato_link_from)
	var b := _map._screen_of_hex(def.nato_link_to)
	assert_true(absf(layer.hit_rect(0).get_center().x - (a.x + b.x) * 0.5) < 1.0)


func test_click_on_the_main_tag_or_an_end_opens_the_window_on_its_row() -> void:
	var layer := _map.objectives_layer()
	var def := _map.simulation().state.definition
	var tag := layer.hit_rect(0).get_center()
	assert_eq(layer.marker_at(tag), 0)
	assert_eq(layer.marker_at(_map._screen_of_hex(def.nato_link_to)), 0, "the Kaunas end")
	_map.click_at(tag)
	assert_true(_map.objectives_window().is_open())
	assert_eq(_map.objectives_window().selected_row(), 0)


func test_redraws_only_on_objective_changed_or_a_zoom_level_change() -> void:
	var layer := _map.objectives_layer()
	var before := layer.redraw_count()
	_map.simulation().event_emitted.emit({"type": &"unit_moved"})
	assert_eq(layer.redraw_count(), before, "unrelated event")
	_map.simulation().event_emitted.emit(
		{"type": &"objective_changed", "kind": &"corridor_counter"}
	)
	assert_eq(layer.redraw_count(), before + 1, "matching event")
	layer.set_level(layer._level)
	assert_eq(layer.redraw_count(), before + 1, "same level")
	layer.set_level(0 if layer._level != 0 else 2)
	assert_eq(layer.redraw_count(), before + 2, "level change")


func test_names_from_z1_and_always_for_the_selected_one() -> void:
	var layer := _map.objectives_layer()
	var level := layer._level
	layer.set_level(0)
	layer.set_selected(2)
	assert_false(layer.name_shown(1))
	assert_true(layer.name_shown(2))
	layer.set_level(1)
	assert_true(layer.name_shown(1))
	layer.set_level(level)


func test_key_toggle_hides_and_the_window_forces_it_back() -> void:
	var layer := _map.objectives_layer()
	_map.toggle_objective_layer()
	assert_false(layer.is_shown())
	assert_eq(_map.options_window().option(StaffMap.ACTION_OBJECTIVE_LAYER).state_text(), "OFF")
	_map.open_objectives()
	assert_true(layer.is_shown(), "forced while the window is open")
	_map.close_objectives()
	assert_false(layer.is_shown(), "previous state restored")
	_map.toggle_objective_layer()
	assert_true(layer.is_shown())


func test_click_on_a_marker_opens_the_window_on_that_row() -> void:
	var layer := _map.objectives_layer()
	var rect := layer.hit_rect(2)
	var plate := Vector2(rect.get_center().x, rect.end.y - 3.0)  # below the ring: no counter there
	assert_eq(layer.marker_at(plate), 2)
	_map.click_at(plate)
	assert_true(_map.objectives_window().is_open())
	assert_eq(_map.objectives_window().selected_row(), 2)


func test_a_hidden_layer_takes_no_clicks() -> void:
	var layer := _map.objectives_layer()
	var centre := layer.hit_rect(2).get_center()
	_map.toggle_objective_layer()
	assert_eq(layer.marker_at(centre), -1)
