# gdlint: disable=max-public-methods
extends TestCase
## Borders in movement and battle (TASK-116): closed countries in routes and orders, sanctuary
## breach and casus belli while orders execute, the route incident forecast, the border rule for
## contact battles and retreats.

const Politics := preload("res://tests/unit/test_country_rules.gd")

var _events: Array[Dictionary] = []


## "quad": 8 x 4 plains; poland q<4 r<2, russia q>=4 r<2, lithuania q<4 r>=2, belarus q>=4 r>=2.
static func _quad() -> OperationalState:
	var grid := HexGrid.new()
	var map := {}
	for q in range(0, 8):
		for r in range(0, 4):
			grid.set_terrain(Vector2i(q, r), Terrain.Type.PLAINS)
			var id := &"poland"
			if q >= 4 and r < 2:
				id = &"russia"
			elif q < 4 and r >= 2:
				id = &"lithuania"
			elif q >= 4:
				id = &"belarus"
			map[Vector2i(q, r)] = id
	return _start(Operation.from_definition(Politics._definition(), 1, grid, map))


## "line": 6 x 1 plains; q 0-2 poland, q 3-5 belarus.
static func _line() -> OperationalState:
	var grid := HexGrid.new()
	var map := {}
	for q in range(0, 6):
		grid.set_terrain(Vector2i(q, 0), Terrain.Type.PLAINS)
		map[Vector2i(q, 0)] = &"poland" if q < 3 else &"belarus"
	return _start(Operation.from_definition(Politics._definition(), 1, grid, map))


static func _start(state: OperationalState) -> OperationalState:
	state.first_player = 0
	state.current_player = 0
	return state


static func _add(state: OperationalState, id: StringName, owner: int, at: Vector2i) -> Formation:
	var f := Formation.new()
	f.id = id
	f.owner_id = owner
	f.coord = at
	f.definition = FormationDefinition.new()
	f.companies.append(Formation.Company.new(&"leopard_2a4", 5, "%s/1" % id))
	state.formations.append(f)
	return f


func _sim(state: OperationalState) -> OperationalSimulation:
	_events.clear()
	var sim := OperationalSimulation.new(state)
	sim.event_emitted.connect(func(e: Dictionary) -> void: _events.append(e))
	return sim


func _end(sim: OperationalSimulation) -> Array[Dictionary]:
	_events.clear()
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	return _events.duplicate()


static func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> Variant: return e["type"])


static func _reason(state: OperationalState, id: StringName, to: Vector2i) -> String:
	state.current_player = state.get_formation(id).owner_id
	return IssueOrderCommand.new(id, to, &"march").validate(state)


static func _has_country(state: OperationalState, route: Array[Vector2i], id: StringName) -> bool:
	for hex in route:
		if state.country_at(hex) == id:
			return true
	return false


# --- routes and orders ---


func test_plan_closed_countries_quad() -> void:
	var s := _quad()
	var f := _add(s, &"f", 0, Vector2i(0, 0))
	var r := _add(s, &"r", 1, Vector2i(7, 3))
	assert_false(OperationalRoutes.plan(s, f, Vector2i(3, 3), false).is_empty(), "own lithuania")
	assert_true(OperationalRoutes.plan(s, f, Vector2i(7, 0), false).is_empty(), "russia, level 1")
	var to_russia := OperationalRoutes.plan(s, r, Vector2i(0, 0), false)
	assert_false(to_russia.is_empty())
	assert_false(_has_country(s, to_russia, &"lithuania"), "hostile lithuania is closed to 1")
	s.escalation_level = 2
	var open := OperationalRoutes.plan(s, f, Vector2i(7, 0), false)
	assert_false(open.is_empty(), "russia, level 2")
	assert_false(_has_country(s, open, &"belarus"))


func test_plan_never_traps_a_formation() -> void:
	var s := _quad()
	var r := _add(s, &"r", 1, Vector2i(7, 3))
	CountryRules.set_stance(s, &"belarus", CountryState.NEUTRAL, -1, &"test", -1)
	assert_false(OperationalRoutes.plan(s, r, Vector2i(6, 1), false).is_empty())
	assert_eq(_reason(s, &"r", Vector2i(6, 3)), "", "order inside the country it stands in")


func test_order_rejected_closed_country() -> void:
	var s := _quad()
	_add(s, &"f", 0, Vector2i(0, 0))
	_add(s, &"r", 1, Vector2i(7, 3))
	assert_eq(_reason(s, &"f", Vector2i(7, 0)), "closed_country")
	assert_eq(_reason(s, &"r", Vector2i(1, 3)), "closed_country")
	assert_eq(_reason(s, &"f", Vector2i(0, 0)), "invalid_destination", "checked before")
	assert_eq(_reason(s, &"f", Vector2i(99, 99)), "invalid_destination")
	assert_eq(_reason(s, &"f", Vector2i(3, 3)), "")


