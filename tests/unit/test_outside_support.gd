# gdlint: disable=max-public-methods
extends TestCase
## Outside support (TASK-121): supporters and packages as data, validation, the request decision,
## the status of a supporter, delivery at the start of the recipient's turn, codec and replay.

const Politics := preload("res://tests/unit/test_country_rules.gd")
const Borders := preload("res://tests/unit/test_borders_movement.gd")
const Strikes := preload("res://tests/unit/test_strikes.gd")
const BAD_PACKAGES: Array[String] = [
	"wrong side",
	"min above max",
	"max too high",
	"negative min",
	"negative cost",
	"negative delay",
	"max_caused",
	"duplicate id",
	"unknown response",
	"same side response",
	"placement player",
	"faction",
	"off map",
	"repeated id",
	"no effect",
]

var _events: Array[Dictionary] = []


static func _placement(
	id: StringName, player: int, type: StringName, at: Vector2i
) -> FormationPlacement:
	var p := FormationPlacement.new()
	p.id = id
	p.display_name = String(id)
	p.player = player
	p.definition = load("res://data/formations/%s.tres" % type) as FormationDefinition
	p.coord = at
	return p


static func _package(
	id: StringName,
	supporter: StringName,
	levels: Vector2i,
	cost: int,
	delay: int,
	formations: Array[FormationPlacement]
) -> SupportPackage:
	var p := SupportPackage.new()
	p.id = id
	p.display_name = String(id)
	p.supporter = SupporterDefinition.find(supporter)
	p.side = p.supporter.side
	p.min_level = levels.x
	p.max_level = levels.y
	p.escalation_cost = cost
	p.delay_turns = delay
	p.formations = formations
	return p


## Test packages A (side 0), N and C (side 1) of the task text.
static func _packages() -> Array[SupportPackage]:
	var a := _package(
		&"a",
		&"nato_allies",
		Vector2i(1, 3),
		1,
		2,
		[_placement(&"u1", 0, &"pl_tank_battalion", Vector2i(1, 0))] as Array[FormationPlacement]
	)
	a.response_to = [&"n"] as Array[StringName]
	var n := _package(
		&"n",
		&"north_korea",
		Vector2i(2, 3),
		1,
		2,
		(
			[
				_placement(&"n1", 1, &"ru_motor_rifle_battalion", Vector2i(7, 3)),
				_placement(&"n2", 1, &"ru_mlrs_battalion", Vector2i(6, 3)),
			]
			as Array[FormationPlacement]
		)
	)
	n.entry_casus_belli = true
	n.response_to = [&"a"] as Array[StringName]
	var c := _package(
		&"c",
		&"china",
		Vector2i(1, 2),
		0,
		2,
		[_placement(&"c1", 1, &"ru_tank_battalion", Vector2i(5, 2))] as Array[FormationPlacement]
	)
	c.max_caused = 0
	c.withdraw_if_unmet = true
	return [a, n, c] as Array[SupportPackage]


static func _definition(packages: Array[SupportPackage]) -> OperationDefinition:
	var def := Politics._definition()
	def.support_packages = packages
	return def


static func _grid() -> HexGrid:
	var grid := HexGrid.new()
	for q in range(0, 8):
		for r in range(0, 4):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
	return grid


static func _map() -> Dictionary:
	var map := {}
	for q in range(0, 8):
		for r in range(0, 4):
			var id := &"poland"
			if q >= 4 and r < 2:
				id = &"russia"
			elif q < 4 and r >= 2:
				id = &"lithuania"
			elif q >= 4:
				id = &"belarus"
			map[Vector2i(q, r)] = id
	return map


## The "quad" grid of TASK-116 with the test packages; F on (0, 0), R on (7, 3), level 1.
static func _setup(packages: Array[SupportPackage] = _packages()) -> OperationalState:
	var s := Operation.from_definition(_definition(packages), 1, _grid(), _map())
	if s == null:
		return null
	s.first_player = 0
	s.current_player = 0
	Borders._add(s, &"f", 0, Vector2i(0, 0))
	Borders._add(s, &"r", 1, Vector2i(7, 3))
	return s


