extends TestCase
## Country layer of the staff map (TASK-113): dash pattern, name anchors, card line, B toggle.

const Fixtures := preload("res://tests/fixtures.gd")
const CSV_PATH := "res://assets/i18n/strings.csv"


func assert_near(actual: float, expected: float) -> void:
	assert_true(absf(actual - expected) < 0.0001, "%f != %f" % [actual, expected])


func _total(pieces: Array[PackedVector2Array]) -> float:
	var sum := 0.0
	for piece in pieces:
		for i in piece.size() - 1:
			sum += piece[i].distance_to(piece[i + 1])
	return sum


func test_dashes_follow_the_pattern_along_a_straight_line() -> void:
	var pieces := StaffMapCountries.dashes(PackedVector2Array([Vector2.ZERO, Vector2(2, 0)]))
	# 0.5 + 0.22 + 0.05 + 0.22 = 0.99 per period: two periods = 1.98, then a 0.02 dash start.
	assert_eq(pieces.size(), 5)
	assert_eq(pieces[0][0], Vector2.ZERO)
	assert_near(pieces[0][1].x, 0.5)
	assert_near(pieces[1][0].x, 0.72)
	assert_near(pieces[1][1].x, 0.77)
	assert_near(pieces[2][0].x, 0.99)


func test_dashes_continue_through_a_corner() -> void:
	var line := PackedVector2Array([Vector2.ZERO, Vector2(0.3, 0), Vector2(0.3, 1)])
	var pieces := StaffMapCountries.dashes(line)
	assert_eq(pieces[0].size(), 3)  # the first dash bends at the corner
	assert_eq(pieces[0][1], Vector2(0.3, 0))
	assert_near(pieces[0][2].y, 0.2)


func test_dashes_of_a_short_or_empty_line() -> void:
	assert_eq(StaffMapCountries.dashes(PackedVector2Array()).size(), 0)
	assert_eq(StaffMapCountries.dashes(PackedVector2Array([Vector2.ONE])).size(), 0)
	var pieces := StaffMapCountries.dashes(PackedVector2Array([Vector2.ZERO, Vector2(0.2, 0)]))
	assert_near(_total(pieces), 0.2)


func test_name_anchor_lies_on_a_hex_of_the_country() -> void:
	var map := ImportedMap.new()
	map.width = 3
	map.height = 2
	map.terrain_rows = PackedStringArray(["PPP", "PPP"])
	map.countries = PackedStringArray(["PL", "LT"])
	map.country_rows = PackedStringArray(["001", "001"])
	var anchors := StaffMapCountries.name_anchors(map, 1.0)
	assert_eq(anchors.keys().size(), 2)
	var lt := Hex.to_world(MapGenerator.offset_to_axial(2, 0), 1.0)
	var lt_two := Hex.to_world(MapGenerator.offset_to_axial(2, 1), 1.0)
	var at: Vector2 = anchors["LT"]
	assert_true(
		at.is_equal_approx(Vector2(lt.x, lt.z)) or at.is_equal_approx(Vector2(lt_two.x, lt_two.z))
	)
	assert_true(StaffMapCountries.NAMES.has("PL"))


func test_card_info_carries_the_country() -> void:
	var grid := Fixtures.plains_grid(1)
	assert_eq(StaffMapCard.info(grid, Vector2i.ZERO, "LT")["country"], "LT")
	assert_eq(StaffMapCard.info(grid, Vector2i.ZERO)["country"], "")


func test_country_names_are_translated() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	var polish := {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 3:
			polish[row[0]] = row[2]
	assert_eq(polish.get("Poland"), "Polska")
	assert_eq(polish.get("Lithuania"), "Litwa")
	assert_eq(polish.get("Belarus"), "Białoruś")
	assert_eq(polish.get("Russia"), "Rosja")
	assert_true(polish.has("Country"))
