# gdlint: disable=max-public-methods
extends TestCase
## The pure view model of the strike mode (TASK-097b): reasons, escalation lines, raise-and-strike
## and the trail bookkeeping, all on TASK-115's strip grid (Poland | Lithuania | Belarus | Russia).

const Strikes := preload("res://tests/unit/test_strikes.gd")
const A1 := &"a1"  # Russian airfield (6, 0), in the Russian sanctuary
const D1 := &"d1"  # Russian depot (7, 1)
const AD := &"ru_ad"  # Russian air defence (7, 0)

static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


static func _state(level := 1) -> OperationalState:
	var op := Strikes._definition()
	op.installations.append(Strikes._placement(AD, &"air_defence", 1, Vector2i(7, 0)))
	op.installations.append(Strikes._placement(&"by", &"depot", 1, Vector2i(5, 0)))  # Belarus
	var state := Strikes._state(op)
	state.escalation_level = level
	return state


func _view(state: OperationalState, target: StringName, means := &"sure") -> Dictionary:
	return StaffMapStrike.target_view(state, 0, target, means)


# --- means, salvo, open problem ---


func test_means_list_and_salvo() -> void:
	var state := _state()
	var list := StaffMapStrike.means_list(state, 0)
	var sure: Dictionary = list.filter(func(m: Dictionary) -> bool: return m["id"] == &"sure")[0]
	assert_eq(sure["stock"], 10)
	assert_eq(sure["range_hexes"], 50)
	assert_eq(sure["max_salvo"], 4)
	assert_eq(StaffMapStrike.salvo_max(state, 0, &"sure"), 4)
	state.strike_stock[0][&"sure"] = 3
	assert_eq(StaffMapStrike.salvo_max(state, 0, &"sure"), 3)
	state.strike_stock[0][&"sure"] = 0
	assert_eq(StaffMapStrike.salvo_max(state, 0, &"sure"), 0)
	assert_eq(StaffMapStrike.salvo_max(state, 0, &"nope"), 0)
	assert_eq(StaffMapStrike.strikes_text(state), "Strikes: 2/2")


func test_open_problem() -> void:
	var state := _state()
	assert_eq(StaffMapStrike.open_problem(state, 0), "")
	assert_eq(StaffMapStrike.open_problem(state, 1), "not_your_turn")
	state.pending_battles.append(BattleSetup.new())
	assert_eq(StaffMapStrike.open_problem(state, 0), "battle_pending")
	state.pending_battles.clear()
	state.result = {"winner": 0, "reason": &"x"}
	assert_eq(StaffMapStrike.open_problem(state, 0), "operation_over")


# --- reasons ---


func test_reason_texts() -> void:
	var state := _state()
	state.decisions_left = 0  # no raise-and-strike: the plain reason
	var closed := _view(state, A1)
	assert_false(closed["legal"])
	assert_eq(closed["reason_code"], "closed_country")
	assert_eq(closed["reason_text"], "Closed soil – opens at Open war")
	state.escalation_level = 2
	state.decisions_left = 1
	var legal := _view(state, A1)
	assert_true(legal["legal"])
	assert_eq(legal["reason_text"], "", "a legal target has no reason")
	var far := _view(state, A1, &"short")
	assert_eq(far["reason_code"], "out_of_range")
	assert_eq(far["reason_text"], "Out of range of short")
	state.get_installation(A1).integrity = 0
	var destroyed := _view(state, A1)
	assert_eq(destroyed["reason_code"], "target_destroyed")
	assert_eq(destroyed["reason_text"], "Already destroyed")
	assert_eq(StaffMapStrike.reason_text(state, 0, A1, &"sure", "own_soil"), "Own territory")


func test_roe_class_text() -> void:
	var state := _state()
	state.get_country(&"russia").breached_by[0] = true  # open to the strike, the level is not
	var view := _view(state, A1)
	assert_eq(view["reason_code"], "roe_class")
	state.decisions_left = 0  # no way to raise: the plain text stays
	view = _view(state, A1)
	assert_eq(view["reason_text"], "Not allowed at this level – needs Open war")
	assert_false(view["conditional"])


