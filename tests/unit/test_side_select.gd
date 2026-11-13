extends TestCase
## The side selection before an operation starts (TASK-149): two cards, nothing pre-picked, START
## only after a pick, BACK / Esc cancel, the picked side goes to Session for the staff map.

const Menu := preload("res://src/presentation/ui/main_menu.gd")
const TEMP := "user://test_side_select_settings.cfg"

var _window: SideSelectWindow
var _definition: OperationDefinition
var _started: Array[StringName] = []
var _cancelled := 0


func before_each() -> void:
	_definition = OperationDefinition.find(&"suwalki_gap")
	_window = SideSelectWindow.new()
	_started.clear()
	_cancelled = 0
	_window.start_requested.connect(func(side: StringName) -> void: _started.append(side))
	_window.cancelled.connect(func() -> void: _cancelled += 1)
	_window.present(_definition, 1, Vector2(1440, 900))


func after_each() -> void:
	_window.free()
	Session.chosen_side = &""


func test_one_card_per_side_and_nothing_is_picked() -> void:
	assert_eq(_window.card_count(), 2)
	assert_eq(_window.picked_side(), &"")
	assert_true(_window.start_button().disabled, "START waits for a pick")
	assert_true(_window.visible)


func test_picking_a_card_enables_start_and_start_emits_the_side() -> void:
	_window.card(1).pressed.emit()
	assert_eq(_window.picked_side(), _definition.sides[1].id)
	assert_false(_window.start_button().disabled)
	_window.start_button().pressed.emit()
	assert_eq(_started, [_definition.sides[1].id] as Array[StringName])


func test_start_without_a_pick_emits_nothing() -> void:
	_window.start()
	assert_eq(_started.size(), 0)


func test_picked_card_is_the_player_and_the_other_the_opponent() -> void:
	_window.pick(0)
	assert_eq((_window.card(0).find_child("Tag", true, false) as Label).text, "◆ YOU COMMAND")
	assert_eq((_window.card(1).find_child("Tag", true, false) as Label).text, "OPPONENT · AI")
	_window.pick(1)
	assert_eq((_window.card(1).find_child("Tag", true, false) as Label).text, "◆ YOU COMMAND")


func test_cards_show_briefing_and_formation_counts_from_data() -> void:
	for index in 2:
		var brief := _window.card(index).find_child("Briefing", true, false) as Label
		assert_eq(brief.text, _definition.sides[index].briefing)
		assert_true(brief.text != "")
		assert_true(SideSelectWindow.formation_count(_definition, index) > 0)


func test_back_and_close_cancel() -> void:
	_window.back_button().pressed.emit()
	_window.close_button().pressed.emit()
	assert_eq(_cancelled, 2)


func test_operation_button_opens_the_selection_and_start_sets_the_session_side() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))
	var menu: Control = Menu.new()
	menu.settings_path = TEMP
	menu._ready()
	assert_false(menu.is_side_select_open())
	menu.operation_button().pressed.emit()
	assert_true(menu.is_side_select_open())
	menu.side_select().pick(0)
	menu.side_select().start()  # outside a tree: records the side, no scene change
	assert_eq(Session.chosen_side, menu.side_select().picked_side())
	menu.close_side_select()
	assert_false(menu.is_side_select_open())
	menu.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


func test_session_side_is_taken_once_and_cleared_by_abandon() -> void:
	Session.chosen_side = &"russia"
	assert_eq(Session.take_chosen_side(), &"russia")
	assert_eq(Session.take_chosen_side(), &"")
	Session.chosen_side = &"nato"
	Session.abandon()
	assert_eq(Session.chosen_side, &"")


func test_staff_map_plays_the_chosen_side_against_the_ai() -> void:
	Session.chosen_side = &"russia"
	var map := StaffMap.new()
	map.auto_build = false
	(Engine.get_main_loop() as SceneTree).root.add_child(map)
	assert_true(map.build_now())
	var sides := map.simulation().state.player_sides
	assert_eq(sides[map.viewer_player], &"russia")
	assert_eq(sides[map.ai_side], &"nato")
	assert_eq(Session.chosen_side, &"", "taken by the staff map")
	map.free()


func test_chooser_lists_nato_first_then_russia() -> void:
	assert_eq(_definition.sides[0].id, &"nato")
	assert_eq(_definition.sides[1].id, &"russia")


func test_side_argument_skips_the_chooser_unknown_value_does_not() -> void:
	assert_eq(Menu.side_from_args(PackedStringArray(["--side=russia"]), _definition), &"russia")
	assert_eq(Menu.side_from_args(PackedStringArray(["--side=NATO"]), _definition), &"nato")
	assert_eq(Menu.side_from_args(PackedStringArray(["--side=mars"]), _definition), &"")
	assert_eq(Menu.side_from_args(PackedStringArray(), _definition), &"")
