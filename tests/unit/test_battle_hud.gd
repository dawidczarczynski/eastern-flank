extends TestCase
## Scene test for the HUD v3 turn bar and end-turn module (TASK-077): the HUD is built headless
## (no scene tree) and refreshed with a two-faction state.

const Fixtures := preload("res://tests/fixtures.gd")

var _hud: BattleHud
var _state: GameState


func before_each() -> void:
	_state = GameState.new(Fixtures.plains_grid(3), 2, 1)
	_state.add_unit(0, Fixtures.infantry(), Vector2i(-3, 0))
	_state.add_unit(0, Fixtures.infantry(), Vector2i(-3, 1))
	_state.add_unit(0, Fixtures.infantry(), Vector2i(-3, 2))
	_state.add_unit(1, Fixtures.infantry(), Vector2i(3, 0))
	_state.add_unit(1, Fixtures.infantry(), Vector2i(3, -1))
	_hud = BattleHud.new()
	_hud.setup(0)


func after_each() -> void:
	_hud.free()


func _find(name: String) -> Node:
	return _hud.find_child(name, true, false)


func _text(path_name: String, side: String) -> String:
	return ((_find(side) as Node).find_child(path_name, true, false) as Label).text


func _visible_flags(side: String) -> int:
	var count := 0
	for flag in (_find(side) as Node).find_child("Flags", true, false).get_children():
		if (flag as SideFlag).visible:
			count += 1
	return count


func test_both_blocks_show_names_and_counts() -> void:
	_hud.refresh(_state)
	assert_eq(_text("Name", "Side0"), _t("Poland").to_upper())
	assert_eq(_text("Name", "Side1"), _t("Russia").to_upper())
	assert_eq(_text("Meta", "Side0"), ("%s · %s" % [_t("ACTIVE"), _t("%d UNITS") % 3]).to_upper())
	assert_eq(_text("Meta", "Side1"), ("%s · %s" % [_t("WAITING"), _t("%d UNITS") % 2]).to_upper())
	assert_eq(_visible_flags("Side0"), 2, "Poland: NATO + Poland")
	assert_eq(_visible_flags("Side1"), 1, "Russia: one flag")
	assert_eq((_find("TurnNumber") as Label).text, "01")
	assert_eq((_find("ActiveSide") as Label).text, _t("Poland").to_upper())


func test_hatch_only_on_the_active_side_and_inactive_is_dimmed() -> void:
	_hud.refresh(_state)
	assert_true((_find("Side0").find_child("ActiveBar", true, false) as Control).visible)
	assert_false((_find("Side1").find_child("ActiveBar", true, false) as Control).visible)
	assert_eq((_find("Side0") as Control).modulate.a, BattleHud.ACTIVE_ALPHA)
	assert_true(is_equal_approx((_find("Side1") as Control).modulate.a, BattleHud.INACTIVE_ALPHA))
	_state.current_player = 1
	_hud.refresh(_state)
	assert_false((_find("Side0").find_child("ActiveBar", true, false) as Control).visible)
	assert_true((_find("Side1").find_child("ActiveBar", true, false) as Control).visible)


func test_ready_blocks_and_button_follow_the_active_faction() -> void:
	_state.units_of(0)[0].moves_left = 0
	_state.units_of(0)[0].has_attacked = true
	_hud.refresh(_state)
	var blocks := _find("ReadyBlocks") as ReadyBlocks
	assert_eq(blocks.total, 3)
	assert_eq(blocks.ready_count, 2)
	assert_eq((_find("ReadyValue") as Label).text, "2 / 3")
	var poland := UiPalette.faction_color(_state, 0)
	assert_eq(blocks.color, poland)
	assert_eq((_find("EndTurnButton") as EndTurnButton).fill, poland)
	_state.current_player = 1
	_hud.refresh(_state)
	assert_eq((_find("ReadyBlocks") as ReadyBlocks).total, 2)
	assert_eq((_find("EndTurnButton") as EndTurnButton).fill, UiPalette.faction_color(_state, 1))


func test_disabling_the_end_button_dims_it() -> void:
	_hud.refresh(_state)
	var button := _find("EndTurnButton") as EndTurnButton
	_hud.set_end_enabled(false)
	assert_true(button.disabled)
	assert_eq(button.modulate.a, 0.5)
	_hud.set_end_enabled(true)
	assert_false(button.disabled)
	assert_eq(button.modulate.a, 1.0)
	assert_eq(button.focus_mode, Control.FOCUS_NONE)


func test_only_the_end_button_takes_the_mouse() -> void:
	_hud.refresh(_state)
	var offenders: Array[String] = []
	_collect_mouse_takers(_hud, offenders)
	for name in [
		"ActionBar", "grid", "reset_view", "deselect", "save", "fire_support", "objectives"
	]:
		assert_true(offenders.has(name), name)
	offenders.erase("ActionBar")
	for name in ["grid", "reset_view", "deselect", "save", "fire_support", "objectives"]:
		offenders.erase(name)
	assert_eq(offenders, ["EndTurnButton"])


func test_no_key_hint_panel() -> void:
	var hud := BattleHud.new()
	hud.setup(0)
	assert_true(hud.find_child("KeyHints", true, false) == null)
	assert_true(hud.find_child("ReadyCounter", true, false) != null)
	hud.free()


