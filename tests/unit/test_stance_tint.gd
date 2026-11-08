extends TestCase
## Political tint and country card of the staff map (TASK-114): the viewer decides own / hostile,
## closed countries are flagged, the card tells what the country allows and why not.

static var _state: OperationalState


func before_all() -> void:
	var definition := OperationDefinition.find(&"suwalki_gap")
	var map := ImportedMap.find(definition.map_id)
	_state = Operation.from_definition(definition, 1, map.to_grid(), Operation.map_countries(map))


func after_all() -> void:
	_state = null


func _relation(player: int, country: StringName) -> StringName:
	return StanceTint.for_viewer(_state, player)[country]["relation"]


func test_viewer_swaps_own_and_enemy() -> void:
	assert_eq(_relation(0, &"poland"), &"own")
	assert_eq(_relation(1, &"poland"), &"enemy")
	assert_eq(_relation(0, &"russia"), &"enemy")
	assert_eq(_relation(1, &"russia"), &"own")


func test_aligned_country_is_own_or_hostile_by_viewer() -> void:
	assert_eq(_relation(0, &"lithuania"), &"own")
	assert_eq(_relation(1, &"lithuania"), &"hostile")
	assert_eq(_relation(0, &"belarus"), &"hostile")
	assert_eq(_relation(1, &"belarus"), &"own")


func test_closed_follows_may_enter() -> void:
	var nato := StanceTint.for_viewer(_state, 0)
	assert_false(nato[&"poland"]["closed"])
	assert_true(nato[&"russia"]["closed"])  # sanctuary
	assert_true(nato[&"belarus"]["closed"])  # hostile
	assert_false(StanceTint.for_viewer(_state, 1)[&"belarus"]["closed"])


func test_colours_come_from_the_palette() -> void:
	var palette := StaffMapPalette.new()
	var own := StanceTint.colour(palette, {"relation": &"own", "stance": &"belligerent"})
	assert_eq(Color(own, 1.0), palette.side_own)
	assert_near(own.a, StanceTint.ALPHA_OWN)
	var hostile := StanceTint.colour(palette, {"relation": &"hostile", "stance": &"aligned"})
	assert_eq(Color(hostile, 1.0), palette.side_enemy)
	var enemy := StanceTint.colour(palette, {"relation": &"enemy", "stance": &"belligerent"})
	assert_true(hostile.a < enemy.a)
	assert_eq(StanceTint.colour(palette, {"relation": &"none", "stance": &"neutral"}).a, 0.0)


func test_card_says_why_russia_is_closed_to_nato() -> void:
	var info := StaffMapCountryCard.info(_state, 0, &"russia")
	assert_false(info["may_enter"])
	assert_eq(info["enter_reason"], "Closed: sanctuary until open war")
	assert_true(info["sanctuary"])
	assert_eq(info["stance"], "At war against you")


func test_card_for_an_ally_allows_entering_not_striking_own_soil() -> void:
	var info := StaffMapCountryCard.info(_state, 0, &"lithuania")
	assert_true(info["may_enter"])
	assert_eq(info["stance"], "Aligned with you")
	assert_false(info["may_strike"])
	assert_eq(info["strike_reason"], "Your own soil")
	assert_eq(info["leaning"], "Leans to you")


func test_card_for_a_hostile_country_names_the_reason() -> void:
	var info := StaffMapCountryCard.info(_state, 0, &"belarus")
	assert_eq(info["enter_reason"], "Closed: hostile to you")
	assert_eq(StaffMapCountryCard.info(_state, 0, &"nowhere"), {})


func assert_near(actual: float, expected: float) -> void:
	assert_true(absf(actual - expected) < 0.0001, "%f != %f" % [actual, expected])


func test_mask_marks_each_country_in_its_own_channel() -> void:
	var map := ImportedMap.find(&"suwalki_theatre")
	var rect := map.layer_world_rect(ImportedMap.LAYER_WATER)
	var mask := StaffMapCountryMask.build(map, rect, null)
	assert_true(mask != null)
	var seen := {}
	for iso in map.countries:
		seen[iso] = false
	for j in range(0, mask.image.get_height(), 7):
		for i in range(0, mask.image.get_width(), 7):
			var pixel := mask.image.get_pixel(i, j)
			for k in map.countries.size():
				if pixel[k] > 0.5:
					seen[map.countries[k]] = true
	for iso in map.countries:
		assert_true(seen[iso], "country %s has no pixel in the mask" % iso)