static func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> Variant: return e["type"])


func _take(s: OperationalState, cmd: OperationalCommand) -> Array[Dictionary]:
	assert_eq(cmd.validate(s), "", "accepted")
	return cmd.apply(s)


func _end(s: OperationalState) -> Array[Dictionary]:
	s.pending_battles.clear()
	var cmd := EndOperationalTurnCommand.new()
	assert_eq(cmd.validate(s), "")
	return cmd.apply(s)


## Ends turns until it is `player`'s turn `turn`; returns the events of the last end only.
func _until(s: OperationalState, turn: int, player: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	while s.turn != turn or s.current_player != player:
		events = _end(s)
	return events


func _request(s: OperationalState, id: StringName) -> String:
	return RequestSupportCommand.new(id).validate(s)


# --- data ---


func test_supporter_data() -> void:
	var expected := {
		&"nato_allies": ["NATO allies", 0],
		&"north_korea": ["North Korea", 1],
		&"china": ["China", 1],
		&"iran": ["Iran", 1],
	}
	for id: StringName in expected:
		var supporter := SupporterDefinition.find(id)
		assert_true(supporter != null, String(id))
		assert_eq(supporter.id, id)
		assert_eq(supporter.display_name, expected[id][0])
		assert_eq(supporter.side, expected[id][1])
	assert_true(SupporterDefinition.find(&"mars") == null)


func test_shipped_packages() -> void:
	var s := Operation.build(&"suwalki_gap", 1)
	var allied := s.get_support(&"allied_reinforcements").definition
	var nk := s.get_support(&"nk_troops").definition
	assert_eq(allied.supporter.id, &"nato_allies")
	assert_eq(nk.supporter.id, &"north_korea")
	assert_eq([allied.side, nk.side], [0, 1])
	assert_eq([allied.min_level, allied.max_level, nk.min_level, nk.max_level], [1, 3, 2, 3])
	assert_eq([allied.escalation_cost, nk.escalation_cost], [1, 1])
	assert_eq([allied.delay_turns, nk.delay_turns], [4, 4])
	assert_eq(allied.response_to, [&"nk_troops"] as Array[StringName])
	assert_eq(nk.response_to, [&"allied_reinforcements"] as Array[StringName])
	assert_true(nk.entry_casus_belli)
	assert_false(allied.entry_casus_belli)
	assert_eq(
		allied.formations.map(func(p: FormationPlacement) -> StringName: return p.id),
		[&"us_armor_1", &"nato_mech_1"]
	)
	assert_eq(
		nk.formations.map(func(p: FormationPlacement) -> StringName: return p.id),
		[&"kp_inf_1", &"kp_art_1"]
	)
	var totals: Array[int] = [0, 0]
	for placement in allied.formations:
		assert_eq(s.country_at(placement.coord), &"poland")
		assert_true(s.grid.move_cost(placement.coord) != Terrain.IMPASSABLE)
		totals[0] += Formation.from_placement(placement, &"defend").max_strength()
	for placement in nk.formations:
		assert_eq(s.country_at(placement.coord), &"belarus")
		assert_true(s.grid.move_cost(placement.coord) != Terrain.IMPASSABLE)
		totals[1] += Formation.from_placement(placement, &"defend").max_strength()
	assert_eq(totals, [80, 56] as Array[int], "strength of the two packages")
	assert_true(allied.formations[0].parent != "")


static func _spoil(label: String, p: Array[SupportPackage]) -> void:
	match label:
		"wrong side":
			p[0].side = 1
		"min above max":
			p[0].max_level = 0
		"max too high":
			p[0].max_level = 6
		"negative min":
			p[0].min_level = -1
		"negative cost":
			p[0].escalation_cost = -1
		"negative delay":
			p[0].delay_turns = -1
		"max_caused":
			p[0].max_caused = -2
		"duplicate id":
			p[1].id = &"a"
		"unknown response":
			p[0].response_to = [&"x"] as Array[StringName]
		"same side response":
			p[2].response_to = [&"n"] as Array[StringName]
		"placement player":
			p[0].formations[0].player = 1
		"faction":
			p[2].formations[0].definition = p[0].formations[0].definition
		"off map":
			p[0].formations[0].coord = Vector2i(9, 9)
		"repeated id":
			p[1].formations[0].id = &"u1"
		"no effect":
			p[0].formations = [] as Array[FormationPlacement]


func test_from_definition_rejects_bad_packages() -> void:
	for label in BAD_PACKAGES:
		var packages := _packages()
		_spoil(label, packages)
		assert_true(_setup(packages) == null, label)
	assert_true(_setup() != null)
	var clash := _definition(_packages())
	clash.formations.append(_placement(&"u1", 0, &"pl_tank_battalion", Vector2i(0, 1)))
	assert_true(Operation.from_definition(clash, 1, _grid(), _map()) == null, "start id repeats")


func test_snapshot_lists_support_sorted() -> void:
	var s := _setup()
	var entries: Array = s.snapshot()["support"]
	assert_eq(entries.map(func(e: Dictionary) -> Variant: return e["id"]), [&"a", &"c", &"n"])
	assert_eq(entries[0]["requested_turn"], -1)
	assert_eq(entries[0]["waiting"], [])
	_take(s, RequestSupportCommand.new(&"a"))
	assert_eq(s.snapshot()["support"][0]["waiting"], [&"u1"])
	assert_eq(s.snapshot()["support"][0]["requested_turn"], 1)


# --- request ---


func test_request_rejections_in_order() -> void:
	var s := _setup()
	assert_eq(_request(s, &"n"), "not_your_package")
	assert_eq(_request(s, &"x"), "unknown_package")
	assert_eq(_request(s, &"a"), "")
	s.pending_battles.append(BattleSetup.new())
	assert_eq(_request(s, &"x"), "battle_pending")
	s.pending_battles.clear()
	s.decisions_left = 0
	assert_eq(_request(s, &"a"), "no_decisions_left")


func test_request_applies() -> void:
	var s := _setup()
	var events := _take(s, RequestSupportCommand.new(&"a"))
	assert_eq(
		_types(events), [&"political_decision_taken", &"support_requested", &"escalation_changed"]
	)
	assert_eq(events[0]["decision"], &"request_support")
	assert_eq(events[0]["country"], &"")
	assert_eq(events[1]["package"], &"a")
	assert_eq(events[1]["supporter"], &"nato_allies")
	assert_eq(events[1]["player"], 0)
	assert_eq(events[1]["delivery_turn"], 3)
	assert_eq(events[1]["responses"], [&"n"])
	assert_eq(events[2]["level"], 2)
	assert_eq(events[2]["previous"], 1)
	assert_eq(events[2]["cause"], &"support_request")
	assert_eq(events[2]["by"], 0)
	assert_eq(s.escalation_level, 2)
	assert_eq(s.escalation_caused, [1, 0] as Array[int])
	assert_eq(s.decisions_left, 0)
	assert_eq(_request(s, &"a"), "no_decisions_left")
	s.decisions_left = 1
	assert_eq(_request(s, &"a"), "already_requested")
	assert_eq(SupportRules.status(s, &"nato_allies"), {"status": &"considering", "side": 0})


func test_response_is_free_and_ignores_level() -> void:
	var s := _setup()
	_take(s, RequestSupportCommand.new(&"a"))
	_end(s)
	assert_eq(s.current_player, 1)
	assert_true(SupportRules.is_response(s, &"n"))
	var events := _take(s, RequestSupportCommand.new(&"n"))
	assert_eq(_types(events), [&"political_decision_taken", &"support_requested"])
	assert_eq(events[1]["responses"], [])
	assert_eq(s.escalation_level, 2)
	assert_eq(s.escalation_caused, [1, 0] as Array[int])


func test_request_conditions_without_response() -> void:
	var s := _setup()
	s.current_player = 1
	assert_eq(_request(s, &"n"), "level_too_low")
	EscalationRules.raise(s, 0, &"test")
	assert_eq(_request(s, &"n"), "")
	_take(s, RequestSupportCommand.new(&"n"))
	assert_eq(s.escalation_level, 3)
	s = _setup()
	EscalationRules.raise(s, 0, &"test", 3)
	s.current_player = 1
	s.escalation_level = 3
	assert_eq(_request(s, &"c"), "level_too_high")


func test_threshold_and_standing_down() -> void:
	# The ladder tops out at 6 (the nuclear attack): a paid request at the cap 5 is rejected.
	var packages := _packages()
	packages[0].max_level = 5
	packages[1].max_level = 5
	var s := _setup(packages)
	EscalationRules.raise(s, 1, &"test", 4)
	assert_eq(s.escalation_level, 5)
	assert_eq(_request(s, &"a"), "threshold")
	s.current_player = 1
	assert_eq(_request(s, &"n"), "threshold")
	# A response is free: accepted at the cap, the level does not change.
	s.get_support(&"n").requested_turn = 1
	s.current_player = 0
	assert_eq(_request(s, &"a"), "")
	_take(s, RequestSupportCommand.new(&"a"))
	assert_eq(s.escalation_level, 5)
	# Standing down: a paid request is rejected, a response is not.
	s = _setup()
	s.stand_down_until[0] = 5
	assert_eq(_request(s, &"a"), "standing_down")
	s.get_support(&"n").requested_turn = 1
	assert_eq(_request(s, &"a"), "")


func test_escalation_record() -> void:
	var s := _setup()
	s.current_player = 1
	s.escalation_caused[1] = 1
	assert_eq(_request(s, &"c"), "escalation_record")
	s.escalation_deescalated[1] = 1
	assert_eq(_request(s, &"c"), "")


func test_side_symmetry() -> void:
	# The same packages with the sides swapped: B (side 1) answers A (side 0) and vice versa.
	var s := _setup()
	s.current_player = 1
	EscalationRules.raise(s, 1, &"test")
	s.current_player = 1
	var events := _take(s, RequestSupportCommand.new(&"n"))
	assert_eq(events[1]["delivery_turn"], 3)
	assert_eq(events[1]["responses"], [&"a"])
	assert_eq(s.escalation_caused, [0, 2] as Array[int])
	s.current_player = 0
	s.decisions_left = 1
	events = _take(s, RequestSupportCommand.new(&"a"))
	assert_eq(_types(events), [&"political_decision_taken", &"support_requested"])


# --- delivery ---


func test_delivery_in_round_three() -> void:
	var s := _setup()
	_take(s, RequestSupportCommand.new(&"a"))
	_end(s)
	_take(s, RequestSupportCommand.new(&"n"))
	var rng_before := s.rng.state
	var events := _end(s)
	assert_eq(s.turn, 2)
	assert_false(_types(events).has(&"formation_joined"))
	_end(s)
	events = _end(s)
	assert_eq(
		_types(events).slice(-3),
		[&"operational_turn_started", &"formation_joined", &"support_delivered"]
	)
	assert_eq(s.turn, 3)
	var u1 := s.get_formation(&"u1")
	assert_eq(u1.coord, Vector2i(1, 0))
	assert_eq(u1.owner_id, 0)
	assert_eq(SupportRules.status(s, &"nato_allies"), {"status": &"supporting", "side": 0})
	var delivered := events[-1]
	assert_eq(delivered["package"], &"a")
	assert_eq(delivered["formations"], [&"u1"])
	assert_true(s.get_support(&"a").delivered)
	# Player 1: N1's entry is held by R, N1 goes on the nearest free belarus hex.
	events = _end(s)
	assert_eq(
		_types(events).slice(-5),
		[
			&"operational_turn_started",
			&"formation_joined",
			&"formation_joined",
			&"casus_belli_gained",
			&"support_delivered"
		]
	)
	assert_eq(s.get_formation(&"n1").coord, Vector2i(7, 2))
	assert_eq(s.get_formation(&"n2").coord, Vector2i(6, 3))
	var cb := events[-2]
	assert_eq([cb["country"], cb["player"]], [&"belarus", 0])
	assert_true(s.get_country(&"belarus").casus_belli[0])
	assert_eq(events[-3]["source"], &"n")
	assert_eq(s.rng.state, rng_before)
	# A delivered formation has full strength, the start posture and can get orders at once.
	var n2 := s.get_formation(&"n2")
	assert_eq(n2.posture, s.initial_posture)
	assert_true(n2.order == null)
	assert_eq(IssueOrderCommand.new(&"n2", Vector2i(5, 3), &"march").validate(s), "")


func _both_requested() -> OperationalState:
	var s := _setup()
	_take(s, RequestSupportCommand.new(&"a"))
	_end(s)
	_take(s, RequestSupportCommand.new(&"n"))
	return s


func test_no_casus_belli_when_belarus_belligerent() -> void:
	var s := _both_requested()
	CountryRules.set_stance(s, &"belarus", CountryState.BELLIGERENT, 1, &"test", -1)
	var events := _until(s, 3, 1)
	assert_false(_types(events).has(&"casus_belli_gained"))
	assert_true(_types(events).has(&"support_delivered"))
	assert_false(s.get_country(&"belarus").casus_belli[0])


func test_closed_entry_waits_and_retries() -> void:
	var s := _both_requested()
	CountryRules.set_stance(s, &"belarus", CountryState.NEUTRAL, -1, &"test", -1)
	var events := _until(s, 3, 1)
	var delayed := events.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"support_delayed"
	)
	assert_eq(delayed.size(), 1)
	assert_eq(delayed[0]["reason"], &"no_open_entry")
	assert_eq(delayed[0]["waiting"], [&"n1", &"n2"])
	assert_true(s.get_formation(&"n1") == null)
	assert_eq(SupportRules.status(s, &"north_korea")["status"], &"considering")
	events = _until(s, 4, 1)
	assert_true(_types(events).has(&"support_delayed"))
	CountryRules.set_stance(s, &"belarus", CountryState.ALIGNED, 1, &"test", -1)
	events = _until(s, 5, 1)
	assert_eq(
		_types(events).slice(-5),
		[
			&"operational_turn_started",
			&"formation_joined",
			&"formation_joined",
			&"casus_belli_gained",
			&"support_delivered"
		]
	)
	assert_eq(s.get_support(&"n").waiting.size(), 0)
	assert_eq(SupportRules.status(s, &"north_korea")["status"], &"supporting")


