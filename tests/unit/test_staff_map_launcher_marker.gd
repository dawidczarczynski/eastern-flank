extends TestCase
## The strike launcher marker of the staff map (TASK-147, variant B): glyph shapes per launcher
## kind, the lifetime / pop-in / pulse / stack helpers and the trail's marker bookkeeping.

const Model := preload("res://tests/unit/test_staff_map_strike_model.gd")
const A1 := &"a1"  # Russian airfield (6, 0)
const EPS := 0.001

# --- glyphs ---


func test_every_launcher_kind_maps_to_a_drawable_shape() -> void:
	for kind: StringName in StrikeMeansDefinition.LAUNCHER_KINDS:
		assert_eq(StaffMapLauncherGlyphs.shape_of(kind), kind, "%s has its own silhouette" % kind)
		assert_eq(StaffMapLauncherGlyphs.shape_of(String(kind)), kind, "the event's String kind")
		_assert_drawable(StaffMapLauncherGlyphs.shape(kind), kind)


func test_old_aircraft_kind_draws_a_fighter() -> void:
	assert_eq(StaffMapLauncherGlyphs.shape_of(&"aircraft"), &"fighter")


func test_unknown_kind_falls_back_to_a_dot() -> void:
	for kind: Variant in [&"", "", &"balloon", null]:
		assert_eq(StaffMapLauncherGlyphs.shape_of(kind), StaffMapLauncherGlyphs.DOT)
	var dot := StaffMapLauncherGlyphs.shape(&"balloon")
	assert_eq(dot["fills"].size(), 1, "one disc")
	_assert_drawable(dot, &"dot")


func test_kinds_have_distinct_silhouettes() -> void:
	var seen := {}
	for kind: StringName in StaffMapLauncherGlyphs.KINDS:
		var fills: Array = StaffMapLauncherGlyphs.shape(kind)["fills"]
		seen[str(fills)] = kind
	assert_eq(seen.size(), StaffMapLauncherGlyphs.KINDS.size())


func _assert_drawable(shape: Dictionary, kind: StringName) -> void:
	var fills: Array = shape["fills"]
	assert_true(not fills.is_empty(), "%s has polygons" % kind)
	for polygon: PackedVector2Array in fills + shape["cutouts"]:
		assert_true(polygon.size() >= 3, "%s: a polygon of 3+ points" % kind)
		assert_true(
			not Geometry2D.triangulate_polygon(polygon).is_empty(), "%s: triangulates" % kind
		)
		for point in polygon:
			assert_true(
				Rect2(0, 0, 24.0001, 24.0001).has_point(point), "%s: inside the 24 box" % kind
			)


# --- lifetime ---


func test_alpha_over_the_lifetime() -> void:
	var flight := 1.6
	assert_eq(StaffMapLauncherMarker.alpha_at(0.0, flight), 1.0, "t = 0")
	assert_eq(StaffMapLauncherMarker.alpha_at(flight / 2.0, flight), 1.0, "mid-flight")
	assert_eq(StaffMapLauncherMarker.alpha_at(flight, flight), 1.0, "flight end")
	assert_near(StaffMapLauncherMarker.alpha_at(flight + 0.3, flight), 0.5, "end + 0.3 s")
	assert_eq(StaffMapLauncherMarker.alpha_at(flight + 0.6, flight), 0.0, "end + 0.6 s")
	assert_eq(StaffMapLauncherMarker.alpha_at(-0.1, flight), 0.0, "before the launch")
	assert_near(StaffMapLauncherMarker.end_time(flight), flight + 0.6, "gone")


func test_marker_never_outlives_the_toast() -> void:
	var cap := 2.0
	assert_near(StaffMapLauncherMarker.end_time(5.0, cap), cap, "gone with the toast")
	assert_eq(StaffMapLauncherMarker.alpha_at(1.3, 5.0, cap), 1.0, "steady until the fade")
	assert_near(StaffMapLauncherMarker.alpha_at(1.7, 5.0, cap), 0.5, "fades out by the cap")
	assert_eq(StaffMapLauncherMarker.alpha_at(2.0, 5.0, cap), 0.0)
	assert_true(
		StaffMapLauncherMarker.toast_cap(true, 3.0) > StaffMapLauncherMarker.toast_cap(false, 3.0)
	)
	assert_near(
		StaffMapLauncherMarker.toast_cap(false, 3.0),
		3.0 + StaffMapStrikeReports.IMPACT_REVEAL_SECONDS + StaffMapStrikeReports.ENEMY_SECONDS,
		"revealed after the last impact, then the enemy card time"
	)
	assert_true(
		(
			StaffMapLauncherMarker.end_time(3.0, StaffMapLauncherMarker.toast_cap(false, 3.0))
			< StaffMapLauncherMarker.toast_cap(false, 3.0)
		),
		"the marker is gone before its card"
	)