func test_closed_country_before_occupied() -> void:
	var s := _quad()
	_add(s, &"f", 0, Vector2i(0, 0))
	_add(s, &"g", 0, Vector2i(7, 0))
	assert_eq(_reason(s, &"f", Vector2i(7, 0)), "closed_country")
	s.escalation_level = 2
	assert_eq(_reason(s, &"f", Vector2i(7, 0)), "occupied")


func test_execution_interrupts_when_destination_closes() -> void:
	var s := _quad()
	_add(s, &"f", 0, Vector2i(0, 0))
	var sim := _sim(s)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(3, 3), &"advance")))
	CountryRules.set_stance(s, &"lithuania", CountryState.NEUTRAL, -1, &"test", -1)
	var events := _end(sim)
	assert_eq(events[0]["type"], &"formation_order_interrupted")
	assert_eq(events[0]["reason"], &"closed_country")
	assert_true(s.get_formation(&"f").order == null)
	assert_eq(s.get_formation(&"f").coord, Vector2i(0, 0))


func test_closed_country_checked_before_occupied_at_execution() -> void:
	var s := _quad()
	_add(s, &"f", 0, Vector2i(0, 0))
	_add(s, &"g", 0, Vector2i(3, 3))
	var sim := _sim(s)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(3, 2), &"march")))
	CountryRules.set_stance(s, &"lithuania", CountryState.NEUTRAL, -1, &"test", -1)
	s.get_formation(&"f").order.destination = Vector2i(3, 3)
	assert_eq(_end(sim)[0]["reason"], &"closed_country")


# --- incidents during execution ---


func test_sanctuary_breach_during_execution() -> void:
	var s := _quad()
	s.escalation_level = 2
	_add(s, &"f", 0, Vector2i(3, 0))
	_add(s, &"g", 0, Vector2i(3, 1))
	var sim := _sim(s)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(5, 0), &"march")))
	var events := _end(sim)
	assert_eq(s.get_formation(&"f").coord, Vector2i(5, 0))
	assert_eq(
		_types(events).slice(0, 6),
		[
			&"formation_moved",
			&"sanctuary_breached",
			&"escalation_changed",
			&"country_stance_changed",
			&"country_stance_changed",
			&"formation_order_completed",
		]
	)
	assert_eq(events[1]["country"], &"russia")
	assert_eq(events[1]["player"], 0)
	assert_eq(events[1]["at"], Vector2i(4, 0))
	assert_eq(events[2]["previous"], 2)
	assert_eq(events[2]["level"], 3)
	assert_eq(events[2]["cause"], &"sanctuary_breach")
	assert_eq(events[3]["country"], &"lithuania")
	assert_eq(events[4]["country"], &"belarus")
	assert_eq(s.escalation_level, 3)


func test_second_formation_no_breach() -> void:
	var s := _quad()
	s.escalation_level = 2
	_add(s, &"f", 0, Vector2i(3, 0))
	_add(s, &"g", 0, Vector2i(3, 1))
	var sim := _sim(s)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(5, 0), &"march")))
	assert_true(sim.execute(IssueOrderCommand.new(&"g", Vector2i(5, 1), &"march")))
	var types := _types(_end(sim))
	assert_eq(types.count(&"sanctuary_breached"), 1)
	assert_eq(types.count(&"formation_order_completed"), 2)


func test_breach_at_the_cap_does_not_end_the_operation() -> void:
	var s := _quad()
	s.escalation_level = 5
	_add(s, &"f", 0, Vector2i(3, 0))
	_add(s, &"g", 0, Vector2i(3, 1))
	var sim := _sim(s)
	assert_true(sim.execute(IssueOrderCommand.new(&"f", Vector2i(5, 0), &"march")))
	assert_true(sim.execute(IssueOrderCommand.new(&"g", Vector2i(2, 0), &"march")))
	var events := _end(sim)
	var types := _types(events)
	assert_eq(types.count(&"sanctuary_breached"), 1, "the breach still happens")
	assert_false(types.has(&"escalation_changed"), "no step above the cap")
	assert_false(types.has(&"operation_ended"))
	assert_eq(s.escalation_level, 5)
	assert_true(s.get_country(&"russia").breached_by[0])
	assert_eq(s.escalation_caused, [0, 0])
	assert_eq(types.count(&"formation_order_completed"), 2, "both formations execute")
	assert_true(types.has(&"operational_turn_ended"))
	assert_eq(s.get_formation(&"f").coord, Vector2i(5, 0))