func test_withdrawal_by_escalation_record() -> void:
	var s := _setup()
	s.current_player = 1
	_take(s, RequestSupportCommand.new(&"c"))
	assert_eq(s.escalation_level, 1)
	EscalationRules.raise(s, 1, &"test")
	var events := _until(s, 3, 1)
	var withdrawn := events.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"support_withdrawn"
	)
	assert_eq(withdrawn.size(), 1)
	assert_eq(withdrawn[0]["reason"], &"escalation_record")
	assert_true(s.get_formation(&"c1") == null)
	assert_true(s.get_support(&"c").withdrawn)
	assert_eq(SupportRules.status(s, &"china"), {"status": &"uninvolved", "side": 1})
	assert_eq(_request(s, &"c"), "already_requested")


func test_delivery_when_other_side_raised() -> void:
	var s := _setup()
	s.current_player = 1
	_take(s, RequestSupportCommand.new(&"c"))
	EscalationRules.raise(s, 0, &"test")
	_until(s, 3, 1)
	assert_eq(s.get_formation(&"c1").coord, Vector2i(5, 2))
	assert_eq(SupportRules.status(s, &"china")["status"], &"supporting")


func test_withdrawal_level_too_high() -> void:
	var s := _setup()
	s.current_player = 1
	_take(s, RequestSupportCommand.new(&"c"))
	EscalationRules.raise(s, 0, &"test", 2)
	var events := _until(s, 3, 1)
	var withdrawn := events.filter(
		func(e: Dictionary) -> bool: return e["type"] == &"support_withdrawn"
	)
	assert_eq(withdrawn[0]["reason"], &"level_too_high")