func test_closed_text_of_hostile_country() -> void:
	var state := _state(2)
	var view := _view(state, &"by")
	assert_eq(view["reason_code"], "closed_country")
	assert_eq(view["reason_text"], "Closed soil – opens at Regional war")


# --- raise and strike ---


func test_raise_offered_one_level_short() -> void:
	var state := _state(1)
	assert_true(StaffMapStrike.raise_offered(state, 0, A1, &"sure"), "airfield: sanctuary opens")
	assert_true(StaffMapStrike.raise_offered(state, 0, D1, &"sure"), "depot too")
	var view := _view(state, A1)
	assert_true(view["conditional"])
	assert_false(view["legal"])
	assert_eq(view["reason_text"], "Needs Open war – raise the level first")


func test_raise_not_offered_two_levels_short_or_spent_or_enough() -> void:
	var state := _state(0)
	assert_false(StaffMapStrike.raise_offered(state, 0, A1, &"sure"), "two levels short")
	assert_eq(_view(state, A1)["reason_code"], "closed_country")
	state.escalation_level = 1
	state.decisions_left = 0
	assert_false(StaffMapStrike.raise_offered(state, 0, A1, &"sure"), "decision spent")
	state.decisions_left = 1
	state.escalation_level = 2
	assert_false(StaffMapStrike.raise_offered(state, 0, A1, &"sure"), "the level is enough")
	assert_true(_view(state, A1)["legal"])


func test_raise_not_offered_out_of_range_or_standing_down_or_wrong_class() -> void:
	var state := _state(1)
	assert_false(StaffMapStrike.raise_offered(state, 0, A1, &"short"), "out of range")
	state.stand_down_until[0] = state.turn + 1
	assert_false(StaffMapStrike.raise_offered(state, 0, A1, &"sure"), "standing down")
	state.stand_down_until[0] = -1
	state.get_country(&"russia").breached_by[0] = true
	var airfield := _view(state, A1)  # open soil, class not allowed at 1, allowed at 2
	assert_true(airfield["conditional"])
	assert_eq(airfield["reason_code"], "roe_class")
	state.escalation_level = 0  # a depot needs level 1: one step is enough, the airfield is not
	assert_false(StaffMapStrike.raise_offered(state, 0, A1, &"sure"), "airfield two short")
	assert_true(StaffMapStrike.raise_offered(state, 0, D1, &"sure"), "depot one short")


func test_raise_not_offered_for_a_closed_non_sanctuary_country() -> void:
	var state := _state(2)
	assert_false(StaffMapStrike.raise_offered(state, 0, &"by", &"sure"))
	assert_false(_view(state, &"by")["conditional"])


# --- escalation lines ---


func test_escalation_lines() -> void:
	var state := _state(2)
	var lines := StaffMapStrike.escalation_lines(state, 0, A1)
	assert_eq(lines.size(), 2, str(lines))
	assert_true(lines[0]["text"].begins_with("Breaches "), lines[0]["text"])
	assert_true(lines[0]["text"].ends_with("sanctuary: +1 escalation"), lines[0]["text"])
	assert_eq(lines[1]["text"], "Escalation level: Regional war")
	assert_false(lines[1]["danger"])
	state.get_country(&"russia").breached_by[0] = true
	assert_eq(StaffMapStrike.escalation_lines(state, 0, A1), [], "no escalation: no lines")


func test_urban_hex_adds_a_line() -> void:
	var state := _state(2)
	state.get_country(&"russia").breached_by[0] = true
	state.grid.set_terrain(Vector2i(7, 1), Terrain.Type.URBAN)
	var lines := StaffMapStrike.escalation_lines(state, 0, D1)
	assert_eq(lines[0]["text"], "Urban hex: +1 escalation")
	assert_eq(lines[1]["text"], "Escalation level: Regional war")


