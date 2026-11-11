extends TestCase
## Installation markers, strike toasts and the F9 Strikes block on the staff map (TASK-097a).

const TARGET := &"ru_airfield_chernyakhovsk"  # owner 1

static var _map: StaffMap
static var _hud: StaffMapPoliticsHud
static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_map = StaffMap.new()
	_map.auto_build = false
	_map.viewer_player = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(_map)
	assert_true(_map.build_now(), "staff map builds")
	# The F9 panel exists only with --debug: make the same hud with it on.
	var layer := CanvasLayer.new()
	_map.add_child(layer)
	var palette := load(StaffMapPalette.PATH) as StaffMapPalette
	_hud = StaffMapPoliticsHud.new(
		_map.view(), null, palette, _map.simulation(), layer, _map._toast_message, true
	)


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


func _id(coord_owner_class: String) -> StringName:
	for installation in _map.simulation().state.installations:
		if String(installation.id).contains(coord_owner_class):
			return installation.id
	return &""


func test_one_marker_per_installation() -> void:
	var state := _map.simulation().state
	assert_true(state.installations.size() > 0)
	assert_eq(_map.installations().marker_count(), state.installations.size())
	var marker := _map.installations().marker(TARGET)
	assert_true(marker != null, "marker for " + str(TARGET))
	assert_eq(marker.owner_id, 1)
	assert_eq(marker.bar_fraction(), 1.0)
	assert_false(marker.destroyed)


func test_card_info() -> void:
	var state := _map.simulation().state
	var data := StaffMapInstallations.info(state, state.get_installation(TARGET))
	assert_eq(data["class"], "Airfield")
	assert_eq(data["integrity"], 100)
	assert_true((data["gives"] as String).contains("battles"), data["gives"])
	var card := StaffMapInstallationCard.new()
	card.show_info(data)
	assert_eq(card.value_text(1), "100 %")
	assert_true(card.visible)
	card.free()


func test_destroyed_marker_is_grey_and_crossed() -> void:
	var state := _map.simulation().state
	var installation := state.get_installation(&"ru_ad_grodno")
	installation.integrity = 0
	_map.installations().refresh()
	var marker := _map.installations().marker(&"ru_ad_grodno")
	assert_true(marker.destroyed)
	assert_eq(marker.fill_colour(), StaffMapInstallationMarker.DESTROYED_FILL)
	installation.integrity = 100
	_map.installations().refresh()
	assert_false(marker.destroyed)


func _enemy_airfield(player: int) -> StringName:
	for target in StrikeRules.targets(_map.simulation().state, player):
		if target["class_id"] == &"airfield":
			return target["id"]
	return &""


func test_debug_strike_lowers_bar_and_stock_line() -> void:
	var sim := _map.simulation()
	var state := sim.state
	var player := state.current_player
	var target := _enemy_airfield(player)
	state.air_defence_intercept_pct = 0
	for id: StringName in state.strike_means.keys():  # copies: the shipped data stays as is
		var means: StrikeMeansDefinition = state.strike_means[id].duplicate()
		means.accuracy_pct = 100
		state.strike_means[id] = means
	for event in EscalationRules.raise(state, player, &"decision", 2):
		sim.event_emitted.emit(event)
	_hud.toggle_panel()
	var panel := _hud.panel()
	assert_true(panel.visible)
	var before_stock := StrikeRules.stock(state, player, &"cruise")
	panel.press_stock(player, &"cruise", 1)
	assert_eq(StrikeRules.stock(state, player, &"cruise"), before_stock + 1)
	panel.press_strike(player, &"cruise", 2, target)
	_map.strike_hud().tick(0.5)  # the result report card (it replaced the toast)
	var message := _map.strike_hud().reports().card().tooltip_text
	assert_eq(StrikeRules.stock(state, player, &"cruise"), before_stock - 1, message)
	var installation := state.get_installation(target)
	assert_true(
		installation.integrity < 100, "integrity %d / %s" % [installation.integrity, message]
	)
	assert_eq(_map.installations().marker(target).bar_fraction(), installation.integrity / 100.0)
	assert_true(message.contains("hit"), message)
	_hud.refresh(0)  # the map refreshes its own hud; this one is a test twin
	var line := panel.find_children("StockLine", "Label", true, false).back() as Label
	assert_true(line.text.contains("cruise %d" % (before_stock - 1)), line.text)


func test_rejection_shows_the_code() -> void:
	var player := _map.simulation().state.current_player
	_hud.panel().press_strike(player, &"cruise", 99, _enemy_airfield(player))
	assert_eq(_map.toast().message(), "bad_count")
	_hud.panel().press_strike(1 - player, &"cruise", 1, _enemy_airfield(1 - player))
	assert_eq(_map.toast().message(), "wrong_player")


## Keep this test last: it removes a formation from the shared map's state.
func test_destroyed_formation_loses_its_counter() -> void:
	var sim := _map.simulation()
	var formation: Formation = sim.state.formations.back()
	var before := _map.counters().counter_count()
	sim.state.formations.erase(formation)
	sim.event_emitted.emit(
		{"type": &"formation_destroyed", "formation_id": formation.id, "player": formation.owner_id}
	)
	assert_eq(_map.counters().counter_count(), before - 1)
	assert_true(_map.counters().counter(formation.id) == null)


func test_a_marker_reached_outside_a_counter_comes_to_the_front() -> void:
	var counters := _map.counters()
	var marker := _map.installations().marker(TARGET)
	var counter := counters.counter(counters.shown_ids()[0])
	marker.position = Vector2(300, 300)
	counter.position = marker.position + Vector2(12, 0)  # covers the marker's right part
	var left_part := marker.position + Vector2(-20, 0)
	var shared := marker.position + Vector2(6, 0)
	assert_eq(_map._pick_counter(shared), counter.formation_id, "the counter is on top at first")
	assert_eq(_map._pick_counter(left_part), &"", "no counter on the free left part")
	assert_eq(_map._raised_marker, TARGET, "pointing at the marker raises it alone")
	assert_eq(marker.z_index, 1)
	assert_eq(_map._pick_counter(shared), &"", "the marker now wins where they overlap")
	_map._raise_marker(&"")
	assert_eq(marker.z_index, 0)
