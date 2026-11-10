class_name StaffMapStrikeFx
extends RefCounted
## Procedural, time-driven impact effects of the strike layer (TASK-097b): a fireball, shockwave
## ring, smoke and sparks for a hit (varying by target class: airfield streaks, depot secondary
## explosions, c2 flash, air-defence spark ring, formation dust), a small airburst for an
## intercepted missile, a dust puff for a miss, and the scorch a destroyed target keeps. Everything
## is a function of the burst's age and seed, drawn on the layer's canvas with a few primitives.

const FIRE := Color(1.0, 0.62, 0.18)
const FIRE_CORE := Color(1.0, 0.92, 0.65)
const SMOKE := Color(0.22, 0.22, 0.24)
const DUST := Color(0.66, 0.6, 0.5)
const COLD := Color(0.75, 0.9, 1.0)


## Draws the effect of `burst` at `at` when `age` seconds have passed since its impact. `accent` is
## the outcome colour of the layer (used for rings and the airburst).
static func draw(
	canvas: CanvasItem, burst: Dictionary, age: float, at: Vector2, accent: Color
) -> void:
	if age < 0.0:
		return
	var seed_value: int = burst["seed"]
	match burst["outcome"]:
		StaffMapStrikeTrail.HIT:
			_hit(canvas, burst, age, at, seed_value, accent)
		StaffMapStrikeTrail.INTERCEPTED:
			_airburst(canvas, age, at, seed_value, accent)
		_:
			_dust(canvas, age, at, seed_value)


static func _hit(
	canvas: CanvasItem, burst: Dictionary, age: float, at: Vector2, seed_value: int, accent: Color
) -> void:
	var destroyed: bool = burst["destroyed"]
	var class_id: StringName = burst["class_id"]
	var size := 1.0
	if destroyed:
		size = 1.6
	elif class_id == &"formation":
		size = 0.8
	var t := clampf(age / StaffMapStrikeTrail.effect_seconds(burst), 0.0, 1.0)
	_scorch(canvas, at, minf(age * 6.0, 1.0), destroyed)
	if t >= 1.0:
		return
	var fire_colour := COLD if class_id == &"c2" else FIRE
	# Fireball: grows fast, shrinks and dims.
	var grow := 1.0 - pow(1.0 - minf(t * 3.0, 1.0), 2.0)
	var fire_alpha := 1.0 - smoothstep(0.15, 0.55, t)
	if fire_alpha > 0.0:
		canvas.draw_circle(at, 12.0 * size * grow, Color(fire_colour, 0.8 * fire_alpha))
		canvas.draw_circle(at, 6.5 * size * grow, Color(FIRE_CORE, fire_alpha))
	# Shockwave ring.
	var ring := minf(t * 2.2, 1.0)
	canvas.draw_arc(
		at, 8.0 + 26.0 * size * ring, 0.0, TAU, 28, Color(accent, 0.8 * (1.0 - ring)), 2.0, true
	)
	if class_id == &"c2":
		var second := clampf(t * 2.2 - 0.3, 0.0, 1.0)
		canvas.draw_arc(
			at,
			6.0 + 20.0 * size * second,
			0.0,
			TAU,
			24,
			Color(COLD, 0.7 * (1.0 - second)),
			1.5,
			true
		)
	_class_detail(canvas, class_id, t, at, seed_value, size)
	_smoke(canvas, t, at, seed_value, size)


## What makes a class recognisable: airfield debris streaks along the runway, depot secondary
## explosions, air-defence sparks, formation dust.
static func _class_detail(
	canvas: CanvasItem, class_id: StringName, t: float, at: Vector2, seed_value: int, size: float
) -> void:
	match class_id:
		&"airfield":
			var streak := minf(t * 3.0, 1.0)
			var alpha := 1.0 - t
			for sign_x in [-1.0, 1.0]:
				var start := at + Vector2(sign_x * 6.0, 0.0)
				canvas.draw_line(
					start,
					start + Vector2(sign_x * 30.0 * streak, 0.0),
					Color(FIRE, alpha),
					2.0,
					true
				)
		&"depot":
			# Secondary explosions: flickers after the main blast at seeded places.
			for k in 3:
				var begin := 0.25 + k * 0.2
				var phase := (t - begin) / 0.18
				if phase < 0.0 or phase > 1.0:
					continue
				var spot := (
					at
					+ (
						Vector2.from_angle(StaffMapStrikeTrail.unit(seed_value + k * 3) * TAU)
						* (9.0 + 8.0 * StaffMapStrikeTrail.unit(seed_value + k * 3 + 1))
					)
				)
				var flare := sin(phase * PI)
				canvas.draw_circle(spot, (5.0 + 3.0 * k) * size * flare, Color(FIRE, 0.85 * flare))
				canvas.draw_circle(spot, 2.5 * flare, Color(FIRE_CORE, flare))
		&"air_defence":
			var reach := minf(t * 3.0, 1.0)
			for i in 10:
				var direction := Vector2.from_angle(i * TAU / 10.0 + 0.3)
				canvas.draw_line(
					at + direction * (10.0 + 6.0 * reach),
					at + direction * (14.0 + 20.0 * reach),
					Color(FIRE_CORE, 1.0 - t),
					1.5,
					true
				)
		&"formation":
			for k in 4:
				var angle := StaffMapStrikeTrail.unit(seed_value + k) * TAU
				var puff := Vector2.from_angle(angle) * (6.0 + 16.0 * t)
				canvas.draw_circle(at + puff, 3.0 + 5.0 * t, Color(DUST, 0.5 * (1.0 - t)))
		_:
			pass


