extends TestCase
## Scene test for the HUD v3 unit card (TASK-078): built headless (no scene tree) for every
## unit class and filled from UnitPopupModel.

const Fixtures := preload("res://tests/fixtures.gd")
const MAX_HEIGHT := 620.0
const UNITS: Array[String] = [
	"pl_mech_infantry", "m1a2_sepv3", "t72b3", "homar_k", "bm27_uragan", "ru_motor_rifle"
]

var _popup: UnitPopup


func before_each() -> void:
	_popup = UnitPopup.new()


func after_each() -> void:
	_popup.free()


func _model(id: String, owner_id: int = 0, effects: Array[String] = []) -> Dictionary:
	var state := GameState.new(Fixtures.plains_grid(3), 2, 1)
	var definition := load("res://data/units/%s.tres" % id) as UnitDefinition
	var unit := state.add_unit(owner_id, definition, Vector2i.ZERO)
	return UnitPopupModel.build(state, unit, 0, effects)


func test_builds_for_every_unit_class() -> void:
	for id in UNITS:
		_popup.show_model(_model(id))
		assert_true(_popup.visible, id)
		var card := _popup.card_size()
		assert_eq(card.x, 320.0, id)
		assert_true(card.y > 250.0 and card.y <= MAX_HEIGHT, "%s height %s" % [id, card.y])
		assert_eq(_popup.tab_text, tr(_model(id)["type"] as String).to_upper())


func test_stays_within_620_px_with_eight_tags_and_a_note() -> void:
	var effects: Array[String] = []
	for i in 7:
		effects.append("Camouflaged position %d" % i)
	var model := _model("ru_motor_rifle", 1, effects)
	model["note"] = "A long note that wraps over several lines of the card. ".repeat(3)
	assert_eq((model["tags"] as Array).size(), 8)
	_popup.show_model(model)
	assert_true(_popup.card_size().y <= MAX_HEIGHT, "height %s" % _popup.card_size().y)


func test_frame_follows_faction_color() -> void:
	var model := _model("t72b3", 1)
	_popup.show_model(model)
	assert_eq(_popup.tab_color, model["color"])
	assert_eq(_popup.tab_right_color, model["color"])


func test_suppressed_hides_and_blocks_show() -> void:
	_popup.show_model(_model("t72b3"))
	assert_true(_popup.visible)
	_popup.suppressed = true
	assert_false(_popup.visible)
	_popup.show_model(_model("t72b3"))
	assert_false(_popup.visible)
	_popup.suppressed = false
	_popup.show_model(_model("t72b3"))
	assert_true(_popup.visible)


func test_hides_designation_and_note_when_absent() -> void:
	_popup.show_model(_model("pl_mech_infantry"))
	assert_false(_popup._designation_label.visible)
	assert_false(_popup._note_wrap.visible)
	_popup.show_model(_model("m1a2_sepv3"))
	assert_true(_popup._designation_label.visible)
	assert_eq(_popup._designation_label.text, "M1A2")


func test_ignores_the_mouse() -> void:
	assert_eq(_popup.mouse_filter, Control.MOUSE_FILTER_IGNORE)
