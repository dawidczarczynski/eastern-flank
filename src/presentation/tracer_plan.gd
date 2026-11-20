class_name TracerPlan
extends RefCounted
## Pure timing and layout of an infantry attack's fire (TASK-188b): which rounds are tracers, when
## each soldier's round leaves and lands, and when the anti-tank rocket flies. No nodes, no state;
## InfantryFire plays the plan. View-only: it reads positions, never the simulation.

## Rounds each firing soldier sends per attack.
const ROUNDS := 2
## Seconds between the rounds of one soldier and between the soldiers within a round.
const ROUND_GAP := 0.12
const SOLDIER_STAGGER := 0.04
## Rifle bullet speed (world units per second) and the flight time limits.
const BULLET_SPEED := 14.0
const BULLET_FLIGHT_MIN := 0.1
const BULLET_FLIGHT_MAX := 0.4
## The rocket leaves this long after the attack starts; its flight = base + per unit of distance.
const ROCKET_DELAY := 0.12
const ROCKET_FLIGHT_BASE := 0.35
const ROCKET_FLIGHT_PER_UNIT := 0.05
## How long the rocket's explosion lasts after it lands (InfantryFire.BLAST_TIME).
const ROCKET_BLAST := 0.32
## Quiet time after the last landing.
const TAIL := 0.1


## Whether the 0-based round `shot_index` is a tracer when every `interval`-th round is one
## (interval 4: rounds 3, 7, 11 ...; interval 1: all).
static func is_tracer(shot_index: int, interval: int) -> bool:
	return interval >= 1 and shot_index % interval == interval - 1


static func bullet_flight(distance: float) -> float:
	return clampf(distance / BULLET_SPEED, BULLET_FLIGHT_MIN, BULLET_FLIGHT_MAX)


static func rocket_flight(distance: float) -> float:
	return ROCKET_FLIGHT_BASE + ROCKET_FLIGHT_PER_UNIT * distance


## The rifle rounds of `muzzles` (world positions) at `aim`: [{from, to, t0, flight, tracer}] in
## firing order; round r of soldier i is shot r * muzzles.size() + i.
static func rifle_shots(muzzles: Array[Vector3], aim: Vector3, interval: int) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var count := muzzles.size()
	for r in ROUNDS:
		for i in count:
			var index := r * count + i
			(
				shots
				. append(
					{
						"from": muzzles[i],
						"to": aim,
						"t0": r * ROUND_GAP + i * SOLDIER_STAGGER,
						"flight": bullet_flight(muzzles[i].distance_to(aim)),
						"tracer": is_tracer(index, interval),
					}
				)
			)
	return shots


## Time the first round lands (the target's hit reaction starts then).
static func first_landing(shots: Array[Dictionary]) -> float:
	var first := INF
	for shot in shots:
		first = minf(first, float(shot["t0"]) + float(shot["flight"]))
	return first if first != INF else 0.0


## Playback length at speed 1 of the rounds and, when `rocket_distance` >= 0, of the rocket too;
## never shorter than the plain attack (EventQueue.ATTACK_DURATION).
static func duration(shots: Array[Dictionary], rocket_distance: float) -> float:
	var end := 0.0
	for shot in shots:
		end = maxf(end, float(shot["t0"]) + float(shot["flight"]))
	if rocket_distance >= 0.0:
		end = maxf(end, ROCKET_DELAY + rocket_flight(rocket_distance) + ROCKET_BLAST)
	return maxf(end + TAIL, EventQueue.ATTACK_DURATION)
