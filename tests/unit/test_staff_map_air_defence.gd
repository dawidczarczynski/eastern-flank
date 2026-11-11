extends TestCase
## The pure models of the air defence view (TASK-098b): the zones, the odds line, the hover card
## lines, the report line and the geometry helpers of the zone layer, on the shipped operation.

const WEAPON := &"jassm_er"

static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


static func _state() -> OperationalState:
	return Operation.build(&"suwalki_gap", 1)


static func _zone(zones: Array[Dictionary], id: StringName) -> Dictionary:
	for zone in zones:
		if zone["id"] == id:
			return zone
	return {}


static func _coord(state: OperationalState, id: StringName) -> Vector2i:
	return state.get_installation(id).coord


# --- zones ---


func test_zones_cover_both_sides() -> void:
	var state := _state()
	var zones := StaffMapAirDefence.zones(state)
	assert_eq(zones.size(), 6, "three sites per side")
	var owners := [0, 0, 0, 1, 1, 1]
	for i in zones.size():
		assert_eq(zones[i]["owner"], owners[i], "side-ordered")
	var long_zone := _zone(zones, &"ru_ad_kaliningrad")
	assert_eq(long_zone["radius_hexes"], 30)
	assert_eq(long_zone["radius_km"], 150, "radius x 5 km")
	assert_eq(long_zone["coord"], _coord(state, &"ru_ad_kaliningrad"))
	assert_false(long_zone["suppressed"])
	assert_eq(long_zone["rounds"], 0)


func test_zone_of_a_suppressed_site() -> void:
	var state := _state()
	state.get_installation(&"ru_ad_grodno").suppressed_rounds = 2
	var zones := StaffMapAirDefence.zones(state)
	var zone := _zone(zones, &"ru_ad_grodno")
	assert_true(zone["suppressed"])
	assert_eq(zone["rounds"], 2)
	assert_eq(zone["owner"], 1)


func test_destroyed_site_has_no_zone() -> void:
	var state := _state()
	state.get_installation(&"nato_ad_suwalki").integrity = 0
	var zones := StaffMapAirDefence.zones(state)
	assert_eq(zones.size(), 5)
	for zone in zones:
		assert_true(zone["id"] != &"nato_ad_suwalki")


func test_zone_count_equals_coverage_of_both_sides() -> void:
	var state := _state()
	var expected := StrikeRules.coverage(state, 0).size() + StrikeRules.coverage(state, 1).size()
	assert_eq(StaffMapAirDefence.zones(state).size(), expected)


# --- odds line ---


func test_odds_with_cover_show_the_core_number() -> void:
	var state := _state()
	var coord := _coord(state, &"ru_c2_kaliningrad")
	var core := StrikeRules.interception_chance(state, 0, WEAPON, coord)
	assert_true(core > 0, "the shipped Kaliningrad site covers its c2")
	var odds := StaffMapAirDefence.odds(state, 0, WEAPON, coord)
	assert_eq(odds["kind"], StaffMapAirDefence.ODDS_SOME)
	assert_eq(odds["percent"], core)
	assert_eq(odds["text"], "Interception ~%d%% per missile" % core)


func test_odds_without_cover() -> void:
	var state := _state()
	var odds := StaffMapAirDefence.odds(state, 0, WEAPON, _coord(state, &"ru_airfield_lida"))
	assert_eq(odds["kind"], StaffMapAirDefence.ODDS_NONE)
	assert_eq(odds["text"], "No air defence cover")


func test_odds_with_every_covering_site_suppressed() -> void:
	var state := _state()
	for installation in state.installations:
		if installation.class_id == &"air_defence" and installation.owner == 1:
			installation.suppressed_rounds = 2
	var coord := _coord(state, &"ru_c2_kaliningrad")
	var odds := StaffMapAirDefence.odds(state, 0, WEAPON, coord)
	assert_eq(odds["kind"], StaffMapAirDefence.ODDS_SUPPRESSED)
	assert_eq(odds["text"], "Air defence suppressed")
	var lida := StaffMapAirDefence.odds(state, 0, WEAPON, _coord(state, &"ru_airfield_lida"))
	assert_eq(lida["kind"], StaffMapAirDefence.ODDS_NONE, "a suppressed site far away is no cover")