func test_status_before_any_request() -> void:
	var s := _setup()
	assert_eq(SupportRules.status(s, &"nato_allies"), {"status": &"considering", "side": 0})
	# North Korea needs level 2, so it is uninvolved at level 1.
	assert_eq(SupportRules.status(s, &"north_korea"), {"status": &"uninvolved", "side": 1})
	EscalationRules.raise(s, 0, &"test")
	assert_eq(SupportRules.status(s, &"north_korea")["status"], &"considering")
	assert_eq(SupportRules.status(s, &"nobody"), {"status": &"uninvolved", "side": -1})


# --- codec and replay ---


func test_codec() -> void:
	var cmd := RequestSupportCommand.new(&"a")
	var d := JSON.parse_string(JSON.stringify(cmd.to_dict())) as Dictionary
	var back := OperationalCommandCodec.from_dict(d)
	assert_true(back is RequestSupportCommand)
	assert_eq(back.to_dict(), cmd.to_dict())
	assert_true(OperationalCommandCodec.from_dict({"type": "request_support"}) == null)
	assert_true(
		OperationalCommandCodec.from_dict({"type": "request_support", "package": 3}) == null
	)
	var unknown := OperationalCommandCodec.from_dict({"type": "request_support", "package": "zz"})
	assert_eq(unknown.validate(_setup()), "unknown_package")