func test_pop_in_and_pulse() -> void:
	assert_near(StaffMapLauncherMarker.pop_scale(0.0), 0.8, "pops in from .8")
	assert_near(StaffMapLauncherMarker.pop_scale(0.25), 1.0, "full size after 250 ms")
	assert_near(StaffMapLauncherMarker.pop_scale(3.0), 1.0)
	var start := StaffMapLauncherMarker.pulse(0.0)
	assert_near(start["radius"], 4.5, "pulse from the tick ring")
	assert_near(start["alpha"], 0.6)
	var half := StaffMapLauncherMarker.pulse(0.4)
	assert_near(half["radius"], 6.75)
	assert_near(half["alpha"], 0.3)
	assert_eq(StaffMapLauncherMarker.pulse(0.8)["alpha"], 0.0, "once, 800 ms")
	var box := StaffMapLauncherMarker.glyph_rect()
	assert_eq(box, Rect2(-14, -34, 28, 28), "28 px glyph 6 px above the tick")


func test_stack_offset_and_alpha() -> void:
	assert_eq(StaffMapLauncherMarker.stack_offset(0), Vector2.ZERO)
	assert_eq(StaffMapLauncherMarker.stack_offset(1), Vector2(14, -14))
	assert_eq(StaffMapLauncherMarker.stack_offset(2), Vector2(28, -28))
	assert_eq(StaffMapLauncherMarker.stack_alpha(0), 1.0)
	assert_eq(StaffMapLauncherMarker.stack_alpha(1), 0.7)
	assert_eq(StaffMapLauncherMarker.stack_alpha(2), 0.45)


# --- trail bookkeeping ---


func _strike(
	trail: StaffMapStrikeTrail,
	state: OperationalState,
	origin: Vector2i,
	kind := "launcher",
	player := 0
) -> void:
	var launched := {
		"type": &"strike_launched",
		"player": player,
		"means": &"sure",
		"count": 2,
		"target": A1,
		"coord": state.get_installation(A1).coord,
		"class_id": &"airfield",
		"launcher_kind": kind,
		"origin": origin,
	}
	trail.on_event(state, 0, launched)
	(
		trail
		. on_event(
			state,
			0,
			{
				"type": &"strike_resolved",
				"player": player,
				"means": &"sure",
				"target": A1,
				"count": 2,
				"intercepted": 0,
				"hits": 2,
				"misses": 0,
				"interceptor_ids": [],
			}
		)
	)


func test_a_seen_strike_adds_a_marker_at_the_events_origin() -> void:
	var state := Model._state(2)
	var trail := StaffMapStrikeTrail.new()
	_strike(trail, state, Vector2i(3, 1), "aircraft")
	assert_eq(trail.launchers.size(), 1)
	var marker := trail.launchers[0]
	assert_eq(marker["origin"], Vector2i(3, 1))
	assert_eq(marker["kind"], "aircraft")
	var means: StrikeMeansDefinition = state.strike_means[&"sure"]
	assert_eq(marker["label"], means.platform, "the means' platform text")
	var first: Dictionary = trail.traces[0]
	assert_near(first["start"], StaffMapLauncherMarker.lead_in(&"aircraft"), "the marker leads in")
	var last: Dictionary = trail.traces[-1]
	assert_near(marker["flight"], last["start"] + last["duration"], "lead-in + longest trace")
	assert_near(trail.seconds_to_last_impact(), marker["flight"], "the card waits for the impact")
	assert_eq(trail.launcher_alpha(marker), 1.0)
	trail.clock = float(marker["flight"]) + 0.3
	assert_near(trail.launcher_alpha(marker), 0.5)
	assert_true(trail.animating(), "the layer keeps redrawing while a marker fades")
	trail.clock = float(marker["flight"]) + 0.6
	assert_true(trail.visible_launchers().is_empty(), "gone 0.6 s after the flight")
	trail.clock = 10.0
	assert_false(trail.animating(), "idle afterwards")


func test_unseen_strike_has_no_marker_and_turn_start_clears() -> void:
	var state := Model._state(2)
	var trail := StaffMapStrikeTrail.new()
	trail.is_visible = func(_coord: Vector2i, _player: int) -> bool: return false
	_strike(trail, state, Vector2i(3, 1))
	assert_eq(trail.launchers.size(), 0, "fog: the viewer does not see the launch")
	trail.is_visible = func(_coord: Vector2i, _player: int) -> bool: return true
	_strike(trail, state, Vector2i(3, 1))
	trail.on_event(state, 0, {"type": &"operational_turn_started", "player": 0})
	assert_eq(trail.launchers.size(), 0)


func test_same_hex_markers_stack_newest_first_max_three() -> void:
	var state := Model._state(2)
	var trail := StaffMapStrikeTrail.new()
	for i in 4:
		_strike(trail, state, Vector2i(3, 1))
	_strike(trail, state, Vector2i(2, 1))
	var shown := trail.visible_launchers()
	assert_eq(shown.size(), 4, "3 on the crowded hex + 1 elsewhere")
	assert_eq(shown[0]["marker"]["origin"], Vector2i(2, 1), "newest first")
	assert_eq(shown[0]["slot"], 0)
	var slots: Array[int] = []
	for item in shown.slice(1):
		slots.append(int(item["slot"]))
	assert_eq(slots, [0, 1, 2] as Array[int], "newest on the tick, older ones up-right")
	assert_eq(int(shown[1]["marker"]["strike"]), 4, "the oldest on the hex was dropped")