static func _smoke(canvas: CanvasItem, t: float, at: Vector2, seed_value: int, size: float) -> void:
	var phase := smoothstep(0.2, 1.0, t)
	if phase <= 0.0:
		return
	for k in 3:
		var drift := (StaffMapStrikeTrail.unit(seed_value + 20 + k) - 0.5) * 18.0
		var centre := at + Vector2(drift * phase, -10.0 * size - 22.0 * phase * (0.7 + 0.3 * k))
		canvas.draw_circle(centre, (5.0 + 7.0 * phase) * size, Color(SMOKE, 0.5 * (1.0 - phase)))


## The mark a hit leaves: a dark spot, bigger with a ring of lingering smoke on a destroyed target.
static func _scorch(canvas: CanvasItem, at: Vector2, grow: float, destroyed: bool) -> void:
	if destroyed:
		canvas.draw_circle(at, 12.0 * grow, Color(0.05, 0.04, 0.04, 0.5 * grow))
		canvas.draw_arc(at, 12.0 * grow, 0.0, TAU, 20, Color(SMOKE, 0.6 * grow), 1.5, true)
		canvas.draw_circle(at + Vector2(-3.0, -14.0), 4.5, Color(SMOKE, 0.28 * grow))
		canvas.draw_circle(at + Vector2(3.0, -20.0), 3.5, Color(SMOKE, 0.2 * grow))
	else:
		canvas.draw_circle(at, 5.0 * grow, Color(0.05, 0.04, 0.04, 0.35 * grow))


## A small flash and a spark ring where a missile was shot down.
static func _airburst(
	canvas: CanvasItem, age: float, at: Vector2, seed_value: int, accent: Color
) -> void:
	var t := clampf(age / 0.7, 0.0, 1.0)
	if t >= 1.0:
		return
	canvas.draw_circle(at, 7.0 * (1.0 - t * 0.4), Color(FIRE_CORE, 1.0 - t))
	canvas.draw_arc(at, 5.0 + 14.0 * t, 0.0, TAU, 20, Color(accent, 1.0 - t), 1.8, true)
	var turn := StaffMapStrikeTrail.unit(seed_value) * TAU
	for i in 6:
		var direction := Vector2.from_angle(turn + i * TAU / 6.0)
		canvas.draw_line(
			at + direction * (6.0 + 6.0 * t),
			at + direction * (10.0 + 12.0 * t),
			Color(accent, 1.0 - t),
			1.5,
			true
		)
	# Falling debris of the shot-down missile.
	canvas.draw_circle(at + Vector2(0.0, 4.0 + 16.0 * t * t), 1.8, Color(SMOKE, 1.0 - t))


## A dust puff where a missile landed beside the target.
static func _dust(canvas: CanvasItem, age: float, at: Vector2, seed_value: int) -> void:
	var t := clampf(age / StaffMapStrikeTrail.EFFECT_SECONDS, 0.0, 1.0)
	if t >= 1.0:
		return
	var spread := 1.0 - pow(1.0 - minf(t * 2.0, 1.0), 2.0)
	for k in 5:
		var angle := StaffMapStrikeTrail.unit(seed_value + k) * TAU
		var spot := at + Vector2.from_angle(angle) * (4.0 + 12.0 * spread)
		canvas.draw_circle(spot, 3.0 + 5.0 * spread, Color(DUST, 0.55 * (1.0 - t)))
	canvas.draw_arc(at, 3.0 + 14.0 * spread, 0.0, TAU, 18, Color(DUST, 0.5 * (1.0 - t)), 1.2, true)
