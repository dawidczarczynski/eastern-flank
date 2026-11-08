extends TestCase
## Route preview on the staff map (TASK-092c): smoothing, the numbers behind the label, the
## controller (hover, keys 1 / 2 / 3, read-only).

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


static func _row_state(enemy_at := Vector2i(100, 100)) -> OperationalState:
	var grid := HexGrid.new()
	for q in range(0, 10):
		grid.set_terrain(Vector2i(q, 0), Terrain.Type.PLAINS)
	grid.set_terrain(Vector2i(9, 0), Terrain.Type.WATER)
	var state := OperationalState.new()
	state.grid = grid
	state.formations.append(_formation(&"f", 0, Vector2i.ZERO))
	if enemy_at != Vector2i(100, 100):
		state.formations.append(_formation(&"e", 1, enemy_at))
	return state


static func _formation(id: StringName, owner: int, coord: Vector2i) -> Formation:
	var f := Formation.new()
	f.id = id
	f.owner_id = owner
	f.coord = coord
	return f


# --- smoothing ---


func test_chaikin_keeps_the_end_points() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(8, 4)])
	var smooth := StaffMapRoute.chaikin(points)
	assert_eq(smooth[0], points[0])
	assert_eq(smooth[smooth.size() - 1], points[points.size() - 1])
	assert_true(smooth.size() > points.size())


func test_chaikin_short_lines_are_unchanged() -> void:
	var two := PackedVector2Array([Vector2(1, 2), Vector2(3, 4)])
	assert_eq(StaffMapRoute.chaikin(two), two)


func test_smoothed_route_starts_and_ends_on_hex_centres() -> void:
	var route: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)]
	var line := StaffMapRoute.smoothed_line(Vector2i.ZERO, route)
	assert_eq(line[0], StaffMapRoute.centre(Vector2i.ZERO))
	assert_eq(line[line.size() - 1], StaffMapRoute.centre(Vector2i(2, 1)))


# --- preview numbers ---


func test_preview_matches_the_forecast() -> void:
	var state := _row_state()
	var formation := state.get_formation(&"f")
	var result := StaffMapRoute.preview(state, formation, Vector2i(6, 0), true, 8)
	assert_eq(result["cost"], 12)
	assert_eq(result["turns"], 2)
	assert_eq(result["stop"], OperationalRoutes.STOP_ARRIVED)
	assert_eq(result["reason"], "")
	var expected := OperationalRoutes.forecast(state, formation, Vector2i(6, 0), 8, true)
	assert_eq(result["stops"], expected)


func test_preview_stops_in_contact() -> void:
	var state := _row_state(Vector2i(5, 0))
	var result := StaffMapRoute.preview(state, state.get_formation(&"f"), Vector2i(4, 0), false, 8)
	assert_eq(result["stop"], OperationalRoutes.STOP_ARRIVED, "arriving next to an enemy")
	var through := _row_state(Vector2i(4, 1))
	through.grid.set_terrain(Vector2i(4, 1), Terrain.Type.PLAINS)
	var past := StaffMapRoute.preview(
		through, through.get_formation(&"f"), Vector2i(6, 0), false, 8
	)
	assert_eq(past["stop"], OperationalRoutes.STOP_CONTACT)
	assert_eq(past["stops"][past["stops"].size() - 1], Vector2i(4, 0))


func test_enemy_hex_is_a_target_for_attack_posture() -> void:
	var state := _row_state(Vector2i(5, 0))
	var formation := state.get_formation(&"f")
	var attack := StaffMapRoute.preview(state, formation, Vector2i(5, 0), false, 8)
	assert_eq(attack["reason"], "")
	assert_eq(attack["stop"], OperationalRoutes.STOP_CONTACT)
	assert_eq(attack["stops"][attack["stops"].size() - 1], Vector2i(4, 0))


func test_unreachable_reasons() -> void:
	var state := _row_state(Vector2i(5, 0))
	var formation := state.get_formation(&"f")
	assert_eq(
		StaffMapRoute.preview(state, formation, Vector2i(9, 0), false, 8)["reason"], "ROUTE_WATER"
	)
	assert_eq(
		StaffMapRoute.preview(state, formation, Vector2i(5, 0), true, 8)["reason"], "ROUTE_ENEMY"
	)
	assert_eq(
		StaffMapRoute.preview(state, formation, Vector2i(5, 5), false, 8)["reason"],
		"ROUTE_NO_ROUTE"
	)
	assert_true(StaffMapRoute.preview(state, formation, Vector2i.ZERO, false, 8).is_empty())
	state.formations.append(_formation(&"mate", 0, Vector2i(2, 0)))
	assert_eq(
		StaffMapRoute.preview(state, formation, Vector2i(2, 0), false, 8)["reason"],
		"ROUTE_OCCUPIED"
	)


func test_label_text() -> void:
	var state := _row_state()
	var result := StaffMapRoute.preview(state, state.get_formation(&"f"), Vector2i(6, 0), true, 8)
	assert_eq(StaffMapRoutePreview.label_text(result), "12 PTS · 2 TURNS · ARRIVED")


# --- controller ---


func _own_formation() -> Formation:
	for formation in _map.simulation().state.formations:
		if formation.owner_id == 0:
			return formation
	return null


func _far_hex(formation: Formation) -> Vector2i:
	var state := _map.simulation().state
	var posture := OperationalPosture.find(formation.posture)
	for c: Vector2i in state.grid.coords():
		if Hex.distance(c, formation.coord) == 4:
			if not OperationalRoutes.plan(state, formation, c, posture.avoids_contact).is_empty():
				return c
	return StaffMapRoutePreview.OFF


func test_hover_shows_the_route_without_a_command() -> void:
	var simulation := _map.simulation()
	var formation := _own_formation()
	_map.select_formation(formation.id)
	var before := simulation.state.snapshot()
	var history := simulation.history.size()
	var target := _far_hex(formation)
	assert_true(target != StaffMapRoutePreview.OFF, "a reachable hex exists")
	var preview := _map.route_preview()
	preview.set_hex(target)
	preview.rebuild()
	assert_true(not preview.shown().is_empty())
	assert_eq(preview.shown()["route"].size() > 0, true)
	assert_eq(simulation.state.snapshot(), before, "hover leaves the state alone")
	assert_eq(simulation.history.size(), history, "no command was created")


func test_hostile_selection_has_no_order_rows_and_no_preview() -> void:
	var enemy: Formation = null
	for formation in _map.simulation().state.formations:
		if formation.owner_id != 0:
			enemy = formation
			break
	_map.select_formation(enemy.id)
	assert_false(_map.formation_panel().order_visible())
	var preview := _map.route_preview()
	preview.set_hex(enemy.coord + Vector2i(1, 0))
	preview.rebuild()
	assert_true(preview.shown().is_empty())
	_map.select_formation(&"")


func test_hover_is_debounced() -> void:
	var formation := _own_formation()
	_map.select_formation(formation.id)
	var preview := _map.route_preview()
	preview.rebuild(1000)
	var plans := preview.plans_made()
	preview.set_hex(formation.coord + Vector2i(1, 0))
	preview.tick(1010)
	assert_eq(preview.plans_made(), plans, "too soon")
	assert_true(preview.is_pending())
	preview.tick(1000 + StaffMapRoutePreview.DEBOUNCE_MSEC)
	assert_eq(preview.plans_made(), plans + 1)
	assert_false(preview.is_pending())
	_map.select_formation(&"")