func test_casus_belli_out_of_aligned_country() -> void:
	var s := _line()
	_add(s, &"f", 0, Vector2i(2, 0))
	_add(s, &"r", 1, Vector2i(4, 0))
	var sim := _sim(s)
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_true(sim.execute(IssueOrderCommand.new(&"r", Vector2i(3, 0), &"march")))
	var belarus := s.get_country(&"belarus")
	assert_false(belarus.casus_belli[0])
	var events := _end(sim)
	assert_eq(_types(events).count(&"casus_belli_gained"), 0, "moving inside belarus")
	assert_false(belarus.casus_belli[0])


func test_casus_belli_event() -> void:
	var s := _line()
	_add(s, &"f", 0, Vector2i(0, 0))
	_add(s, &"r", 1, Vector2i(4, 0))
	s.current_player = 1
	var sim := _sim(s)
	assert_true(sim.execute(IssueOrderCommand.new(&"r", Vector2i(1, 0), &"march")))
	var events := _end(sim)
	var got: Array[Dictionary] = []
	for e in events:
		if e["type"] == &"casus_belli_gained":
			got.append(e)
	assert_eq(got.size(), 1)
	assert_eq(got[0]["country"], &"belarus")
	assert_eq(got[0]["player"], 0)
	assert_eq(got[0]["formation_id"], &"r")
	assert_eq(got[0]["at"], Vector2i(2, 0))
	assert_true(s.get_country(&"belarus").casus_belli[0])
	var order := _types(events)
	assert_true(order.find(&"formation_moved") < order.find(&"casus_belli_gained"))
	assert_true(order.find(&"casus_belli_gained") < order.find(&"formation_order_completed"))
	# A stance change resets the flag.
	CountryRules.set_stance(s, &"belarus", CountryState.BELLIGERENT, 1, &"test", -1)
	assert_false(s.get_country(&"belarus").casus_belli[0])


func test_casus_belli_once_per_country_and_player() -> void:
	var s := _line()
	s.get_country(&"belarus").casus_belli[0] = true
	_add(s, &"r", 1, Vector2i(4, 0))
	s.current_player = 1
	var sim := _sim(s)
	assert_true(sim.execute(IssueOrderCommand.new(&"r", Vector2i(1, 0), &"march")))
	assert_eq(_types(_end(sim)).count(&"casus_belli_gained"), 0)


# --- borders in battle ---


func test_battle_allowed_border_rule() -> void:
	var s := _line()
	var f := _add(s, &"f", 0, Vector2i(2, 0))
	var r := _add(s, &"r", 1, Vector2i(3, 0))
	assert_false(ContactRules.battle_allowed(s, f, r), "belarus is closed to 0")
	assert_true(ContactRules.battle_allowed(s, r, f), "poland is open to 1")
	CountryRules.set_stance(s, &"belarus", CountryState.BELLIGERENT, 1, &"test", 1)
	assert_true(ContactRules.battle_allowed(s, f, r))
	assert_true(ContactRules.battle_allowed(s, r, f))


func test_contact_forbidden_by_border_then_allowed() -> void:
	var s := _line()
	var f := _add(s, &"f", 0, Vector2i(2, 0))
	_add(s, &"r", 1, Vector2i(3, 0))
	var halted: Array[Dictionary] = [
		{"type": &"formation_halted", "formation_id": &"f", "at": f.coord, "reason": &"contact"}
	]
	var events := halted.duplicate()
	ContactRules.start_battles(s, events)
	assert_true(s.pending_battles.is_empty())
	assert_eq(_types(events), [&"formation_halted", &"contact_forbidden"])
	assert_eq(events[1]["attacker_id"], &"f")
	assert_eq(events[1]["defender_id"], &"r")
	assert_eq(events[1]["country"], &"belarus")
	assert_eq(events[1]["at"], Vector2i(3, 0))
	CountryRules.set_stance(s, &"belarus", CountryState.BELLIGERENT, 1, &"test", 1)
	events = halted.duplicate()
	ContactRules.start_battles(s, events)
	assert_eq(s.pending_battles.size(), 1)
	assert_eq(s.pending_battles[0].attacker, 0)
	assert_eq(_types(events), [&"formation_halted", &"battle_pending"])


