class_name CombatForecast
extends RefCounted
## Exact odds of one attack (TASK-089a): the attacker's strike and the defender's counter, from
## the binomial distribution of the per-element rolls (AttackCommand). Pure – it never touches
## GameState.rng or a unit – so the HUD and the AI can call it freely (AttackCommand.forecast).
## It ignores that BattleRules.after_strike may end the battle after the first strike (which
## would cancel the counter). Percentiles: the smallest k with P(X <= k) >= 0.10 / >= 0.90.

const LOW_QUANTILE := 0.10
const HIGH_QUANTILE := 0.90
## Tolerance of the percentile comparison (the cumulative sums are floats).
const _EPSILON := 1e-9

## Hex distance between the two units (TASK-131a).
var distance: int
## Share of the attacker's full hit chance left at that distance (AttackCommand.range_factor).
var range_factor: float
## The attacker sees the defender (LineOfSight; indirect fire doesn't need it).
var line_of_sight: bool
## Why the attack itself is illegal from where the attacker stands: AttackCommand.fire_problem
## ("" = it can fire; the same codes as AttackCommand.validate).
var problem: String
## Attacker strength rolling (its current HP).
var shots: int
## A roll <= hit_on hits.
var hit_on: int
## Faces of the attacker's die (its max_hp).
var die: int
## E[min(hits, defender hp)].
var expected_damage: float
## 10th / 90th percentile of min(hits, defender hp).
var damage_low: int
var damage_high: int
## P(hits >= defender hp).
var kill_chance: float
## The defender can fire back at the attacker: range and, for direct fire, line of sight
## (a battle end by objectives ignored).
var counter_possible: bool
## E[min(counter hits, attacker hp)] over every outcome of the first strike (0 without counter).
var counter_expected: float
## 10th / 90th percentile of the counter damage mixture (0 when no counter).
var counter_low: int
var counter_high: int
## P(the counter destroys the attacker).
var attacker_loss_chance: float


static func compute(state: GameState, attacker: Unit, defender: Unit) -> CombatForecast:
	return compute_at(state, attacker, defender, attacker.coord)


## compute as if the attacker stood on `from` (the AI weighs firing positions; TASK-131a).
static func compute_at(
	state: GameState, attacker: Unit, defender: Unit, from: Vector2i
) -> CombatForecast:
	var f := CombatForecast.new()
	f.distance = Hex.distance(from, defender.coord)
	f.range_factor = AttackCommand.range_factor(attacker.definition, f.distance)
	f.line_of_sight = LineOfSight.visible(state.grid, from, defender.coord)
	f.problem = AttackCommand.fire_problem(state, attacker.definition, from, defender.coord)
	f.shots = attacker.hp
	f.die = attacker.definition.max_hp
	f.hit_on = AttackCommand.hit_on_at(state, attacker, defender, f.distance)
	var damage := _capped(binomial(f.shots, float(f.hit_on) / f.die), defender.hp)
	f.expected_damage = mean(damage)
	f.damage_low = percentile(damage, LOW_QUANTILE)
	f.damage_high = percentile(damage, HIGH_QUANTILE)
	f.kill_chance = damage[defender.hp]
	f.counter_possible = (
		AttackCommand.fire_problem(state, defender.definition, defender.coord, from) == ""
	)
	var counter := _counter_damage(state, attacker, defender, damage, f)
	f.counter_expected = mean(counter)
	f.counter_low = percentile(counter, LOW_QUANTILE)
	f.counter_high = percentile(counter, HIGH_QUANTILE)
	f.attacker_loss_chance = counter[attacker.hp] if f.counter_possible else 0.0
	return f


## P(X = k) for k = 0 … n, X ~ Binomial(n, p).
static func binomial(n: int, p: float) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(n + 1)
	var ways := 1.0
	for k in n + 1:
		result[k] = ways * pow(p, k) * pow(1.0 - p, n - k)
		ways = ways * (n - k) / (k + 1)
	return result


## Mean of a distribution over 0 … size − 1.
static func mean(distribution: PackedFloat64Array) -> float:
	var total := 0.0
	for k in distribution.size():
		total += k * distribution[k]
	return total


## Smallest k with P(X <= k) >= q.
static func percentile(distribution: PackedFloat64Array, q: float) -> int:
	var cumulative := 0.0
	for k in distribution.size():
		cumulative += distribution[k]
		if cumulative >= q - _EPSILON:
			return k
	return distribution.size() - 1


## The distribution of min(X, cap) over 0 … cap.
static func _capped(distribution: PackedFloat64Array, cap: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(cap + 1)
	result.fill(0.0)
	for k in distribution.size():
		result[mini(k, cap)] += distribution[k]
	return result


## Counter damage to the attacker (0 … attacker hp) mixed over the first strike's `damage`
## distribution: the defender rolls the HP it has left; a destroyed defender doesn't counter.
static func _counter_damage(
	state: GameState, attacker: Unit, defender: Unit, damage: PackedFloat64Array, f: CombatForecast
) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(attacker.hp + 1)
	result.fill(0.0)
	if not f.counter_possible:
		result[0] = 1.0
		return result
	var hit := AttackCommand.hit_on_at(state, defender, attacker, f.distance)
	var p := float(hit) / defender.definition.max_hp
	for k in damage.size():
		var left := defender.hp - k
		if left <= 0:
			result[0] += damage[k]
			continue
		var counter := _capped(binomial(left, p), attacker.hp)
		for j in counter.size():
			result[j] += damage[k] * counter[j]
	return result
