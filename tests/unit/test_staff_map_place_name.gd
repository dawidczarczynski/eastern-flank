extends TestCase
## Place-based hex names of the staff map: nearest place, distance in km, compass direction.

var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


func _map(places: Array) -> ImportedMap:
	var map := ImportedMap.new()
	map.hex_spacing_m = 1000.0
	for place: Array in places:
		map.place_names.append(place[0])
		map.place_positions.append(place[1])
		map.place_ranks.append(ImportedMap.PLACE_TOWN)
	return map


func test_hex_east_of_the_place() -> void:
	var map := _map([["Suwałki", Vector2.ZERO]])
	assert_eq(StaffMapPlaceName.describe(map, Vector2i(5, 0)), "Suwałki, 5 km east")


func test_hex_south_of_the_place() -> void:
	# Axial (-3, 6) sits straight south: x = 0, z = 9 world units = 5.2 km.
	var map := _map([["Suwałki", Vector2.ZERO]])
	assert_eq(StaffMapPlaceName.describe(map, Vector2i(-3, 6)), "Suwałki, 5 km south")


func test_nearest_place_wins() -> void:
	var map := _map([["Far", Vector2(-50, 0)], ["Near", Vector2(2, 0)]])
	assert_true(StaffMapPlaceName.describe(map, Vector2i(5, 0)).begins_with("Near"))


func test_close_to_a_place_gives_the_bare_name() -> void:
	var map := _map([["Suwałki", Vector2.ZERO]])
	assert_eq(StaffMapPlaceName.describe(map, Vector2i(1, 0)), "Suwałki")


func test_no_places_gives_an_empty_name() -> void:
	assert_eq(StaffMapPlaceName.describe(_map([]), Vector2i(5, 0)), "")
	assert_eq(StaffMapPlaceName.describe(null, Vector2i(5, 0)), "")
