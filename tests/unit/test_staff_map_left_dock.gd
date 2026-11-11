extends TestCase
## The left edge of the staff map holds one window at a time: opening the country card, the
## debug panels or a strike report closes the others.

const Fixtures := preload("res://tests/fixtures.gd")

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
	Fixtures.add_generic_strike_means(_map.simulation().state)  # code-built `cruise`
	_map.simulation().state.air_defence_types.clear()  # no interception


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func _strike_once() -> StaffMapStrikeReports:
	var state := _map.simulation().state
	state.current_player = 0
	state.escalation_level = 2
	state.decisions_left = 1
	state.strikes_left = 2
	state.pending_battles.clear()
	state.strike_stock[0][&"cruise"] = 8
	var hud := _map.strike_hud()
	hud.reports().clear()
	hud.close()
	assert_true(hud.toggle(), "strike mode opens")
	hud.pick_means(&"cruise")
	for target in StrikeRules.targets(state, 0):
		if target["class_id"] == &"airfield":
			hud.click(target["id"])
			break
	hud.confirm()
	hud.reports().tick(0.5)
	return hud.reports()


func test_country_card_and_strike_report_share_the_place() -> void:
	var reports := _strike_once()
	assert_true(reports.card_visible(), "a report shows")
	_map.open_country_card(_map.simulation().state.countries[0].id)
	assert_true(_map.country_card().visible, "the country card opens")
	assert_false(reports.card_visible(), "and takes the report's place")
	assert_false(reports.chip_visible())
	reports.toggle()
	assert_true(reports.card_visible(), "J brings the report back")
	assert_false(_map.country_card().visible, "and closes the country card")