func test_odds_for_a_target_id() -> void:
	var state := _state()
	var odds := StaffMapAirDefence.odds_for_target(state, 0, WEAPON, &"ru_c2_kaliningrad")
	assert_eq(odds["kind"], StaffMapAirDefence.ODDS_SOME)
	assert_true(StaffMapAirDefence.odds_for_target(state, 0, WEAPON, &"nope").is_empty())


func test_odds_for_the_other_side() -> void:
	var state := _state()
	var coord := _coord(state, &"nato_c2_bialystok")
	var core := StrikeRules.interception_chance(state, 1, WEAPON, coord)
	var odds := StaffMapAirDefence.odds(state, 1, WEAPON, coord)
	assert_eq(odds["percent"], core)


# --- hover card ---


func test_card_of_an_active_site() -> void:
	var state := _state()
	var card := StaffMapAirDefence.card_model(state, state.get_installation(&"nato_ad_olsztyn"))
	assert_true(card["is_air_defence"])
	assert_eq(card["type_line"], "Medium-range air defence – NASAMS / Narew, Buk-M3, Tor")
	assert_eq(card["reach_line"], "radius 10 hexes (50 km)")
	assert_false(card["suppressed"])
	assert_eq(card["suppressed_line"], "", "no line for an active site")


func test_card_of_a_suppressed_site() -> void:
	var state := _state()
	var site := state.get_installation(&"nato_ad_olsztyn")
	site.suppressed_rounds = 2
	var card := StaffMapAirDefence.card_model(state, site)
	assert_true(card["suppressed"])
	assert_eq(card["rounds"], 2)
	assert_eq(card["suppressed_line"], "▲ SUPPRESSED – 2 rounds left")
	site.suppressed_rounds = 1
	assert_eq(
		StaffMapAirDefence.card_model(state, site)["suppressed_line"], "▲ SUPPRESSED – 1 round left"
	)


func test_card_of_other_classes_has_no_air_defence_lines() -> void:
	var state := _state()
	for id: StringName in [&"ru_airfield_lida", &"nato_depot_elk", &"ru_c2_kaliningrad"]:
		var card := StaffMapAirDefence.card_model(state, state.get_installation(id))
		assert_false(card["is_air_defence"], String(id))
		assert_eq(card["type_line"], "")
		assert_eq(card["reach_line"], "")
		assert_eq(card["suppressed_line"], "")


# --- report line ---


func test_report_line() -> void:
	assert_eq(StaffMapAirDefence.report_line(2), "Suppressed for 2 rounds")
	assert_eq(StaffMapAirDefence.report_line(1), "Suppressed for 1 round")


# --- geometry ---


func test_ring_is_a_true_circle() -> void:
	var centre := Vector2(3, -2)
	var radius := StaffMapAirDefence.radius_units(10)
	assert_true(absf(radius - 10.0 * Hex.SQRT3) < 0.0001, "10 hexes x sqrt(3) hex units")
	var points := StaffMapAirDefence.ring(centre, radius)
	assert_eq(points.size(), StaffMapAirDefence.RING_SEGMENTS)
	for p in points:
		assert_true(absf(p.distance_to(centre) - radius) < 0.001)


func test_dashes_alternate_on_and_off() -> void:
	var square := PackedVector2Array(
		[Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	)
	var dashes := StaffMapAirDefence.dashes(square, 6.0, 5.0)
	assert_true(dashes.size() > 30, "a 400 px ring has about 36 dashes")
	for dash in dashes:
		assert_true(dash.size() >= 2)
		var length := 0.0
		for i in range(1, dash.size()):
			length += dash[i - 1].distance_to(dash[i])
		assert_true(length <= 6.001, "no dash longer than 6 px")
	assert_true(StaffMapAirDefence.dashes(PackedVector2Array(), 6.0, 5.0).is_empty())


func test_hatch_stays_inside_a_convex_polygon() -> void:
	var circle := StaffMapAirDefence.ring(Vector2(200, 200), 100.0)
	var lines := StaffMapAirDefence.hatch(circle, 5.0)
	assert_true(lines.size() > 40 and lines.size() % 2 == 0, "pairs of points")
	for p in lines:
		assert_true(absf(p.distance_to(Vector2(200, 200)) - 100.0) < 0.5, "ends on the ring")
	for i in range(0, lines.size(), 2):
		var d := lines[i + 1] - lines[i]
		assert_true(absf(absf(d.x) - absf(d.y)) < 0.01, "45 degrees")