func test_retreat_never_ends_on_a_closed_hex() -> void:
	var s := _quad()
	var f := _add(s, &"f", 0, Vector2i(3, 1))
	var enemy := _add(s, &"e", 1, Vector2i(2, 1))
	var hex: Variant = BattleConsequences.retreat_hex(s, f, enemy)
	assert_true(hex != null)
	assert_true(CountryRules.may_enter(s, 0, hex as Vector2i))
	assert_eq(hex, Vector2i(3, 2), "lithuania is own; russia (4,1), (4,0) are closed")
	var g := _add(s, &"g", 0, Vector2i(3, 2))
	var enemy2 := _add(s, &"e2", 1, Vector2i(2, 2))
	hex = BattleConsequences.retreat_hex(s, g, enemy2)
	var country := s.country_at(hex as Vector2i)
	assert_true(country == &"lithuania" or country == &"poland", String(country))
	assert_true(enemy2 != null)


func test_no_retreat_when_every_hex_is_closed() -> void:
	var s := _quad()
	var f := _add(s, &"f", 0, Vector2i(5, 3))
	var enemy := _add(s, &"e", 1, Vector2i(7, 3))
	assert_true(BattleConsequences.retreat_hex(s, f, enemy) == null)


# --- forecast ---


func test_route_incidents_breach() -> void:
	var s := _quad()
	s.escalation_level = 2
	var f := _add(s, &"f", 0, Vector2i(3, 0))
	var route: Array[Vector2i] = [Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)]
	var incidents := EscalationRules.route_incidents(s, f, route)
	assert_eq(incidents.size(), 1)
	assert_eq(incidents[0]["type"], &"sanctuary_breach")
	assert_eq(incidents[0]["country"], &"russia")
	assert_eq(incidents[0]["at"], Vector2i(4, 0))
	assert_eq(incidents[0]["steps"], 1)
	assert_false(incidents[0]["ends_operation"])
	s.escalation_level = 4
	var capped := EscalationRules.route_incidents(s, f, route)[0]
	assert_eq(capped["steps"], 1)
	assert_false(capped["ends_operation"], "an incident never ends the operation")
	s.escalation_level = 5
	var at_cap := EscalationRules.route_incidents(s, f, route)[0]
	assert_eq(at_cap["steps"], 0, "clipped to the cap")
	assert_false(at_cap["ends_operation"])
	assert_eq(s.escalation_level, 5, "pure")
	assert_false(s.get_country(&"russia").breached_by[0], "pure")
	assert_true(EscalationRules.route_incidents(s, f, [] as Array[Vector2i]).is_empty())


func test_route_incidents_casus_belli_and_none() -> void:
	var s := _line()
	var r := _add(s, &"r", 1, Vector2i(4, 0))
	var route: Array[Vector2i] = [Vector2i(3, 0), Vector2i(2, 0), Vector2i(1, 0)]
	var incidents := EscalationRules.route_incidents(s, r, route)
	assert_eq(incidents.size(), 1)
	assert_eq(incidents[0]["type"], &"casus_belli")
	assert_eq(incidents[0]["country"], &"belarus")
	assert_eq(incidents[0]["for_player"], 0)
	assert_eq(incidents[0]["at"], Vector2i(2, 0))
	var inside: Array[Vector2i] = [Vector2i(3, 0)]
	assert_true(EscalationRules.route_incidents(s, r, inside).is_empty())
	s.get_country(&"belarus").casus_belli[0] = true
	assert_true(EscalationRules.route_incidents(s, r, route).is_empty(), "flag already set")


# --- battle never escalates ---


func test_battle_does_not_escalate() -> void:
	var s := _line()
	CountryRules.set_stance(s, &"belarus", CountryState.BELLIGERENT, 1, &"test", 1)
	var f := _add(s, &"f", 0, Vector2i(2, 0))
	var r := _add(s, &"r", 1, Vector2i(3, 0))
	var halted: Array[Dictionary] = [
		{"type": &"formation_halted", "formation_id": &"f", "at": f.coord, "reason": &"contact"}
	]
	ContactRules.start_battles(s, halted)
	assert_eq(s.pending_battles.size(), 1)
	var setup: BattleSetup = s.pending_battles[0]
	var result := BattleResult.new()
	result.winner = 0
	result.reason = &"turn_limit"
	result.turns = 8
	var caused := s.escalation_caused.duplicate()
	var flags := s.get_country(&"belarus").casus_belli.duplicate()
	var level := s.escalation_level
	var sim := OperationalSimulation.new(s)
	for company in setup.companies:
		var res := BattleResult.Company.new()
		res.player = company.player
		res.unit_type = company.unit_type
		res.ref = company.ref
		res.strength_start = company.strength
		res.strength_end = company.strength
		result.companies.append(res)
	sim.execute(ResolveBattleCommand.new(result))
	assert_eq(s.escalation_level, level)
	assert_eq(s.escalation_caused, caused)
	assert_eq(s.get_country(&"belarus").casus_belli, flags)
	assert_true(r != null)


