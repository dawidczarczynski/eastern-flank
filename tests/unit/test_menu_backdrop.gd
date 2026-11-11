extends TestCase
## MenuBackdrop (docs/design/operational_map/main_menu.html, variant A) and ChamferBox.


func test_cover_fills_the_view_and_keeps_the_aspect() -> void:
	var frame := MenuBackdrop.cover(Vector2(1792, 1008), Vector2(1000, 1000))
	assert_true(frame.size.y >= 1000.0 and frame.size.x >= 1000.0)
	assert_true(absf(frame.size.x / frame.size.y - 1792.0 / 1008.0) < 0.01)
	assert_true(absf(frame.get_center().x - 500.0) < 0.01)  # centred
	var exact := MenuBackdrop.cover(Vector2(1600, 900), Vector2(800, 450))
	assert_eq(exact, Rect2(0, 0, 800, 450))


func test_shard_is_inside_the_screen_and_scales_with_it() -> void:
	var view := Vector2(1920, 1080)
	var points := MenuBackdrop.shard_points(view)
	assert_eq(points.size(), MenuBackdrop.SHARD.size())
	for p in points:
		assert_true(Rect2(Vector2.ZERO, view).has_point(p) or p.x == view.x or p.y == view.y)
	var small := MenuBackdrop.shard_points(view * 0.5)
	assert_true(absf(small[3].x * 2.0 - points[3].x) < 0.01)


func test_backdrop_builds_with_and_without_stills() -> void:
	var backdrop := MenuBackdrop.new()
	backdrop.size = Vector2(1280, 720)
	backdrop._ready()
	backdrop.refresh_texts()
	assert_true(backdrop.get_child_count() >= 4)
	backdrop.free()


func test_the_stills_are_in_the_project() -> void:
	assert_true(ResourceLoader.exists(MenuBackdrop.MAP_PATH), "run tools/menu_backdrop.sh")
	assert_true(ResourceLoader.exists(MenuBackdrop.BATTLE_PATH), "run tools/menu_backdrop.sh")


func test_chamfer_outline_cuts_the_top_right_and_bottom_left() -> void:
	var points := ChamferBox.outline(Vector2(100, 50), 12.0)
	assert_eq(points.size(), 6)
	assert_eq(points[0], Vector2(0, 0))  # top-left stays square
	assert_eq(points[2], Vector2(100, 12))
	assert_eq(points[4], Vector2(12, 50))


func test_plate_is_a_button_with_chamfered_styles() -> void:
	var plate := MenuStyle.plate("Start")
	assert_eq(plate.text, "START")
	assert_true(plate.get_theme_stylebox(&"hover") is ChamferBox)
	assert_true((plate.get_theme_stylebox(&"hover") as ChamferBox).accent.a > 0.0)
	plate.free()