func _scripted(state: OperationalState, dicts: Array[Dictionary]) -> Array[Dictionary]:
	_events.clear()
	var sim := OperationalSimulation.new(state)
	var all: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: all.append(e))
	for d in dicts:
		var cmd := OperationalCommandCodec.from_dict(
			JSON.parse_string(JSON.stringify(d)) as Dictionary
		)
		var reason := cmd.validate(state)
		if reason == "":
			assert_true(sim.execute(cmd))
		else:
			assert_false(sim.execute(cmd))
			all.append({"type": &"rejected", "reason": reason})
	return all


func test_replay_on_real_operation() -> void:
	var end := EndOperationalTurnCommand.new().to_dict()
	# Russia (player 1) moves first: its free answer comes after NATO's request.
	var dicts: Array[Dictionary] = [
		RequestSupportCommand.new(&"nk_troops").to_dict(),  # level 1: rejected
		end,
		RequestSupportCommand.new(&"allied_reinforcements").to_dict(),
		end,
		RequestSupportCommand.new(&"nk_troops").to_dict(),  # a free response
	]
	for _i in 12:
		dicts.append(end)
	var first := Operation.build(&"suwalki_gap", 7)
	var rng_before := first.rng.state
	var events_a := _scripted(first, dicts)
	var kinds := _types(events_a)
	assert_eq(kinds.count(&"support_delivered"), 2)
	assert_eq(kinds.count(&"support_requested"), 2)
	assert_eq(
		events_a.filter(func(e: Dictionary) -> bool: return e["type"] == &"rejected").size(), 1
	)
	assert_true(first.get_formation(&"us_armor_1") != null)
	assert_true(first.get_formation(&"kp_inf_1") != null)
	assert_eq(first.rng.state, rng_before)
	var second := Operation.build(&"suwalki_gap", 7)
	var events_b := _scripted(second, dicts)
	assert_eq(first.snapshot(), second.snapshot())
	assert_eq(str(events_a), str(events_b))


