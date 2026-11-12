extends TestCase
## StaffMapJournalText (TASK-148b): the sentence of every journal kind in the viewer's words, once
## as side 0 and once as side 1; strike outcome words; place line; turn header; filters.

const Contact := preload("res://tests/unit/test_contact.gd")

static var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


func _state() -> OperationalState:
	var state := Contact._state()
	state.player_sides = [&"nato", &"russia"]
	state.start_date = "2027-06-14"
	return state


func _entry(
	kind: StringName, category: StringName, actor: int, args := {}, coord: Variant = null
) -> OperationalJournal.Entry:
	var e := OperationalJournal.Entry.new()
	e.kind = kind
	e.category = category
	e.actor = actor
	e.args = args
	if coord is Vector2i:
		e.coord = coord
		e.has_coord = true
	return e


func _text(e: OperationalJournal.Entry, viewer: int, state: OperationalState = null) -> String:
	var s := state if state != null else _state()
	return StaffMapJournalText.plain(StaffMapJournalText.line(e, viewer, s)["parts"])


## [entry, text for side 0, text for side 1]
func _cases() -> Array:
	var f := {"formation_id": "f"}
	var e := {"formation_id": "e"}
	return [
		[_entry(&"formation_moved", &"move", 0, f), "Our NAME_f moved", "Enemy NAME_f moved"],
		[
			_entry(&"formation_halted", &"move", 1, {"formation_id": "e", "reason": "contact"}),
			"Enemy NAME_e halted on contact",
			"Our NAME_e halted on contact"
		],
		[
			_entry(&"formation_halted", &"move", 0, {"formation_id": "f", "reason": "forbidden"}),
			"Our NAME_f halted at a closed border",
			"Enemy NAME_f halted at a closed border"
		],
		[_entry(&"order_completed", &"move", 0, f), "Our NAME_f arrived", "Enemy NAME_f arrived"],
		[
			_entry(&"order_issued", &"move", 0, {"formation_id": "f", "posture": "advance"}),
			"Our NAME_f ordered to move (attack)",
			"Enemy NAME_f ordered to move (attack)"
		],
		[
			_entry(&"order_cancelled", &"move", 0, f),
			"Our NAME_f: order cancelled",
			"Enemy NAME_f: order cancelled"
		],
		[
			_entry(&"posture_changed", &"move", 0, {"formation_id": "f", "posture": "defend"}),
			"Our NAME_f changed posture to defend",
			"Enemy NAME_f changed posture to defend"
		],
		[
			_entry(&"contact_forbidden", &"move", 0, {"attacker_id": "f", "country": "pl"}),
			"Our NAME_f stopped at the closed border of pl",
			"Enemy NAME_f stopped at the closed border of pl"
		],
		[
			_entry(&"formation_joined", &"move", 0, {"formation_id": "f", "country": "pl"}),
			"Our NAME_f joined (pl)",
			"Enemy NAME_f joined (pl)"
		],
		[
			_entry(&"battle_pending", &"battle", 0, {"attacker_id": "f", "defender_id": "e"}),
			"Contact: Our NAME_f and Enemy NAME_e",
			"Contact: Enemy NAME_f and Our NAME_e"
		],
		[
			_entry(
				&"battle_resolved",
				&"battle",
				-1,
				{"attacker_id": "f", "defender_id": "e", "winner": 0}
			),
			"Our NAME_f won the battle against Enemy NAME_e",
			"Our NAME_e lost the battle against Enemy NAME_f"
		],
		[
			_entry(
				&"battle_resolved",
				&"battle",
				-1,
				{"attacker_id": "f", "defender_id": "e", "winner": -1}
			),
			"The battle between Our NAME_f and Enemy NAME_e ended in a draw",
			"The battle between Our NAME_e and Enemy NAME_f ended in a draw"
		],
		[
			_entry(&"battle_consequences", &"battle", -1, {"losses": [3, 5], "field_holder": 0}),
			"Losses: ours 3, enemy 5. We hold the field",
			"Losses: ours 5, enemy 3. Enemy holds the field"
		],
		[
			_entry(&"formation_retreated", &"battle", -1, {"formation_id": "e", "blocked": false}),
			"Enemy NAME_e retreated one hex",
			"Our NAME_e retreated one hex"
		],
		[
			_entry(&"formation_retreated", &"battle", -1, {"formation_id": "f", "blocked": true}),
			"Our NAME_f could not retreat",
			"Enemy NAME_f could not retreat"
		],
		[
			_entry(&"formation_destroyed", &"battle", -1, {"formation_id": "gone", "player": 0}),
			"Our formation was destroyed",
			"Enemy formation was destroyed"
		],
		[
			_entry(
				&"strike",
				&"strike",
				0,
				{"means": "x", "count": 2, "class_id": "airfield", "hits": 2, "intercepted": 1}
			),
			"We struck the enemy airfield with x ×2: 2 hit, 1 intercepted",
			"Enemy x ×2 on our airfield: 2 hit, 1 intercepted"
		],
		[
			_entry(
				&"strike",
				&"strike",
				1,
				{
					"means": "x",
					"count": 1,
					"class_id": "formation",
					"hits": 1,
					"before": 12,
					"after": 5
				}
			),
			"Enemy x ×1 on our formation: 1 hit, strength 12 → 5",
			"We struck the enemy formation with x ×1: 1 hit, strength 12 → 5"
		],
		[
			_entry(
				&"strike",
				&"strike",
				0,
				{"means": "x", "count": 3, "class_id": "c2", "hits": 0, "target_destroyed": true}
			),
			"We struck the enemy command post with x ×3: no hit – target destroyed",
			"Enemy x ×3 on our command post: no hit – target destroyed"
		],
		[
			_entry(
				&"stance_changed",
				&"politics",
				-1,
				{"country": "lt", "stance": "aligned", "side": 0}
			),
			"lt moved to our side",
			"lt moved to the enemy side"
		],
		[
			_entry(
				&"stance_changed",
				&"politics",
				-1,
				{"country": "lt", "stance": "belligerent", "side": 1}
			),
			"lt entered the war on the enemy side",
			"lt entered the war on our side"
		],
		[
			_entry(
				&"stance_changed",
				&"politics",
				-1,
				{"country": "lt", "stance": "neutral", "side": -1}
			),
			"lt became neutral",
			"lt became neutral"
		],
		[
			_entry(&"level_changed", &"politics", -1, {"level": 1, "previous": 2, "cause": "calm"}),
			"Calm: level 2 → 1",
			"Calm: level 2 → 1"
		],
		[
			_entry(&"decision", &"politics", -1, {"decision": "escalate", "country": ""}),
			"Decision: Escalate",
			"Decision: Escalate"
		],
		[
			_entry(&"decision", &"politics", -1, {"decision": "invoke_alliance", "country": "lt"}),
			"Decision: Invoke alliance · lt",
			"Decision: Invoke alliance · lt"
		],
		[
			_entry(&"sanctuary_breach", &"politics", -1, {"country": "ru"}),
			"Sanctuary breached: ru",
			"Sanctuary breached: ru"
		],
		[
			_entry(&"casus_belli", &"politics", -1, {"country": "ru"}),
			"Casus belli over ru",
			"Casus belli over ru"
		],
		[
			_entry(&"operation_ended", &"politics", -1, {"winner": 0}),
			"The operation ended: we won",
			"The operation ended: we lost"
		],
	]


