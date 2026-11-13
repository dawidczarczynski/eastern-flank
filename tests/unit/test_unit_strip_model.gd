extends TestCase
## The tactical unit in the bottom-bar strip: the staff map's StaffMapUnitStrip filled by
## UnitStripModel (replaces the terrain description while a unit is hovered or selected).

const Fixtures := preload("res://tests/fixtures.gd")

var _squad := load("res://data/units/pl_mech_infantry.tres") as UnitDefinition
var _state: GameState
var _own: Unit
var _hostile: Unit


func before_each() -> void:
	_state = GameState.new(Fixtures.plains_grid(3), 2, 1)
	_own = _state.add_unit(0, _squad, Vector2i.ZERO)
	_hostile = _state.add_unit(1, _squad, Vector2i(1, 0))


func test_own_unit_shows_health_moves_and_status() -> void:
	_own.hp = 7
	var m := UnitStripModel.build(_state, _own, 0)
	assert_eq(m["strength_text"], "7 / 10")
	assert_eq(m["posture_text"], "3 / 3")
	assert_eq(m["order_text"], "READY")
	assert_eq(m["side_text"], "OWN")
	assert_eq(m["lit"], StaffMapFormations.lit_segments(7, 10))
	assert_eq(m["gauge_color"], UiPalette.hp_color(7, 10))


func test_hostile_unit_is_marked_hostile_in_its_side_colour() -> void:
	var m := UnitStripModel.build(_state, _hostile, 0)
	assert_eq(m["side_text"], "HOSTILE")
	assert_eq(m["order_text"], "HOSTILE")
	assert_eq(m["side_color"], _state.faction_of(1).color)


func test_strip_renders_the_unit_model_with_unit_captions() -> void:
	var strip := StaffMapUnitStrip.new()
	strip.show_unit(UnitStripModel.build(_state, _own, 0))
	assert_eq(strip.tab_text(), "UNIT · OWN")
	assert_eq(strip.name_text(), "MECHANISED INFANTRY SQUAD")
	assert_eq(strip.value_text(0), "10 / 10")
	assert_true(strip.has_gauge())
	strip.free()