# --- strike means (TASK-122) ---


static func _grant(means: StringName, count: int) -> MeansGrant:
	var g := MeansGrant.new()
	g.means = means
	g.count = count
	return g


## Packages D (+3 kh101, delay 1), E (+2 geran_2, max_caused 0, withdraw_if_unmet, delay 2) and
## F (one formation + 2 kh101) of side 1; player 1 starts with 4 kh101.
static func _means_setup() -> OperationalState:
	var none: Array[FormationPlacement] = []
	var d := _package(&"d", &"china", Vector2i(1, 3), 0, 1, none)
	d.strike_means = [_grant(&"kh101", 3)] as Array[MeansGrant]
	var e := _package(&"e", &"iran", Vector2i(1, 2), 0, 2, none)
	e.max_caused = 0
	e.withdraw_if_unmet = true
	e.strike_means = [_grant(&"geran_2", 2)] as Array[MeansGrant]
	var f := _package(
		&"f",
		&"china",
		Vector2i(1, 3),
		0,
		1,
		[_placement(&"f1", 1, &"ru_tank_battalion", Vector2i(7, 0))] as Array[FormationPlacement]
	)
	f.strike_means = [_grant(&"kh101", 2)] as Array[MeansGrant]
	var packages: Array[SupportPackage] = [d, e, f]
	var def := _definition(packages)
	def.strike_stock = [{}, {&"kh101": 4}] as Array[Dictionary]
	var s := Operation.from_definition(def, 1, _grid(), _map())
	s.first_player = 0
	s.current_player = 0
	Borders._add(s, &"f", 0, Vector2i(0, 0))
	Borders._add(s, &"r", 1, Vector2i(7, 3))
	return s


