extends TestCase
## The river channel's water surface only falls downstream (TASK-216 realism pass).


func _line(count: int) -> PackedVector2Array:
	var line := PackedVector2Array()
	for i in count:
		line.append(Vector2(float(i) * 0.1, 0.0))
	return line


func test_levels_never_rise_downstream_over_a_bumpy_valley() -> void:
	var heights := PackedFloat32Array()
	var frees := PackedFloat32Array()
	for i in 40:
		heights.append(1.0 - float(i) * 0.02 + 0.08 * sin(float(i) * 1.3))  # falls with bumps
		frees.append(0.005)
	var level := RiverChannel.levels(heights, frees)
	for i in 39:
		assert_true(level[i + 1] <= level[i] + 1e-6, "level rises at %d" % i)
		assert_true(level[i] <= heights[i] + 1e-6, "water above the ground at %d" % i)


func test_levels_run_towards_the_lower_end_whichever_way_the_line_is_drawn() -> void:
	var up := PackedFloat32Array()
	var frees := PackedFloat32Array()
	for i in 20:
		up.append(0.2 + float(i) * 0.03)  # the line starts at the low end
		frees.append(0.0)
	var level := RiverChannel.levels(up, frees)
	for i in 19:
		assert_true(
			level[i] <= level[i + 1] + 1e-6, "must rise along the line, falling to the start"
		)


func test_levels_stay_at_or_above_the_water_plane() -> void:
	var heights := PackedFloat32Array([0.3, 0.1, -0.4, -0.5])
	var level := RiverChannel.levels(heights, PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))
	for value in level:
		assert_true(value >= TerrainSurface.WATER_SURFACE)


func test_water_is_flat_across_the_river_and_the_ground_never_rises() -> void:
	MapScale.reset()
	var base := func(_x: float, _z: float) -> float: return 0.5
	var waters: Array[PackedFloat32Array] = [PackedFloat32Array()]
	var lines: Array[PackedVector2Array] = [_line(12)]
	for i in 12:
		waters[0].append(MapScale.to_units(20.0))
	var channel := RiverChannel.build(lines, waters, base)
	var centre := channel.carved_height(0.5, 0.0, 0.5)
	assert_true(centre < 0.5, "the bed is dug below the bank")
	var level := channel.water_level(0.5, 0.0)
	assert_true(not is_nan(level) and level > centre and level < 0.5)
	assert_eq(channel.carved_height(0.5, 5.0, 0.5), 0.5)  # far away: untouched
