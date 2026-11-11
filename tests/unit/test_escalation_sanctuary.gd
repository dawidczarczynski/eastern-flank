extends TestCase
## Escalation (TASK-115): sanctuary gate, breach, rules of engagement for strikes.

const Politics := preload("res://tests/unit/test_country_rules.gd")


static func _strip() -> OperationalState:
	return Politics._strip()


static func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e: Dictionary) -> Variant: return e["type"])


# --- sanctuary ---


func test_sanctuary_gate() -> void:
	var s := _strip()
	var russia := Vector2i(6, 0)
	assert_false(CountryRules.may_enter(s, 0, russia))
	assert_false(CountryRules.may_strike(s, 0, russia))
	s.escalation_level = 2
	assert_true(CountryRules.may_enter(s, 0, russia))
	assert_true(CountryRules.may_strike(s, 0, russia))
	s.escalation_level = 1
	assert_false(CountryRules.may_enter(s, 0, russia))
	s.get_country(&"russia").breached_by[0] = true
	assert_true(CountryRules.may_enter(s, 0, russia))


func test_sanctuary_gate_mirrored() -> void:
	var s := _strip()
	var poland := CountryDefinition.new()
	poland.id = &"poland"
	poland.iso_code = "PL"
	poland.sanctuary = true
	s.get_country(&"poland").definition = poland
	assert_false(CountryRules.may_enter(s, 1, Vector2i(0, 0)))
	s.escalation_level = 2
	assert_true(CountryRules.may_enter(s, 1, Vector2i(0, 0)))


func test_breach() -> void:
	var s := _strip()
	var at := Vector2i(6, 0)
	assert_eq(EscalationRules.breach(s, 0, &"poland", at, &"f"), [], "own country")
	assert_eq(EscalationRules.breach(s, 0, &"belarus", at, &"f"), [], "not a sanctuary")
	var events := EscalationRules.breach(s, 0, &"russia", at, &"f")
	assert_eq(_types(events), [&"sanctuary_breached", &"escalation_changed"])
	assert_eq(events[0]["country"], &"russia")
	assert_eq(events[0]["player"], 0)
	assert_eq(events[0]["at"], at)
	assert_eq(events[0]["formation_id"], &"f")
	assert_eq(events[1]["cause"], &"sanctuary_breach")
	assert_eq(events[1]["by"], 0)
	assert_eq(s.escalation_level, 2)
	assert_true(s.get_country(&"russia").breached_by[0])
	assert_eq(EscalationRules.breach(s, 0, &"russia", at, &"f"), [])
	assert_eq(s.escalation_level, 2)


# --- ROE ---


func test_strike_allowed() -> void:
	var s := _strip()
	assert_eq(EscalationRules.strike_allowed(s, 0, Vector2i(6, 0), &"formation"), "closed_country")
	assert_eq(EscalationRules.strike_allowed(s, 0, Vector2i(4, 0), &"formation"), "closed_country")
	assert_eq(EscalationRules.strike_allowed(s, 0, Vector2i(1, 0), &"formation"), "own_soil")
	assert_eq(EscalationRules.strike_allowed(s, 1, Vector2i(0, 0), &"formation"), "")
	assert_eq(EscalationRules.strike_allowed(s, 1, Vector2i(0, 0), &"airfield"), "roe_class")
	assert_eq(EscalationRules.strike_allowed(s, 1, Vector2i(0, 0), &"unicorn"), "roe_class")
	s.escalation_level = 2
	assert_eq(EscalationRules.strike_allowed(s, 0, Vector2i(6, 0), &"airfield"), "")


func test_strike_escalation_and_on_strike() -> void:
	var s := _strip()
	s.escalation_level = 2
	var russia := Vector2i(6, 0)
	assert_eq(EscalationRules.strike_escalation(s, 0, russia), 1)
	s.grid.set_terrain(russia, Terrain.Type.URBAN)
	assert_eq(EscalationRules.strike_escalation(s, 0, russia), 2)
	var events := EscalationRules.on_strike(s, 0, russia)
	assert_eq(events[0]["type"], &"sanctuary_breached")
	assert_eq(events[1]["cause"], &"sanctuary_breach")
	assert_eq(events.back()["cause"], &"urban_strike")
	assert_eq(s.escalation_level, 4, "2 -> 3 -> 4, no end")
	assert_eq(s.result, {})
	assert_eq(s.escalation_caused, [2, 0])
	assert_eq(EscalationRules.strike_escalation(s, 0, russia), 0, "breach and urban used up")
	assert_eq(EscalationRules.strike_escalation(s, 1, Vector2i(0, 0)), 0, "not urban")
	s.grid.set_terrain(Vector2i(0, 0), Terrain.Type.URBAN)
	assert_eq(EscalationRules.strike_escalation(s, 1, Vector2i(0, 0)), 1, "the other side's first")
	s.escalation_level = 5
	assert_eq(EscalationRules.strike_escalation(s, 1, Vector2i(0, 0)), 0, "clipped at the cap")