func test_means_only_package_is_valid_and_bad_grants_rejected() -> void:
	assert_true(_means_setup() != null)
	for label in ["unknown", "zero", "twice", "other side", "empty"]:
		var def := _definition(_packages())
		var none: Array[FormationPlacement] = []
		var p := _package(&"m", &"china", Vector2i(1, 3), 0, 1, none)
		match label:
			"unknown":
				p.strike_means = [_grant(&"nuke", 1)] as Array[MeansGrant]
			"zero":
				p.strike_means = [_grant(&"kh101", 0)] as Array[MeansGrant]
			"twice":
				p.strike_means = [_grant(&"kh101", 1), _grant(&"kh101", 2)] as Array[MeansGrant]
			"other side":
				p.strike_means = [_grant(&"storm_shadow", 1)] as Array[MeansGrant]
			"empty":
				pass
		def.support_packages = [p] as Array[SupportPackage]
		assert_true(Operation.from_definition(def, 1, _grid(), _map()) == null, label)


func test_means_delivery_adds_stock_at_turn_start() -> void:
	var s := _means_setup()
	_end(s)
	_take(s, RequestSupportCommand.new(&"d"))
	var rng_before := s.rng.state
	var events := _end(s)
	assert_false(_types(events).has(&"support_delivered"))
	events = _end(s)
	assert_eq(
		_types(events).slice(-3),
		[&"operational_turn_started"] + [&"strike_stock_changed", &"support_delivered"]
	)
	assert_eq(s.turn, 2)
	assert_eq(StrikeRules.stock(s, 1, &"kh101"), 7)
	var changed := events[-2]
	assert_eq([changed["total"], changed["count"], changed["source"]], [7, 3, &"d"])
	assert_eq(events[-1]["means"], {&"kh101": 3})
	assert_eq(events[-1]["formations"], [])
	assert_true(s.get_support(&"d").delivered)
	assert_eq(s.rng.state, rng_before)


func test_means_package_withdrawn_when_conditions_lapse() -> void:
	var s := _means_setup()
	_end(s)
	_take(s, RequestSupportCommand.new(&"e"))
	s.escalation_level = 3
	var events := _until(s, 3, 1)
	assert_eq(StrikeRules.stock(s, 1, &"geran_2"), 0)
	assert_true(s.get_support(&"e").withdrawn)
	assert_false(_types(events).has(&"strike_stock_changed"))