func test_no_threshold_line_near_the_cap() -> void:
	# TASK-140: incidents stop at the cap, so no line ends the operation.
	var state := _state(4)
	var lines := StaffMapStrike.escalation_lines(state, 0, A1)
	assert_eq(lines.back()["text"], "Escalation level: Strategic alert")
	for line in lines:
		assert_false(line["danger"], str(line))
	var raised := StaffMapStrike.escalation_lines(state, 0, A1, true)
	assert_eq(raised.size(), 1, "the raise reaches the cap first: " + str(raised))
	assert_eq(raised[0]["text"], "Already at the highest level – no further escalation")


func test_incident_at_the_cap_reads_no_further_escalation() -> void:
	var state := _state(4)
	state.escalation_level = state.ladder.cap()
	var lines := StaffMapStrike.escalation_lines(state, 0, A1)
	assert_eq(lines.size(), 1, str(lines))
	assert_eq(lines[0]["text"], "Already at the highest level – no further escalation")
	assert_false(lines[0]["danger"])
	state.get_country(&"russia").breached_by[0] = true
	assert_eq(StaffMapStrike.escalation_lines(state, 0, A1), [], "no incident: no lines")


func test_confirm_model_with_raise() -> void:
	var state := _state(1)
	var plain := StaffMapStrike.confirm_model(state, 0, A1, &"sure", 2, false)
	assert_eq(plain["means_line"], "2 × sure")
	assert_eq(plain["salvo_line"], "2 × sure on a1")
	assert_eq(plain["raise_line"], "")
	var raised := StaffMapStrike.confirm_model(state, 0, A1, &"sure", 2, true)
	assert_eq(raised["raise_line"], "Escalate to Open war (uses this turn's decision)")
	assert_eq(raised["lines"][raised["lines"].size() - 1]["text"], "Escalation level: Regional war")
	assert_false(raised["danger"])


# --- trail ---


func _launched(target: StringName, coord: Vector2i, player := 0) -> Dictionary:
	return {
		"type": &"strike_launched",
		"player": player,
		"means": &"sure",
		"count": 2,
		"target": target,
		"coord": coord,
		"class_id": &"airfield",
	}


func _resolved(target: StringName, intercepted: int, hits: int, player := 0) -> Dictionary:
	return {
		"type": &"strike_resolved",
		"player": player,
		"means": &"sure",
		"target": target,
		"count": 2,
		"intercepted": intercepted,
		"hits": hits,
		"misses": 2 - intercepted - hits,
	}


func _feed(
	trail: StaffMapStrikeTrail, state: OperationalState, target: StringName, intercepted: int
) -> void:
	var coord := state.get_installation(target).coord
	trail.on_event(state, 0, _launched(target, coord))
	trail.on_event(state, 0, _resolved(target, intercepted, 2 - intercepted))


func test_origin_is_the_nearest_own_hex_and_follows_the_country() -> void:
	var state := _state(2)
	var from := StaffMapStrikeTrail.origin(state, 0, Vector2i(7, 0))
	assert_eq(from.x, 3, "Lithuania (aligned) is the nearest own soil")
	CountryRules.set_stance(state, &"lithuania", &"neutral", -1, &"test", -1)
	var other := StaffMapStrikeTrail.origin(state, 0, Vector2i(7, 0))
	assert_eq(other.x, 1, "Poland is the nearest once Lithuania is out")
	assert_eq(Hex.distance(other, Vector2i(7, 0)) > Hex.distance(from, Vector2i(7, 0)), true)
	var russia := StaffMapStrikeTrail.origin(state, 1, Vector2i(0, 0))
	assert_eq(russia.x, 4, "Belarus is the other side's nearest own soil")


func test_interceptors_only_intact_enemy_sites_in_radius() -> void:
	var state := _state(2)
	var sites := StaffMapStrikeTrail.interceptors(state, 1, Vector2i(6, 0))
	assert_eq(sites.size(), 1)
	assert_eq(sites[0]["id"], AD)
	assert_eq(StaffMapStrikeTrail.interceptors(state, 0, Vector2i(6, 0)).size(), 0, "not own sites")
	assert_eq(StaffMapStrikeTrail.interceptors(state, 1, Vector2i(0, 0)).size(), 0, "too far")
	state.get_installation(AD).integrity = 0
	assert_eq(StaffMapStrikeTrail.interceptors(state, 1, Vector2i(6, 0)).size(), 0, "destroyed")


