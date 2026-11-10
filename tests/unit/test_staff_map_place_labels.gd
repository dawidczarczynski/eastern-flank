extends TestCase
## Place-name labels of the staff map (TASK-112): the filter and the layer's recompute rule.

const Fixtures := preload("res://tests/fixtures.gd")
const VIEW := Rect2(0, 0, 1000, 600)
const SIZE := Vector2(60, 14)


func _show(ranks: Array, points: Array, level: int, sizes: Array = []) -> PackedInt32Array:
	var sz := PackedVector2Array()
	for i in ranks.size():
		sz.append(sizes[i] if i < sizes.size() else SIZE)
	return StaffMapPlaceFilter.visible_places(
		PackedInt32Array(ranks), PackedVector2Array(points), sz, level, VIEW
	)


func test_zoom_level_opens_ranks() -> void:
	var points := [Vector2(100, 100), Vector2(300, 100), Vector2(500, 100)]
	assert_eq(_show([0, 2, 2], points, 0), PackedInt32Array([0]))
	assert_eq(_show([0, 1, 2], points, 1), PackedInt32Array([0, 1]))
	assert_eq(_show([0, 1, 2], points, 2), PackedInt32Array([0, 1, 2]))


func test_off_screen_anchor_is_dropped() -> void:
	var shown := _show([0, 0, 0], [Vector2(-5, 50), Vector2(500, 300), Vector2(500, 700)], 2)
	assert_eq(shown, PackedInt32Array([1]))


func test_overlap_higher_rank_wins_even_when_later_in_the_list() -> void:
	var shown := _show([2, 0], [Vector2(500, 300), Vector2(510, 305)], 2)
	assert_eq(shown, PackedInt32Array([1]))


func test_overlap_equal_rank_keeps_the_earlier_entry() -> void:
	var shown := _show([2, 2], [Vector2(500, 300), Vector2(520, 300)], 2)
	assert_eq(shown, PackedInt32Array([0]))


func test_non_overlapping_labels_all_stay() -> void:
	var shown := _show([1, 1], [Vector2(500, 300), Vector2(500, 330)], 2)
	assert_eq(shown, PackedInt32Array([0, 1]))


func test_same_input_same_output() -> void:
	var ranks := [2, 1, 0, 2, 1, 0, 2]
	var points := []
	for i in ranks.size():
		points.append(Vector2(100 + i * 25, 200 + (i % 2) * 5))
	assert_eq(_show(ranks, points, 2), _show(ranks, points, 2))


func test_font_covers_polish_lithuanian_and_cyrillic() -> void:
	var font := StaffMapPlaceLayer.label_font()
	for ch in "ąćęłńóśźżėšžųūįčĄŁЖыўіёЩюя":
		assert_true(font.has_char(ch.unicode_at(0)), "missing glyph " + ch)


func test_layer_recomputes_only_when_the_camera_changes() -> void:
	var map := ImportedMap.new()
	map.width = 4
	map.height = 4
	map.place_names = PackedStringArray(["Alpha", "Beta"])
	map.place_positions = PackedVector2Array([Vector2(1, 1), Vector2(5, 5)])
	map.place_ranks = PackedInt32Array([0, 1])
	var relief := StaffMapRelief.new(Fixtures.plains_grid(3), 2886.75, 3.0)
	var layer := StaffMapPlaceLayer.new()
	layer.build(map, relief)
	var project := func(p: Vector3) -> Vector2: return Vector2(p.x * 50.0, p.z * 50.0)
	layer.layout(project, Vector2(1000, 600), 1, [1])
	assert_eq(layer.rebuild_count, 1)
	assert_eq(layer.shown().size(), 2)
	layer.layout(project, Vector2(1000, 600), 1, [1])
	assert_eq(layer.rebuild_count, 1)
	layer.layout(project, Vector2(1000, 600), 0, [1])
	assert_eq(layer.rebuild_count, 2)
	assert_eq(layer.shown().size(), 2)
	layer.layout(project, Vector2(1000, 600), 0, [2])
	assert_eq(layer.rebuild_count, 3)
	layer.set_enabled(false)
	layer.layout(project, Vector2(1000, 600), 0, [2])
	assert_eq(layer.rebuild_count, 3)
	layer.set_enabled(true)
	layer.layout(project, Vector2(1000, 600), 0, [2])
	assert_eq(layer.rebuild_count, 4)
	layer.free()


func test_widest_zoom_also_shows_the_largest_towns() -> void:
	var points := [Vector2(100, 100), Vector2(300, 100)]
	assert_eq(_show([0, 1], points, 0), PackedInt32Array([0, 1]))


func test_label_touching_an_obstacle_is_dropped() -> void:
	var obstacles: Array[Rect2] = [Rect2(480, 290, 40, 26)]
	var shown := StaffMapPlaceFilter.visible_places(
		PackedInt32Array([2, 2]),
		PackedVector2Array([Vector2(500, 300), Vector2(200, 300)]),
		PackedVector2Array([SIZE, SIZE]),
		2,
		VIEW,
		obstacles
	)
	assert_eq(shown, PackedInt32Array([1]))


func test_cyrillic_name_gets_a_latin_transcription() -> void:
	assert_eq(PlaceTransliteration.latin("Гродна"), "Grodno")
	assert_eq(PlaceTransliteration.latin("Калининград"), "Kaliningrad")
	assert_eq(PlaceTransliteration.latin("Suwałki"), "")


func test_city_under_a_counter_slides_aside_but_a_village_is_dropped() -> void:
	var obstacles: Array[Rect2] = [Rect2(470, 280, 60, 40)]
	var shifts := {}
	var shown := StaffMapPlaceFilter.visible_places(
		PackedInt32Array([0, 2]),
		PackedVector2Array([Vector2(500, 300), Vector2(500, 300)]),
		PackedVector2Array([SIZE, SIZE]),
		2,
		VIEW,
		obstacles,
		shifts
	)
	assert_eq(shown, PackedInt32Array([0]))
	assert_true(shifts[0] != Vector2.ZERO)