func test_formation_and_means_package_orders_events() -> void:
	var s := _means_setup()
	_end(s)
	_take(s, RequestSupportCommand.new(&"f"))
	_end(s)
	var events := _end(s)
	assert_eq(
		_types(events).slice(-4),
		[
			&"operational_turn_started",
			&"formation_joined",
			&"strike_stock_changed",
			&"support_delivered"
		]
	)
	assert_eq(events[-1]["formations"], [&"f1"])
	assert_eq(events[-1]["means"], {&"kh101": 2})
	assert_eq(StrikeRules.stock(s, 1, &"kh101"), 6)


func test_shipped_strike_means_packages() -> void:
	var s := Operation.build(&"suwalki_gap", 1)
	var china := s.get_support(&"china_components").definition
	var iran := s.get_support(&"iran_drones").definition
	var allied := s.get_support(&"allied_strike_means").definition
	assert_eq(
		[china.supporter.id, china.side, china.min_level, china.max_level], [&"china", 1, 1, 2]
	)
	assert_eq([china.max_caused, china.escalation_cost, china.delay_turns], [1, 0, 6])
	assert_true(china.withdraw_if_unmet)
	assert_eq([china.strike_means[0].means, china.strike_means[0].count], [&"kh101", 4])
	assert_eq(
		[iran.supporter.id, iran.min_level, iran.max_level, iran.delay_turns], [&"iran", 1, 3, 2]
	)
	assert_eq([iran.strike_means[0].means, iran.strike_means[0].count], [&"geran_2", 8])
	assert_eq([allied.side, allied.min_level, allied.max_level, allied.delay_turns], [0, 2, 3, 2])
	assert_eq(allied.response_to, [&"china_components", &"iran_drones"] as Array[StringName])
	assert_eq(
		allied.strike_means.map(func(g: MeansGrant) -> Array: return [g.means, g.count]),
		[[&"storm_shadow", 4], [&"tomahawk", 2]]
	)
	assert_true(china.formations.is_empty())


## A TASK-097 strike state (player 0 strikes "a1") with a delivered-on-demand means-only package
## granting `granted` of `sure` to player 0 on top of `start`.
func _granted_strike_state(
	start: int, granted: int, seed_value := 1, means := &"sure"
) -> OperationalState:
	var s := Strikes._state(null, seed_value)
	s.escalation_level = 2
	s.strike_stock[0][means] = start
	if granted > 0:
		var none: Array[FormationPlacement] = []
		var p := _package(&"g", &"nato_allies", Vector2i(0, 3), 0, 0, none)
		p.strike_means = [_grant(means, granted)] as Array[MeansGrant]
		var support := SupportState.from_package(p)
		support.requested_turn = s.turn
		s.support.append(support)
		SupportRules.deliver(s)
		assert_true(support.delivered)
	return s


func test_granted_stock_is_spent_like_any_stock() -> void:
	var s := _granted_strike_state(4, 3, 1, &"never")
	assert_eq(StrikeRules.stock(s, 0, &"never"), 7)
	var sim := OperationalSimulation.new(s)
	for i in 7:
		s.strikes_left = 5
		assert_true(sim.execute(StrikeCommand.new(&"never", &"a1", 1)), "strike %d" % (i + 1))
	s.strikes_left = 5
	assert_eq(StrikeCommand.new(&"never", &"a1", 1).validate(s), "out_of_stock")


func test_strike_result_does_not_depend_on_stock_origin() -> void:
	var results: Array = []
	for granted in [0, 3]:
		var s := _granted_strike_state(10 - granted, granted, 5)
		var sim := OperationalSimulation.new(s)
		var seen: Array[Dictionary] = []
		sim.event_emitted.connect(func(e: Dictionary) -> void: seen.append(e))
		assert_true(sim.execute(StrikeCommand.new(&"sure", &"a1", 2)))
		results.append(seen)
	assert_eq(results[0], results[1])