func test_strike_makes_one_trace_and_one_burst_per_missile() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	_feed(trail, state, A1, 0)
	assert_eq(trail.trace_count(), 2, "salvo of 2 = 2 arcs")
	assert_eq(trail.burst_count(), 2)
	assert_eq(trail.strike_count(), 1)
	assert_eq(trail.traces[0]["to"], Vector2i(6, 0))
	assert_eq(trail.bursts[0]["outcome"], StaffMapStrikeTrail.HIT)
	assert_true(trail.animating())
	assert_eq(trail.traces[0]["marks"], [], "no interception: no marks")
	assert_true(trail.traces[1]["start"] > trail.traces[0]["start"], "staggered")


func test_missile_outcomes_intercepted_first() -> void:
	var event := {"count": 5, "intercepted": 2, "hits": 2, "misses": 1}
	var list := StaffMapStrikeTrail.missile_outcomes(event)
	assert_eq(list.size(), 5)
	assert_eq(list.count(StaffMapStrikeTrail.INTERCEPTED), 2)
	assert_eq(list[0], StaffMapStrikeTrail.INTERCEPTED)
	assert_eq(list[2], StaffMapStrikeTrail.HIT)
	assert_eq(list[4], StaffMapStrikeTrail.MISSED)


func test_variation_and_miss_offset_are_deterministic_and_vary() -> void:
	assert_eq(StaffMapStrikeTrail.variation(5, 1), StaffMapStrikeTrail.variation(5, 1))
	assert_true(
		StaffMapStrikeTrail.variation(5, 0)["delay"] != StaffMapStrikeTrail.variation(5, 1)["delay"]
	)
	var offset := StaffMapStrikeTrail.miss_offset(42)
	assert_eq(offset, StaffMapStrikeTrail.miss_offset(42))
	assert_true(offset.length() >= StaffMapStrikeTrail.MISS_MIN_PX - 0.01)
	assert_true(offset.length() <= StaffMapStrikeTrail.MISS_MAX_PX + 0.01)


func test_interception_marks_and_outcomes() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	_feed(trail, state, A1, 1)
	var marks: Array = trail.traces[0]["marks"]
	assert_eq(marks.size(), 1)
	assert_eq(marks[0]["coord"], Vector2i(7, 0))
	assert_eq(marks[0]["count"], 1)
	assert_eq(trail.traces[0]["outcome"], StaffMapStrikeTrail.INTERCEPTED)
	assert_eq(trail.traces[0]["stop"], Vector2i(7, 0), "ends at the interceptor")
	assert_eq(trail.traces[1]["outcome"], StaffMapStrikeTrail.HIT)
	trail.on_event(state, 0, _launched(A1, Vector2i(6, 0)))
	trail.on_event(state, 0, _resolved(A1, 2, 0))
	assert_eq(trail.bursts[2]["outcome"], StaffMapStrikeTrail.INTERCEPTED)
	trail.on_event(state, 0, _launched(A1, Vector2i(6, 0)))
	trail.on_event(state, 0, _resolved(A1, 0, 0))
	assert_eq(trail.bursts[4]["outcome"], StaffMapStrikeTrail.MISSED)
	assert_true(trail.traces[4]["offset"].length() >= StaffMapStrikeTrail.MISS_MIN_PX - 0.01)


func test_struck_air_defence_still_counts_as_interceptor() -> void:
	var state := _state(2)
	var ad := state.get_installation(AD)
	ad.integrity = 0  # the strike destroyed it (100 damage dealt)
	var trail := StaffMapStrikeTrail.new()
	trail.on_event(state, 0, _launched(AD, ad.coord))
	var event := _resolved(AD, 1, 1)
	event["damage_dealt"] = 100
	event["target_destroyed"] = true
	trail.on_event(state, 0, event)
	var marks: Array = trail.traces[0]["marks"]
	assert_eq(marks.size(), 1, "the struck site was a contributor before the strike")
	assert_eq(marks[0]["coord"], ad.coord)
	assert_eq(marks[0]["count"], 1)
	assert_true(trail.bursts[1]["destroyed"])
	assert_eq(StaffMapStrikeTrail.interceptors(state, 1, ad.coord).size(), 0, "after: gone")