# --- replay ---


func _script_run(state: OperationalState, dicts: Array[Dictionary]) -> Array[Dictionary]:
	var sim := _sim(state)
	var all: Array[Dictionary] = []
	sim.event_emitted.connect(func(e: Dictionary) -> void: all.append(e))
	for d in dicts:
		var cmd := OperationalCommandCodec.from_dict(
			JSON.parse_string(JSON.stringify(d)) as Dictionary
		)
		assert_true(sim.execute(cmd))
	return all


## 8 x 1: russia q 0-1, poland q 2-4, belarus q 5-7; level 2.
func _replay_state() -> OperationalState:
	var grid := HexGrid.new()
	var map := {}
	for q in range(0, 8):
		grid.set_terrain(Vector2i(q, 0), Terrain.Type.PLAINS)
		map[Vector2i(q, 0)] = &"russia" if q < 2 else (&"poland" if q < 5 else &"belarus")
	var s := _start(Operation.from_definition(Politics._definition(), 1, grid, map))
	s.escalation_level = 2
	_add(s, &"f", 0, Vector2i(3, 0))
	_add(s, &"r", 1, Vector2i(6, 0))
	s.current_player = 1
	return s


func test_replay_with_breach_and_casus_belli() -> void:
	var dicts: Array[Dictionary] = [
		IssueOrderCommand.new(&"r", Vector2i(4, 0), &"march").to_dict(),
		EndOperationalTurnCommand.new().to_dict(),
		IssueOrderCommand.new(&"f", Vector2i(1, 0), &"march").to_dict(),
		EndOperationalTurnCommand.new().to_dict(),
	]
	var first := _replay_state()
	var rng_before := first.rng.state
	var events_a := _script_run(first, dicts)
	var types := _types(events_a)
	assert_true(types.has(&"sanctuary_breached"))
	assert_true(types.has(&"casus_belli_gained"))
	assert_false(types.has(&"battle_pending"))
	assert_eq(first.rng.state, rng_before)
	var second := _replay_state()
	var events_b := _script_run(second, dicts)
	assert_eq(first.snapshot(), second.snapshot())
	assert_eq(str(events_a), str(events_b))


# --- the real operation ---


func test_real_operation_borders() -> void:
	var s := Operation.build(&"suwalki_gap", 7)
	s.current_player = 0
	var by_formation := _first_with_country(s, 1, &"belarus")
	assert_true(by_formation != null, "a Russian formation stands in Belarus")
	var near := _closest_free(s, by_formation, &"poland", 1)
	var route := OperationalRoutes.plan(s, by_formation, near, false)
	assert_eq(_reason(s, by_formation.id, near), "")
	assert_false(route.is_empty())
	assert_false(_has_country(s, route, &"lithuania"))
	var polish := _first_with_country(s, 0, &"poland")
	var grodno := _closest_free(s, polish, &"belarus", 0)
	assert_eq(_reason(s, polish.id, grodno), "closed_country")
	var oblast := _closest_free(s, polish, &"russia", 0)
	assert_eq(_reason(s, polish.id, oblast), "closed_country")
	EscalationRules.raise(s, 1, &"test")
	assert_eq(s.escalation_level, 2)
	assert_eq(_reason(s, polish.id, oblast), "")
	var path := OperationalRoutes.plan(s, polish, oblast, false)
	var incidents := EscalationRules.route_incidents(s, polish, path)
	assert_eq(incidents.size(), 1)
	assert_eq(incidents[0]["type"], &"sanctuary_breach")


func _first_with_country(s: OperationalState, owner: int, country: StringName) -> Formation:
	for f in s.formations:
		if f.owner_id == owner and s.country_at(f.coord) == country:
			return f
	return null


## The free land hex of `country` closest to `f` that `f` could reach if the border were open.
func _closest_free(s: OperationalState, f: Formation, country: StringName, _p: int) -> Vector2i:
	var best := f.coord
	var best_d := 1 << 30
	for c: Vector2i in s.country_map:
		if s.country_map[c] != country or s.formation_at(c) != null:
			continue
		if s.grid.get_terrain(c) == Terrain.Type.WATER:
			continue
		var d := Hex.distance(f.coord, c)
		if d < best_d:
			best_d = d
			best = c
	return best