func test_every_kind_reads_in_the_words_of_the_viewing_side() -> void:
	var state := _state()
	for c: Array in _cases():
		var entry: OperationalJournal.Entry = c[0]
		assert_eq(_text(entry, 0, state), c[1], "%s as side 0" % entry.kind)
		assert_eq(_text(entry, 1, state), c[2], "%s as side 1" % entry.kind)


func test_the_cases_cover_every_journal_kind_but_the_order_interruption() -> void:
	var seen := {}
	for c: Array in _cases():
		seen[(c[0] as OperationalJournal.Entry).kind] = true
	for kind in OperationalJournal.KINDS:
		if kind in [&"order_interrupted", &"level_changed", &"formation_halted"]:
			continue
		assert_true(seen.has(kind), "a case for %s" % kind)


func test_an_order_interruption_names_the_reason() -> void:
	var e := _entry(&"order_interrupted", &"move", 0, {"formation_id": "f", "reason": "no_route"})
	var why := StaffMapTurnReport.kind_text(StaffMapTurnMarks.INTERRUPTED, &"no_route")
	assert_eq(_text(e, 0), "Our NAME_f: %s" % (why.substr(0, 1).to_lower() + why.substr(1)))
	assert_true(_text(e, 1).begins_with("Enemy NAME_f: "))


func test_no_sentence_names_a_bloc_or_who_decided() -> void:
	var state := _state()
	for c: Array in _cases():
		for viewer in 2:
			var text := _text(c[0], viewer, state)
			for word in ["NATO", "Russia", "nato", "russia"]:
				assert_false(
					text.contains(word), "%s: %s" % [(c[0] as OperationalJournal.Entry).kind, text]
				)
	var decision := _entry(&"decision", &"politics", -1, {"decision": "escalate"})
	assert_eq(_text(decision, 0, state), _text(decision, 1, state), "political lines are bare")