func test_strikes_are_capped_and_cleared_at_the_viewers_turn_start() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	for i in 10:
		_feed(trail, state, A1, 0)
	assert_eq(trail.strike_count(), StaffMapStrikeTrail.MAX_STRIKES)
	assert_eq(trail.trace_count(), StaffMapStrikeTrail.MAX_STRIKES * 2, "whole salvos are kept")
	assert_eq(trail.burst_count(), trail.trace_count())
	assert_false(trail.on_event(state, 0, {"type": &"operational_turn_started", "player": 1}))
	assert_eq(trail.strike_count(), StaffMapStrikeTrail.MAX_STRIKES, "the enemy's turn keeps them")
	assert_true(trail.on_event(state, 0, {"type": &"operational_turn_started", "player": 0}))
	assert_eq(trail.trace_count(), 0)
	assert_eq(trail.burst_count(), 0)
	assert_false(trail.animating())


func test_animation_runs_until_the_last_effect_ends() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	_feed(trail, state, A1, 0)
	trail.clock = 0.2
	assert_true(trail.animating())
	assert_true(trail.progress(trail.traces[0]) < 1.0)
	trail.clock = 5.0
	assert_false(trail.animating())
	assert_eq(trail.progress(trail.traces[0]), 1.0)


func test_enemy_strikes_leave_traces_and_unseen_ones_none() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	var own := Vector2i(0, 1)
	trail.on_event(state, 0, _launched(&"pl_air", own, 1))
	trail.on_event(state, 0, _resolved(&"pl_air", 0, 2, 1))
	assert_eq(trail.trace_count(), 2)
	assert_eq(trail.traces[0]["player"], 1)
	trail.is_visible = func(_coord: Vector2i, _player: int) -> bool: return false
	trail.on_event(state, 0, _launched(&"pl_air", own, 1))
	trail.on_event(state, 0, _resolved(&"pl_air", 0, 2, 1))
	assert_eq(trail.trace_count(), 2, "fog: nothing drawn")


func _feed_means(
	trail: StaffMapStrikeTrail, state: OperationalState, means: StringName, count: int, hits: int
) -> void:
	var coord := state.get_installation(A1).coord
	trail.on_event(state, 0, _launched(A1, coord))
	var event := _resolved(A1, 0, hits)
	event["means"] = means
	event["count"] = count
	event["misses"] = count - hits
	trail.on_event(state, 0, event)


func test_traces_take_the_weapon_look_duration_and_warhead() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	_feed_means(trail, state, &"iskander_m", 2, 2)
	var look := StrikeWeaponLook.for_means(&"iskander_m")
	var trace := trail.traces[0]
	var distance := Hex.distance(trace["from"], trace["to"])
	assert_eq(trace["look"], look)
	assert_eq(trace["duration"], look.duration(distance))
	assert_eq(
		trail.bursts[0]["start"], trace["start"] + trace["duration"], "impact after the flight"
	)
	assert_eq(trail.bursts[0]["warhead"], &"heavy_blast")
	assert_eq(trail.bursts[0]["burst_scale"], look.burst_scale)
	trail.clock = trace["start"] + trace["duration"] / 2.0
	assert_true(absf(trail.progress(trace) - 0.5) < 0.001, "progress follows the weapon's duration")


func test_unknown_weapon_uses_the_default_look() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	_feed_means(trail, state, &"sure", 2, 2)
	assert_eq(trail.traces[0]["look"].glyph, StrikeWeaponLook.new().glyph)
	assert_eq(trail.bursts[0]["warhead"], &"blast")


