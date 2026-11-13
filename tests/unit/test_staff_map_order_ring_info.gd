extends TestCase
## The INFO slot [5] of the order ring (TASK-151): always there, on a hex ring and on a counter.

const Fixtures := preload("res://tests/fixtures.gd")

var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


func _state() -> OperationalState:
	var state := OperationalState.new()
	var grid := HexGrid.new()
	for q in range(0, 6):
		grid.set_terrain(Vector2i(q, 0), Terrain.Type.PLAINS)
	state.grid = grid
	state.formations.append(Fixtures.formation(&"f", 0))
	return state


func test_hex_ring_has_info_in_slot_five() -> void:
	var state := _state()
	var model := StaffMapOrderRingModel.build(state, state.formations[0], Vector2i(3, 0))
	var slot: Dictionary = model["slots"][StaffMapOrderRingModel.SLOT_INFO]
	assert_eq(slot["key"], 5)
	assert_eq(slot["action"], StaffMapOrderRingModel.INFO)
	assert_eq(slot["icon"], &"info")
	assert_true(slot["enabled"])
	assert_false(slot["empty"])
	assert_false((model["details"][StaffMapOrderRingModel.SLOT_INFO] as Dictionary).is_empty())
	assert_true(model["slots"][5]["empty"], "slot 6 stays free")


func test_info_stays_with_a_standing_order() -> void:
	var state := _state()
	state.formations[0].order = FormationOrder.new(Vector2i(4, 0))
	var model := StaffMapOrderRingModel.build(state, state.formations[0], Vector2i(3, 0))
	assert_eq(model["slots"][3]["action"], StaffMapOrderRingModel.CANCEL)
	assert_eq(model["slots"][4]["action"], StaffMapOrderRingModel.INFO)


func test_counter_ring_has_only_cancel_and_info() -> void:
	var state := _state()
	var f := state.formations[0]
	var model := StaffMapOrderRingModel.build(state, f, f.coord, true)
	assert_true(model["on_counter"])
	for i in 4:
		assert_true(model["slots"][i]["empty"], "slot %d" % (i + 1))
	assert_eq(model["slots"][4]["action"], StaffMapOrderRingModel.INFO)
	f.order = FormationOrder.new(Vector2i(4, 0))
	model = StaffMapOrderRingModel.build(state, f, f.coord, true)
	assert_eq(model["slots"][3]["action"], StaffMapOrderRingModel.CANCEL)
	assert_true(model["slots"][0]["empty"])


func test_hex_ring_is_not_a_counter_ring() -> void:
	var state := _state()
	var model := StaffMapOrderRingModel.build(state, state.formations[0], Vector2i(2, 0))
	assert_false(model["on_counter"])
