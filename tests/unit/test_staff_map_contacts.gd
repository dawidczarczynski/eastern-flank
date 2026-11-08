extends TestCase
## Contact notice of the staff map (TASK-094a): a scripted contact shows the notice with both
## names, the queue and the odds; resolving closes it and End turn works again.

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
	_map.set_follow_side(false)


func after_all() -> void:
	_map.free()
	_map = null
	TranslationServer.set_locale(_previous_locale)


## Puts the Russian formation `attacker` next to the NATO `defender` and lets ContactRules start
## the battle as the end of a turn would; the events reach the map like real ones.
func _contact(attacker: Formation, defender: Formation) -> void:
	var state := _map.simulation().state
	for neighbor in Hex.neighbors(defender.coord):
		if state.formation_at(neighbor) == null:
			attacker.coord = neighbor
			break
	var events: Array[Dictionary] = [
		{
			"type": &"formation_halted",
			"formation_id": attacker.id,
			"at": attacker.coord,
			"reason": &"contact",
		}
	]
	ContactRules.start_battles(state, events)
	for event in events:
		_map.simulation().event_emitted.emit(event)


func _pair(index: int) -> Array[Formation]:
	var state := _map.simulation().state
	var own: Array[Formation] = []
	var enemy: Array[Formation] = []
	for formation in state.formations:
		(own if formation.owner_id == 0 else enemy).append(formation)
	return [enemy[index], own[index]]


func test_contact_shows_notice_and_resolving_closes_it() -> void:
	var state := _map.simulation().state
	var contacts := _map.contacts()
	assert_false(contacts.notice.visible)
	var pair := _pair(0)
	_contact(pair[0], pair[1])
	assert_eq(state.pending_battles.size(), 1)
	var notice := contacts.notice
	assert_true(notice.visible, "notice shows")
	assert_true(contacts.scrim.visible, "map dims")
	assert_eq(notice.name_text(0), tr_upper(pair[0].display_name), "attacker first")
	assert_eq(notice.name_text(1), tr_upper(pair[1].display_name))
	assert_false(notice.counter(0).is_own(), "the Russian attacker is the enemy to NATO")
	assert_true(notice.counter(1).is_own())
	assert_true(notice.title_text().begins_with("ENEMY ATTACK AT HEX"), notice.title_text())
	assert_true(notice.odds_line().begins_with("1 : "), notice.odds_line())
	assert_true(notice.role_text(0).ends_with("ATTACKER"), notice.role_text(0))
	assert_true(notice.row_text("MISSION").begins_with("ATTACK"), notice.row_text("MISSION"))
	assert_false(notice.play_enabled(), "Play battle is off until TASK-094c")
	assert_eq(notice.reason_text(), "Battle scene not hooked up yet")
	assert_false(notice.resolve_visible(), "no debug button without --debug")
	assert_true(contacts.queue.visible)
	assert_eq(contacts.queue.row_count(), 1)
	assert_true(contacts.queue.row_text(0).contains("NOW"), contacts.queue.row_text(0))
	assert_false(_map.end_turn(), "End turn is blocked by the pending battle")
	assert_true(_map.turn_bar().end_button().disabled)
	assert_true(contacts.resolve_as_draw(), "the debug draw resolves it")
	assert_eq(state.pending_battles.size(), 0)
	assert_false(notice.visible)
	assert_false(contacts.scrim.visible)
	assert_false(contacts.queue.visible)
	assert_false(_map.turn_bar().end_button().disabled, "End turn is back")
	assert_true(_map.end_turn())


func test_two_contacts_queue_in_order() -> void:
	var state := _map.simulation().state
	var contacts := _map.contacts()
	var first := _pair(1)
	var second := _pair(2)
	_contact(first[0], first[1])
	_contact(second[0], second[1])
	assert_eq(state.pending_battles.size(), 2)
	assert_eq(contacts.queue.row_count(), 2)
	assert_true(contacts.queue.row_text(1).contains("NEXT"), contacts.queue.row_text(1))
	assert_eq(contacts.notice.name_text(0), tr_upper(first[0].display_name))
	assert_true(contacts.notice.tab_right_text.ends_with("1/2"), contacts.notice.tab_right_text)
	contacts.resolve_as_draw()
	assert_true(contacts.notice.visible, "the second contact follows")
	assert_eq(contacts.notice.name_text(0), tr_upper(second[0].display_name))
	assert_eq(contacts.queue.row_count(), 1)
	contacts.resolve_as_draw()
	assert_false(contacts.notice.visible)


func test_odds_and_mission_text() -> void:
	assert_eq(StaffMapContactNotice.odds_text(10, 14), "1 : 1.4")
	assert_eq(StaffMapContactNotice.odds_text(0, 5), "–")
	var mission := BattleSetup.Mission.new()
	mission.task = &"attack"
	mission.intent_key = ContactRules.INTENT_MOVE
	mission.intent_args = [3, 4]
	assert_true(StaffMapContactNotice.mission_text(mission).begins_with("Attack · Advance to hex "))


func tr_upper(key: String) -> String:
	return TranslationServer.translate(key).to_upper()


## TASK-094b debug preview: while the contact-map panel is open, two clicks pick the attacker and
## an adjacent defender hex, the cut is outlined on the relief and "Open battle map" hands over
## the built setup.
func test_debug_contact_map_outlines_the_cut_and_opens_it() -> void:
	var debug := _map.contact_debug()
	var state := _map.simulation().state
	var opened: Array[BattleSetup] = []
	debug.open_battle = func(setup: BattleSetup) -> void: opened.append(setup)
	debug.toggle(Vector2(16, 130))
	assert_true(debug.is_open())
	var formation := state.formations[0]
	var target := formation.coord
	for n in Hex.neighbors(formation.coord):
		if state.grid.has_tile(n) and state.grid.get_terrain(n) != Terrain.Type.WATER:
			target = n
			break
	_map.click_at(_map.hex_screen_position(formation.coord))
	assert_eq(debug.preview().attacker_hex, formation.coord)
	assert_eq(_map.selected_formation(), &"", "the click picks, it does not select")
	_map.click_at(_map.hex_screen_position(target))
	assert_true(debug.preview().setup != null, debug.preview().problem)
	assert_true(debug.outline_line().point_count() > 5, "the outline follows the relief")
	assert_true(debug.panel().open_enabled())
	debug.panel().press_open()
	assert_eq(opened.size(), 1)
	assert_eq(opened[0].map_region, debug.preview().setup.map_region)
	debug.toggle(Vector2.ZERO)
	assert_false(debug.is_open())
	assert_eq(debug.outline_line().point_count(), 0, "closing removes the outline")