func test_action_bar_buttons_are_labelled_and_translated() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("pl")
	var hud := BattleHud.new()
	hud.setup(0)
	var bar := hud.action_bar()
	assert_eq(bar.ids().size(), 6)
	assert_eq(bar.button(BattleHud.ACTION_GRID).key_text(), "G")
	assert_false(bar.button(BattleHud.ACTION_SAVE).label_text().contains("SAVE"))
	var pressed: Array[StringName] = []
	hud.action_pressed.connect(func(id: StringName) -> void: pressed.append(id))
	bar.button(BattleHud.ACTION_DESELECT).pressed.emit()
	assert_eq(pressed, [BattleHud.ACTION_DESELECT])
	hud.free()
	TranslationServer.set_locale(previous)


func _collect_mouse_takers(node: Node, out: Array[String]) -> void:
	var control := node as Control
	if control != null and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		out.append(String(control.name))
	for child in node.get_children():
		_collect_mouse_takers(child, out)


func _t(key: String) -> String:
	return String(TranslationServer.translate(key))


func test_turn_limit_stays_a_small_suffix_on_the_result_screen() -> void:
	var no_conditions: Array[VictoryCondition] = []
	_state.set_objectives(Fixtures.objectives(8, [], [], no_conditions))
	_state.turn = 8
	_state.finish(-1, &"turn_limit")
	_hud.refresh(_state)
	assert_eq((_find("TurnNumber") as Label).text, "08")
	assert_eq((_find("TurnLimit") as Label).text, "/08")
	var banner := _find("TurnBanner") as TurnBanner
	assert_eq(banner.caption_text(), ("%s 08 / 08" % _t("TURN")).to_upper())
	assert_eq(banner.subtitle_text(), _t("TURN LIMIT REACHED").to_upper())


func test_no_turn_limit_hides_the_suffix() -> void:
	_hud.refresh(_state)
	assert_eq((_find("TurnLimit") as Label).text, "")
	assert_false((_find("TurnLimit") as Control).get_parent().visible)


func test_command_points_counter_only_when_limited() -> void:
	_hud.refresh(_state)
	assert_false((_find("CommandPoints") as Label).visible)
	_state.set_command_points_per_turn([3, 3] as Array[int])
	_hud.refresh(_state)
	assert_true((_find("CommandPoints") as Label).visible)
	assert_eq((_find("CommandPoints") as Label).text, "C2 3/3")
	_state.activate(_state.units_of(0)[0])
	_hud.refresh(_state)
	assert_eq((_find("CommandPoints") as Label).text, "C2 2/3")


func test_units_without_points_left_count_as_done() -> void:
	_state.set_command_points_per_turn([1, 0] as Array[int])
	var first := _state.units_of(0)[0]
	var second := _state.units_of(0)[1]
	_state.activate(first)
	assert_false(UnitStatus.is_done(_state, first))
	assert_true(UnitStatus.is_done(_state, second))
	assert_false(UnitStatus.is_done(_state, _state.units_of(1)[0]))


func test_action_icons_exist_for_every_button_and_fit_the_grid() -> void:
	for id in ActionIcons.IDS:
		var lines := ActionIcons.polylines(id)
		assert_true(not lines.is_empty() or ActionIcons.text(id, false) != "", String(id))
		for line in lines:
			for p in line:
				assert_true(
					(
						p.x >= 0.0
						and p.y >= 0.0
						and p.x <= ActionIcons.GRID
						and p.y <= ActionIcons.GRID
					),
					"%s point %s" % [id, p]
				)
	assert_true(ActionIcons.polylines(&"nope").is_empty())


func test_action_button_has_tooltip_parts() -> void:
	var hud := BattleHud.new()
	hud.setup(0)
	var b := hud.action_bar().button(BattleHud.ACTION_GRID)
	assert_eq(b.key_text(), "G")
	assert_true(b.tip_text() != "" and b.tip_text() != "TIP_GRID_BATTLE")
	assert_eq(b.tooltip_text, b.label_text())
	var tip := b._make_custom_tooltip("") as Control
	assert_true(tip != null)
	tip.free()
	hud.free()


func test_fire_support_button_shows_the_counter_and_the_reason() -> void:
	var button := _hud.action_bar().button(BattleHud.ACTION_FIRE_SUPPORT)
	assert_false(button.visible, "hidden without missions at the start")
	_state.fire_support_left[0] = 2
	_hud.set_fire_support_start(2)
	_hud.refresh(_state)
	assert_true(button.visible)
	assert_eq(button.badge, "2")
	assert_false(button.disabled)
	_state.fire_support_left[0] = 1
	_state.fire_support_used_turn[0] = true
	_hud.refresh(_state)
	assert_eq(button.badge, "1")
	assert_true(button.disabled, "used this turn")
	assert_true(button.tip_text().contains("ALREADY USED"), button.tip_text())


func test_command_points_text_for_a_destroyed_c2_and_unlimited() -> void:
	_state.set_command_points_per_turn([1, 0] as Array[int])
	assert_eq(HudModel.command_points_text(_state, 0), "C2 1/1")
	_state.current_player = 1
	assert_eq(HudModel.command_points_text(_state, 1), "", "unlimited shows nothing")


func test_objectives_button_only_in_a_campaign_battle() -> void:
	var hud := BattleHud.new()
	hud.setup(0)
	assert_false(hud.action_bar().button(BattleHud.ACTION_OBJECTIVES).visible)
	hud.set_campaign("Take the hex")
	assert_true(hud.action_bar().button(BattleHud.ACTION_OBJECTIVES).visible)
	hud.free()


func test_hud_mission_line_click_emits() -> void:
	var hud := BattleHud.new()
	hud.setup(0)
	var fired := [false]
	hud.mission_pressed.connect(func() -> void: fired[0] = true)
	hud.set_campaign("Take the hex")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	hud._on_mission_input(click)
	assert_true(fired[0])
	hud.free()
