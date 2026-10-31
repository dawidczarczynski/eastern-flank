extends TestCase

const TOLERANCE := 0.5


func _near(actual: float, expected: float, message: String) -> void:
	assert_true(absf(actual - expected) <= TOLERANCE, "%s (got %s)" % [message, actual])


func test_dust_rate_follows_ground_speed() -> void:
	_near(MotionEffects.dust_rate(&"tank", MotionEffects.FULL_SPEED), 24.0, "tank full")
	assert_eq(MotionEffects.dust_rate(&"tank", 0.0), 0.0)
	_near(MotionEffects.dust_rate(&"mlrs", MotionEffects.FULL_SPEED / 2.0), 7.0, "mlrs half")
	assert_eq(MotionEffects.dust_rate(&"infantry", MotionEffects.FULL_SPEED), 0.0)
	_near(MotionEffects.dust_rate(&"tank", 10.0), 24.0, "clamped")


func test_dust_colour_by_terrain() -> void:
	assert_eq(MotionEffects.dust_color(Terrain.Type.PLAINS), Color("a39477"))
	assert_eq(MotionEffects.dust_color(Terrain.Type.HILLS), Color("a39477"))
	assert_eq(MotionEffects.dust_color(Terrain.Type.FOREST), Color("7d6f58"))
	assert_eq(MotionEffects.dust_color(Terrain.Type.WATER).a, 0.0, "no dust on water")
	var weights := PackedFloat32Array()
	weights.resize(TerrainSplat.LAYER_COUNT)
	weights[TerrainSplat.MUD] = 0.5
	assert_eq(MotionEffects.dust_color(Terrain.Type.PLAINS, weights), Color("5a4a38"))
	assert_eq(MotionEffects.dust_rate_factor(Terrain.Type.PLAINS, weights), 0.4)
	assert_eq(MotionEffects.dust_rate_factor(Terrain.Type.PLAINS), 1.0)


func test_exhaust_is_strongest_when_starting_off() -> void:
	var start := MotionEffects.exhaust_rate(&"tank", MotionEffects.exhaust_load(0.0, 0.0, 0.0))
	var later := MotionEffects.exhaust_rate(&"tank", MotionEffects.exhaust_load(3.0, 0.0, 3.1))
	assert_true(start >= 3.0 * later, "start %s vs cruising %s" % [start, later])
	assert_true(later > 0.0, "a thin stream while cruising")


func test_exhaust_is_strong_when_pivoting_in_place() -> void:
	var cruising := MotionEffects.exhaust_load(3.0, 0.0, 3.1)
	var pivoting := MotionEffects.exhaust_load(3.0, 1.2, 0.3)
	var turning_fast := MotionEffects.exhaust_load(3.0, 1.2, 3.1)
	assert_true(pivoting > 0.8, "pivot load %s" % pivoting)
	assert_true(pivoting > turning_fast, "a pivot beats a bend at speed")
	assert_true(pivoting > cruising)


func test_exhaust_load_decays_after_the_start() -> void:
	var l0 := MotionEffects.exhaust_load(0.0, 0.0, 1.0)
	var l1 := MotionEffects.exhaust_load(1.0, 0.0, 1.0)
	var l3 := MotionEffects.exhaust_load(6.0, 0.0, 1.0)
	assert_true(l0 > l1 and l1 > l3, "decays")
	assert_true(l3 < 0.1, "nearly gone after 6 s")


func test_no_exhaust_for_infantry() -> void:
	assert_eq(MotionEffects.exhaust_rate(&"infantry", 1.0), 0.0)
	assert_true(MotionEffects.emits(&"tank") and MotionEffects.emits(&"mlrs"))
	assert_false(MotionEffects.emits(&"infantry"))


func test_wheeled_trucks_raise_smaller_clouds_than_tanks() -> void:
	assert_true(MotionEffects.cloud_size(&"mlrs") < MotionEffects.cloud_size(&"tank"))
	assert_true(MotionEffects.exhaust_rate(&"mlrs", 1.0) < MotionEffects.exhaust_rate(&"tank", 1.0))


func test_dust_on_real_terrain_types() -> void:
	assert_eq(MotionEffects.dust_color(Terrain.Type.FIELDS), MotionEffects.DUST_PLAINS)
	assert_eq(MotionEffects.dust_color(Terrain.Type.URBAN), MotionEffects.DUST_PLAINS)
	assert_eq(MotionEffects.dust_color(Terrain.Type.MARSH), MotionEffects.DUST_MUD)
	assert_eq(MotionEffects.dust_rate_factor(Terrain.Type.MARSH), MotionEffects.MUD_RATE_FACTOR)
	assert_eq(MotionEffects.dust_rate_factor(Terrain.Type.FIELDS), 1.0)
