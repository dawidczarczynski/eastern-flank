extends TestCase
## Allied contributions on the staff map (TASK-118): counters, tag, notice and panel.

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


func test_neutral_country_adds_nothing_then_belligerent_adds_three() -> void:
	var state := _map.simulation().state
	var before := _map.counters().counter_count()
	assert_eq(before, state.formations.size())
	assert_false(_map.join_notice().visible)
	var side := 0
	for event in CountryRules.set_stance(state, &"lithuania", &"neutral", side, &"test", -1):
		_map.simulation().event_emitted.emit(event)
	assert_eq(_map.counters().counter_count(), before, "no counters while neutral")
	for event in CountryRules.set_stance(state, &"lithuania", &"belligerent", side, &"test", -1):
		_map.simulation().event_emitted.emit(event)
	assert_eq(_map.counters().counter_count(), before + 3, "three Lithuanian counters")
	assert_eq(_map.counters().counter_count(), state.formations.size())
	var joined := _map.counters().formation_ids().slice(before)
	var counter := _map.counters().counter(joined[0])
	assert_eq(counter.country_tag, "LT")
	assert_true(counter.pulse_left > 0.0, "pulses")
	assert_eq(_map.origin_country(joined[0]), &"lithuania")
	var notice := _map.join_notice()
	assert_true(notice.visible)
	assert_eq(notice.message(), "Lithuania joins NATO – 3 formations")
	assert_eq(notice.formation_ids().size(), 3)
	_map.select_formation(joined[0])
	assert_eq(_map.formation_panel().value_text("Country"), "LITHUANIA")
	notice.press_show()
	assert_true(_map.zoom() > _map.zoom_limits().x, "Show zooms in (min zoom pins the camera)")