func test_missiles_of_a_salvo_are_staggered_by_eighty_milliseconds() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	_feed_means(trail, state, &"kalibr", 4, 4)
	assert_eq(trail.trace_count(), 4)
	for i in 3:
		var gap: float = trail.traces[i + 1]["start"] - trail.traces[i]["start"]
		assert_true(absf(gap - StaffMapStrikeFlight.STAGGER_SECONDS) < 0.0001, "gap %f" % gap)


func test_a_big_salvo_draws_six_missiles_and_counts_the_rest() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	_feed_means(trail, state, &"geran_2", 16, 10)
	assert_eq(trail.trace_count(), StaffMapStrikeFlight.MAX_DRAWN)
	assert_eq(trail.burst_count(), StaffMapStrikeFlight.MAX_DRAWN)
	assert_eq(trail.traces[0]["more"], 10)
	assert_eq(trail.traces[1]["more"], 0)
	assert_eq(trail.strike_count(), 1)


func test_trail_keeps_at_most_eight_strikes() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	for i in 10:
		_feed_means(trail, state, &"kalibr", 2, 2)
	assert_eq(StaffMapStrikeTrail.MAX_STRIKES, 8)
	assert_eq(trail.strike_count(), 8)


func test_toast_text_of_a_strike() -> void:
	var state := _state(2)
	var installation := state.get_installation(A1)
	installation.integrity = 65
	var event := _resolved(A1, 1, 1)
	event["damage_dealt"] = 35
	event["target_destroyed"] = false
	assert_eq(
		StaffMapStrikeText.resolved(state, event),
		"sure ×2 on a1: 1 intercepted, 1 hit – integrity 100 → 65"
	)


func _own_hexes(state: OperationalState, player: int) -> Array[Vector2i]:
	var list: Array[Vector2i] = []
	for hex: Vector2i in state.country_map:
		if CountryRules.relation(state, player, state.country_map[hex]) == &"own":
			list.append(hex)
	return list


func test_launch_origin_is_a_standoff_point_at_ninety_percent_of_the_range() -> void:
	var state := _state(2)
	var target := Vector2i(7, 0)
	var border := StaffMapStrikeTrail.origin(state, 0, target)
	var nearest := Hex.distance(border, target)
	for range_hexes in [nearest, nearest + 2, nearest + 3, 6]:
		var launch := StaffMapStrikeTrail.launch_origin(state, 0, target, range_hexes)
		var distance := Hex.distance(launch, target)
		assert_true(distance <= range_hexes, "in range (%d)" % range_hexes)
		assert_true(distance >= nearest)
		var gap := absf(distance - range_hexes * 0.9)
		for hex in _own_hexes(state, 0):
			var other := Hex.distance(hex, target)
			if other <= range_hexes:
				assert_true(absf(other - range_hexes * 0.9) >= gap - 0.0001, "closest to 90 %")
	assert_eq(
		StaffMapStrikeTrail.launch_origin(state, 0, target, nearest), border, "range = border"
	)


func test_launch_origin_long_range_takes_the_farthest_own_hex_and_short_range_the_border() -> void:
	var state := _state(2)
	var target := Vector2i(7, 0)
	var farthest := 0
	for hex in _own_hexes(state, 0):
		farthest = maxi(farthest, Hex.distance(hex, target))
	var far := StaffMapStrikeTrail.launch_origin(state, 0, target, 500)
	assert_eq(Hex.distance(far, target), farthest, "no own hex that far: the farthest one")
	assert_eq(
		StaffMapStrikeTrail.launch_origin(state, 0, target, 1),
		StaffMapStrikeTrail.origin(state, 0, target),
		"out of range from every own hex: the border hex"
	)
	assert_eq(
		StaffMapStrikeTrail.launch_origin(state, 0, target, 500), far, "deterministic tie-break"
	)


func test_strike_traces_start_at_the_launch_origin() -> void:
	var state := _state(2)
	var trail := StaffMapStrikeTrail.new()
	_feed_means(trail, state, &"sure", 2, 2)
	var coord := state.get_installation(A1).coord
	var range_hexes: int = state.strike_means[&"sure"].range_hexes
	assert_eq(
		trail.traces[0]["from"], StaffMapStrikeTrail.launch_origin(state, 0, coord, range_hexes)
	)
