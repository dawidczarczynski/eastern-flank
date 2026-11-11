extends TestCase
## The look data of the strike weapons (TASK-141b): one file per shipped means, values in range, a
## default for an unknown id, and the duration / shade helpers.


func test_every_shipped_means_has_a_look_in_range() -> void:
	for id in StrikeMeansDefinition.SHIPPED:
		var path := "%s%s.tres" % [StrikeWeaponLook.DIR, id]
		assert_true(ResourceLoader.exists(path), "look file for %s" % id)
		var look := StrikeWeaponLook.for_means(id)
		assert_eq(look.problem(), "", "%s: %s" % [id, look.problem()])
		assert_true(look.resource_path.ends_with("%s.tres" % id), "%s loads its own file" % id)


func test_unknown_means_gets_the_default_look() -> void:
	for id: StringName in [&"nope", &"", &"../x", &"a.b"]:
		var look := StrikeWeaponLook.for_means(id)
		assert_true(look != null and look.problem() == "", "default for '%s'" % id)
		assert_eq(look.resource_path, "")


func test_weapon_families_read_differently() -> void:
	var ballistic := StrikeWeaponLook.for_means(&"iskander_m")
	var cruise := StrikeWeaponLook.for_means(&"kalibr")
	var drone := StrikeWeaponLook.for_means(&"geran_2")
	var rocket := StrikeWeaponLook.for_means(&"homar_k")
	assert_eq(ballistic.glyph, &"ballistic")
	assert_eq(cruise.glyph, &"missile")
	assert_eq(drone.glyph, &"drone")
	assert_eq(StrikeWeaponLook.for_means(&"warmate").glyph, &"loitering")
	assert_eq(rocket.glyph, &"rocket")
	assert_true(ballistic.arc_height > rocket.arc_height and rocket.arc_height > cruise.arc_height)
	assert_true(ballistic.duration(60.0) < cruise.duration(60.0))
	assert_true(cruise.duration(60.0) < drone.duration(60.0))
	assert_true(drone.wobble > 0.0 and cruise.wobble == 0.0)
	assert_true(
		StrikeWeaponLook.for_means(&"kinzhal").speed_hexes_per_s > ballistic.speed_hexes_per_s
	)
	assert_eq(ballistic.warhead, &"heavy_blast")
	assert_eq(rocket.warhead, &"cluster")
	assert_eq(drone.warhead, &"small")


func test_duration_is_clamped() -> void:
	var look := StrikeWeaponLook.new()
	look.speed_hexes_per_s = 100.0
	assert_eq(look.duration(1.0), StrikeWeaponLook.DURATION_MIN)
	assert_eq(look.duration(10000.0), StrikeWeaponLook.DURATION_MAX)
	assert_true(absf(look.duration(100.0) - 1.0) < 0.001)


func test_shade_mixes_towards_the_trail_colour_and_keeps_the_side() -> void:
	var look := StrikeWeaponLook.new()
	var side := Color(0.2, 0.4, 0.8)
	assert_eq(look.shade(side), side, "alpha 0 keeps the side colour")
	look.trail_color = Color(1, 1, 1, 1)
	assert_eq(look.shade(side), Color(1, 1, 1))
	look.trail_color = Color(1, 1, 1, 0.5)
	var half := look.shade(side)
	assert_true(absf(half.r - 0.6) < 0.001 and absf(half.b - 0.9) < 0.001)


func test_problem_flags_bad_values() -> void:
	var look := StrikeWeaponLook.new()
	look.glyph = &"banana"
	assert_true(look.problem().contains("glyph"))
	look.glyph = &"drone"
	look.arc_height = 0.9
	assert_true(look.problem().contains("arc_height"))