func test_at_most_eight_markers() -> void:
	var state := Model._state(2)
	var trail := StaffMapStrikeTrail.new()
	for i in 10:
		_strike(trail, state, Vector2i(i % 4, i / 4))
	assert_eq(trail.launchers.size(), StaffMapLauncherMarker.MAX_MARKERS)


func test_enemy_marker_is_capped_by_the_shorter_toast() -> void:
	var state := Model._state(2)
	var trail := StaffMapStrikeTrail.new()
	_strike(trail, state, Vector2i(6, 1), "ship", 1)
	assert_eq(trail.launchers[0]["player"], 1)
	var marker := trail.launchers[0]
	assert_near(marker["cap"], StaffMapLauncherMarker.toast_cap(false, marker["flight"]))


func assert_near(value: Variant, expected: float, message := "") -> void:
	assert_true(absf(float(value) - expected) < EPS, "%s (%s vs %s)" % [message, value, expected])


# --- aircraft flyover ---


func test_aircraft_approach_launch_and_u_turn() -> void:
	var origin := Vector2(400, 300)
	var target := Vector2(800, 300)  # the target is to the right
	var forward := Vector2.RIGHT
	var start := StaffMapLauncherFlyover.pose(0.0, origin, target)
	assert_true(
		(start["at"] - origin).dot(forward) < -200.0, "appears behind the launch point: %s" % start
	)
	assert_true((start["heading"] as Vector2).dot(forward) > 0.99, "faces the target")
	var mid := StaffMapLauncherFlyover.pose(0.9, origin, target)
	assert_true((mid["heading"] as Vector2).dot(forward) > 0.99, "flies straight at it")
	var launch := StaffMapLauncherFlyover.pose(
		StaffMapLauncherFlyover.APPROACH_SECONDS, origin, target
	)
	assert_true((launch["at"] as Vector2).distance_to(origin) < 0.01, "over the launch point")
	assert_eq(
		StaffMapLauncherMarker.lead_in(&"bomber"),
		StaffMapLauncherFlyover.APPROACH_SECONDS,
		"the missiles leave when the aircraft arrives"
	)
	assert_eq(StaffMapLauncherMarker.lead_in(&"launcher"), StaffMapLauncherMarker.LEAD_IN_SECONDS)
	var end := StaffMapLauncherFlyover.end_time()
	var turned := StaffMapLauncherFlyover.pose(end - 0.001, origin, target)
	assert_true((turned["heading"] as Vector2).dot(forward) < -0.9, "turned away: %s" % turned)
	assert_true(absf((turned["at"] as Vector2).y - origin.y) > 50.0, "banked off to one side")
	assert_true((turned["at"] as Vector2).x - origin.x < 60.0, "not over the target")
	assert_eq(StaffMapLauncherFlyover.alpha_at(end), 0.0, "gone after the turn")
	assert_eq(StaffMapLauncherFlyover.alpha_at(1.0), 1.0)
	assert_true(StaffMapLauncherFlyover.alpha_at(end - 0.3) < 0.6, "fades over the turn's end")


func test_stacked_aircraft_fly_apart() -> void:
	var origin := Vector2(400, 300)
	var target := Vector2(400, 0)  # the target is up
	var a := StaffMapLauncherFlyover.variant(1)
	var b := StaffMapLauncherFlyover.variant(2)
	assert_true(a["side"] != b["side"], "turn to different sides")
	var end := StaffMapLauncherFlyover.end_time() - 0.01
	var pa := StaffMapLauncherFlyover.pose(end, origin, target, a["side"], a["lateral"])
	var pb := StaffMapLauncherFlyover.pose(end, origin, target, b["side"], b["lateral"])
	assert_true((pa["at"] as Vector2).distance_to(pb["at"]) > 100.0)
	var sa := StaffMapLauncherFlyover.pose(0.0, origin, target, a["side"], a["lateral"])
	var sb := StaffMapLauncherFlyover.pose(0.0, origin, target, b["side"], b["lateral"])
	assert_true((sa["at"] as Vector2).distance_to(sb["at"]) > 5.0, "different approach lines")


func test_aircraft_marker_lives_through_its_turn_and_leads_in_with_the_approach() -> void:
	var state := Model._state(2)
	var trail := StaffMapStrikeTrail.new()
	_strike(trail, state, Vector2i(3, 1), "bomber")
	var marker := trail.launchers[0]
	assert_near(trail.traces[0]["start"], StaffMapLauncherFlyover.APPROACH_SECONDS)
	assert_true(
		StaffMapStrikeTrail.launcher_end(marker) >= StaffMapLauncherFlyover.end_time(),
		"alive until the U-turn ends"
	)
	assert_true(
		StaffMapStrikeTrail.launcher_end(marker) < float(marker["cap"]), "gone before its card"
	)
	assert_eq(marker["to"], state.get_installation(A1).coord, "faces the target hex")
