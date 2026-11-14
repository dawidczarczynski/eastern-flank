extends TestCase
## Orders per turn (C2 integrity limits the orders a side may issue on the staff map): the limit
## from the installations, IssueOrderCommand's `no_orders_left`, the reset at the turn start, the
## snapshot and the AI.

const TestOrders := preload("res://tests/unit/test_formation_orders.gd")

var _previous_locale: String


func before_all() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_all() -> void:
	TranslationServer.set_locale(_previous_locale)


static func _c2(owner: int, integrity: int) -> Installation:
	var installation := Installation.new()
	installation.id = StringName("c2_%d_%d" % [owner, integrity])
	installation.class_id = &"c2"
	installation.owner = owner
	installation.integrity = integrity
	return installation


## A state with `count` own formations on row 0 (player 0); each can march one hex east.
static func _state(count: int) -> OperationalState:
	var state := TestOrders._state()
	state.formations.clear()
	for i in count:
		state.formations.append(TestOrders._formation(StringName("f%d" % i), 0, Vector2i(i, 0)))
	return state


static func _order(index: int) -> IssueOrderCommand:
	return IssueOrderCommand.new(StringName("f%d" % index), Vector2i(9, 1), &"march")


func test_shipped_data() -> void:
	var rules := BattleConditionsRules.shipped()
	assert_eq(rules.problem(), "")
	assert_eq(rules.orders_base, 4)
	assert_eq(rules.orders_floor, 25)


func test_limit_follows_c2_integrity() -> void:
	var state := OperationalState.new()
	assert_eq(state.orders_per_turn(0), 4, "no command post: not penalised")
	state.installations.append(_c2(0, 50))
	state.installations.append(_c2(1, 100))
	assert_eq(state.orders_per_turn(0), 2)
	assert_eq(state.orders_per_turn(1), 4)
	state.installations[0].integrity = 0
	assert_eq(state.orders_per_turn(0), 1, "never below 1")


func test_orders_are_counted_and_the_next_is_rejected() -> void:
	var state := _state(5)
	var sim := OperationalSimulation.new(state)
	var reasons: Array[String] = []
	sim.command_rejected.connect(func(_c: OperationalCommand, r: String) -> void: reasons.append(r))
	for i in 4:
		assert_true(sim.execute(_order(i)), "order %d" % i)
	assert_eq(state.orders_left(), 0)
	assert_false(sim.execute(_order(4)))
	assert_eq(reasons, ["no_orders_left"])
	assert_eq(_order(4).validate(state), "no_orders_left")


func test_replacing_an_order_counts_again() -> void:
	var state := _state(1)
	var sim := OperationalSimulation.new(state)
	for i in 4:
		assert_true(sim.execute(IssueOrderCommand.new(&"f0", Vector2i(i + 1, 0), &"march")))
	assert_eq(state.orders_left(), 0)


func test_cancel_and_posture_stay_free() -> void:
	var state := _state(5)
	var sim := OperationalSimulation.new(state)
	for i in 4:
		sim.execute(_order(i))
	assert_eq(state.orders_left(), 0)
	assert_true(sim.execute(SetPostureCommand.new(&"f0", &"defend")))
	assert_true(sim.execute(CancelOrderCommand.new(&"f0")))
	assert_eq(state.orders_left(), 0)


func test_a_rejected_order_is_not_counted() -> void:
	var state := _state(1)
	var sim := OperationalSimulation.new(state)
	assert_false(sim.execute(IssueOrderCommand.new(&"f0", Vector2i(99, 99), &"march")))
	assert_eq(state.orders_issued, 0)


func test_limit_is_read_from_the_current_installations() -> void:
	var state := _state(3)
	state.installations.append(_c2(0, 50))
	var sim := OperationalSimulation.new(state)
	assert_true(sim.execute(_order(0)))
	assert_true(sim.execute(_order(1)))
	assert_false(sim.execute(_order(2)))
	state.installations[0].integrity = 100  # repaired: 4 orders, 2 used
	assert_true(sim.execute(_order(2)))


func test_the_count_resets_at_the_turn_start() -> void:
	var state := _state(5)
	var sim := OperationalSimulation.new(state)
	for i in 4:
		sim.execute(_order(i))
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(state.orders_issued, 0)
	assert_true(sim.execute(EndOperationalTurnCommand.new()))
	assert_eq(state.current_player, 0)
	assert_eq(state.orders_left(), 4)


func test_snapshot_only_carries_the_count_when_used() -> void:
	var state := _state(2)
	assert_false(state.snapshot().has("orders_issued"), "old snapshots stay unchanged")
	OperationalSimulation.new(state).execute(_order(0))
	assert_eq(state.snapshot()["orders_issued"], 1)


func test_the_ai_stays_within_the_limit_and_ends_the_turn() -> void:
	var sim := OperationalSimulation.new(Operation.build(&"suwalki_gap", 1))
	var player := sim.state.current_player
	var out := OperationalAiTurn.play(sim, player)
	var orders := 0
	for command: OperationalCommand in out["commands"]:
		if command is IssueOrderCommand:
			orders += 1
	assert_true(orders <= sim.state.orders_per_turn(player), "orders %d" % orders)
	assert_false((out["results"] as Array[bool]).has(false), "no order is rejected")
	assert_true(out["ended"])


func test_orders_left_text_for_the_view() -> void:
	var state := _state(3)
	state.installations.append(_c2(0, 50))
	state.installations.append(_c2(1, 100))
	assert_eq(StaffMapOrders.orders_left_text(state, 0), "ORDERS LEFT 2 / 2")
	OperationalSimulation.new(state).execute(_order(0))
	assert_eq(StaffMapOrders.orders_left_text(state, 0), "ORDERS LEFT 1 / 2")
	assert_eq(StaffMapOrders.orders_left_text(state, 1), "ORDERS LEFT 4 / 4", "waiting side")


func test_rejection_text() -> void:
	assert_eq(StaffMapOrderRingModel.reason_text("no_orders_left"), "No orders left this turn.")
