extends TestCase
## The devtools terrain viewer's setup: a cut of the shipped tactical layer around an operational
## hex, with no companies, that still builds a battle state.

static var _state: OperationalState


func before_all() -> void:
	_state = Operation.build(&"suwalki_gap", 1)


func after_all() -> void:
	_state = null


func test_the_cut_is_centred_on_the_hex_and_has_no_units() -> void:
	var hex := MapGenerator.offset_to_axial(20, 40)
	var setup := TerrainViewSetup.build(_state.map_id, hex)
	assert_true(setup != null)
	var settings := ContactSettings.shipped()
	assert_eq(setup.map_id, settings.layer_for(_state.map_id))
	assert_eq(setup.map_region.size, Vector2i(settings.width, settings.height))
	assert_true(setup.companies.is_empty())
	assert_true(setup.operation_name.contains("20"))
	var state := Scenario.from_setup(setup)
	assert_true(state != null, "the view builds a state")
	assert_true(state.units.is_empty())


func test_the_cut_follows_the_hex() -> void:
	var west := TerrainViewSetup.build(_state.map_id, MapGenerator.offset_to_axial(10, 40))
	var east := TerrainViewSetup.build(_state.map_id, MapGenerator.offset_to_axial(30, 40))
	assert_true(east.map_region.position.x > west.map_region.position.x)