func test_strike_outcome_words_carry_the_strike_colours() -> void:
	var entry := _entry(
		&"strike",
		&"strike",
		0,
		{
			"means": "x",
			"count": 2,
			"class_id": "airfield",
			"hits": 2,
			"intercepted": 1,
			"before": 8,
			"after": 3
		}
	)
	var parts: Array = StaffMapJournalText.line(entry, 0, _state())["parts"]
	var styles := {}
	for part: Array in parts:
		styles[part[0]] = part[1]
	assert_eq(styles["2 hit"], StaffMapJournalText.HIT)
	assert_eq(styles["1 intercepted"], StaffMapJournalText.ICPT)
	assert_eq(styles["x ×2"], StaffMapJournalText.BOLD)
	assert_eq(styles["3"], StaffMapJournalText.BAD, "the new integrity is the loss")
	var palette := StaffMapPalette.new()
	var bb := (
		StaffMapJournalText
		. bbcode(
			parts,
			{
				StaffMapJournalText.HIT: palette.outcome_hit,
				StaffMapJournalText.ICPT: palette.outcome_intercepted,
				StaffMapJournalText.BAD: palette.ui_alert,
			}
		)
	)
	assert_true(bb.contains("[color=#e8b04a]2 hit[/color]"), bb)
	assert_true(bb.contains("[color=#6f95ab]1 intercepted[/color]"), bb)
	assert_true(bb.contains("[color=#e07c5e]3[/color]"), bb)


func test_side_shape_and_tag() -> void:
	var state := _state()
	var own := _entry(&"formation_moved", &"move", 0, {"formation_id": "f"})
	assert_eq(StaffMapJournalText.line(own, 0, state)["side"], StaffMapJournalText.OWN)
	assert_eq(StaffMapJournalText.line(own, 1, state)["side"], StaffMapJournalText.ENEMY)
	assert_eq(StaffMapJournalText.line(own, 0, state)["tag"], "MOV")
	var politics := _entry(&"sanctuary_breach", &"politics", -1, {"country": "ru"})
	assert_eq(StaffMapJournalText.line(politics, 0, state)["side"], StaffMapJournalText.NEUTRAL)
	assert_eq(StaffMapJournalText.line(politics, 0, state)["tag"], "POL")
	var strike := _entry(&"strike", &"strike", 1, {"means": "x"})
	assert_eq(StaffMapJournalText.line(strike, 0, state)["tag"], "STR")
	var battle := _entry(&"formation_retreated", &"battle", -1, {"formation_id": "e"})
	assert_eq(StaffMapJournalText.line(battle, 0, state)["side"], StaffMapJournalText.ENEMY)
	assert_eq(StaffMapJournalText.line(battle, 1, state)["side"], StaffMapJournalText.OWN)
	assert_eq(StaffMapJournalText.line(battle, 0, state)["tag"], "BTL")


func test_place_line_uses_the_namer_and_falls_back_to_the_hex() -> void:
	var state := _state()
	var e := _entry(&"order_completed", &"move", 0, {"formation_id": "f"}, Vector2i(1, 0))
	var namer := func(_c: Vector2i) -> String: return "Sejny, 3 km north"
	assert_eq(StaffMapJournalText.line(e, 0, state, namer)["place"], "Sejny, 3 km north")
	assert_eq(
		StaffMapJournalText.line(e, 0, state)["place"],
		StaffMapTurnReport.place_text(Vector2i(1, 0))
	)
	var none := _entry(&"decision", &"politics", -1, {"decision": "escalate"})
	assert_eq(StaffMapJournalText.line(none, 0, state)["place"], "")


func test_turn_header_has_the_date_and_the_day_night_range() -> void:
	var state := _state()
	var day := StaffMapJournalText.turn_header(1, state)
	assert_eq(day["title"], "TURN 1")
	assert_eq(day["date"], "14 JUN")
	assert_eq(day["range"], "DAY 06–18")
	assert_eq(day["text"], "14 JUN · DAY 06–18")
	var night := StaffMapJournalText.turn_header(2, state)
	assert_eq(night["range"], "NIGHT 18–06")
	assert_eq(StaffMapJournalText.turn_header(3, state)["date"], "15 JUN")
	state.start_date = ""
	assert_eq(
		StaffMapJournalText.turn_header(1, state)["text"], "DAY 06–18", "no date, only the range"
	)


func test_filters_match_the_category() -> void:
	var strike := _entry(&"strike", &"strike", 0)
	assert_true(StaffMapJournalText.matches(strike, &""))
	assert_true(StaffMapJournalText.matches(strike, &"strike"))
	assert_false(StaffMapJournalText.matches(strike, &"battle"))
	assert_eq(StaffMapJournalText.FILTERS.size(), 5)
