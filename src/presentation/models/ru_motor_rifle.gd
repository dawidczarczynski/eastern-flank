## Russian motor rifle squad (BMP dismounts in Ratnik kit): five soldiers in EMR (faction uniform
## camo), rounded 6B47 helmets and bulky 6B45 armour with a high collar and front pouches; a
## leader and a kneeling rifleman with AK-74M + GP-30, a standing RPG-7V gunner, a kneeling
## RPK-74M gunner and the assistant grenadier with a rocket carrier. Squad contract: Soldier0..4,
## each with a Rig; kneelers have Kneel + Stand (Stand hidden). The soldier (squad pivots, smooth
## MeshKit body, RPG-7, helpers) is the shared parts/soldier.gd.
## Blueprint: docs/design/units/units/ru_motor_rifle/blueprint.md.

const Soldier := preload("res://src/presentation/models/parts/soldier.gd")
## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.5
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {"squad_march": {}}
## Exaggeration of the soldiers (real 1.80 m -> 3.15 m), the same as the other squads.
const SOLDIER_SCALE := 1.75
const RIFLE := 0
const GP30 := 1
const RPG := 2
const MG := 3
const ASSIST := 4
## Squad layout: [x, z, kneeling, kit, carry, yaw] (Soldier.squad); the leader first, aiming. 5 of
## the 6 dismounts (see blueprint); the assistant carries low and watches the right flank, the
## kneeling rifleman covers the left.
const SQUAD: Array = [
	[0.13, 0.0, false, GP30, Soldier.AIM],
	[-0.03, 0.16, false, RPG],
	[-0.03, -0.15, true, MG],
	[-0.19, 0.06, false, ASSIST, Soldier.LOW, 0.6],
	[-0.16, -0.13, true, GP30, Soldier.AIM, -0.5],
]
## 6B47: rounded full-cut shell, no flared brim, deep over the ears and neck (Vector2(radius, y)
## from the crown base, metres); crown base height and back tilt.
const HELMET: Array[Vector2] = [
	Vector2(0.0, 0.19),
	Vector2(0.08, 0.18),
	Vector2(0.125, 0.15),
	Vector2(0.152, 0.1),
	Vector2(0.165, 0.045),
	Vector2(0.168, 0.0),
	Vector2(0.165, -0.04),
	Vector2(0.158, -0.07),
	Vector2(0.145, -0.075),
	Vector2(0.0, -0.075),
]
const HELMET_BASE := 1.63
const HELMET_TILT := 0.08


static func build(faction: FactionDefinition) -> Node3D:
	var dress := func(
		k: MeshKits, up: Vector3, kit: int, kneel: bool, carry: int
	) -> Array[Vector3]:
		return _dress(k, up, kit, kneel, carry)
	var g := Soldier.squad(
		"ru_motor_rifle", SQUAD, SOLDIER_SCALE, Soldier.materials(faction), dress
	)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## The Ratnik kit on one soldier: 6B47 helmet, 6B45 armour and the weapon of `kit`.
static func _dress(k: MeshKits, up: Vector3, kit: int, kneel: bool, carry: int) -> Array[Vector3]:
	_helmet(k, up)
	_armour(k, up)
	match kit:
		RPG:
			return Soldier.rpg7(k, Soldier.rpg7_shoulder(up))
		MG:
			return _ak(k, _shouldered(up, -0.08 if kneel else -0.35), false, true, kneel)
		ASSIST:
			_rocket_carrier(k, up)
	var angle := Soldier.carry_angle(carry, kneel, -0.4, -0.2)
	return _ak(k, _shouldered(up, angle), kit == GP30, false, false)


## Rifle frame with the butt in the right shoulder, muzzle `angle` rad above level.
static func _shouldered(up: Vector3, angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, angle), up + Soldier.RIFLE_BUTT)


## 6B47 helmet with the EMR cover (uniform camo), the side rails' mounting band and chin strap.
static func _helmet(k: MeshKits, up: Vector3) -> void:
	var h := Soldier.helmet_frame(up, HELMET_BASE, HELMET_TILT)
	Soldier.helmet(k, up, h, HELMET, -0.05)
	k.k(&"dark").lathe(
		h.origin,
		h.basis,
		[Vector2(0.163, 0.05), Vector2(0.17, 0.047), Vector2(0.171, 0.012), Vector2(0.166, 0.009)],
		18
	)


## 6B45 body armour: thick front and back sections, cummerbund, shoulder straps, high collar,
## groin flap, three MOLLE magazine pouches and a side pouch; belt.
static func _armour(k: MeshKits, up: Vector3) -> void:
	var vest := k.k(&"vest")
	var dark := k.k(&"dark")
	vest.pillow(
		up + Vector3(0.12, 1.24, 0.0),
		Vector3(0.1, 0.38, 0.36),
		Basis(Vector3.BACK, -0.04),
		0.3,
		6,
		12
	)
	vest.pillow(
		up + Vector3(-0.125, 1.26, 0.0),
		Vector3(0.09, 0.4, 0.36),
		Basis(Vector3.BACK, 0.04),
		0.3,
		6,
		12
	)
	vest.sweep(
		[up + Vector3(0.0, 1.03, 0.0), up + Vector3(0.005, 1.17, 0.0)],
		[Vector2(0.2, 0.14), Vector2(0.205, 0.145)],
		16
	)
	for side: float in [-1.0, 1.0]:
		(
			vest
			. tube(
				[
					up + Vector3(0.13, 1.41, side * 0.13),
					up + Vector3(0.03, 1.46, side * 0.14),
					up + Vector3(-0.08, 1.45, side * 0.14),
					up + Vector3(-0.14, 1.41, side * 0.13),
				],
				0.028,
				6
			)
		)
	# High collar: a ring around the neck, higher at the back.
	(
		vest
		. lathe(
			up + Vector3(-0.01, 1.39, 0.0),
			Basis(Vector3.BACK, 0.15),
			[
				Vector2(0.088, 0.13),
				Vector2(0.11, 0.125),
				Vector2(0.135, 0.02),
				Vector2(0.13, 0.0),
				Vector2(0.1, 0.0),
				Vector2(0.088, 0.13),
			],
			14
		)
	)
	# Groin flap below the belt.
	vest.pillow(
		up + Vector3(0.15, 0.89, 0.0),
		Vector3(0.05, 0.17, 0.2),
		Basis(Vector3.BACK, 0.12),
		0.35,
		4,
		8
	)
	var tilt := Basis(Vector3.BACK, -0.04)
	for z: float in [-0.11, 0.0, 0.11]:
		vest.cbox(up + Vector3(0.2, 1.13, z), Vector3(0.07, 0.15, 0.09), 0.014, tilt)
		vest.cbox(up + Vector3(0.205, 1.2, z), Vector3(0.075, 0.03, 0.095), 0.008, tilt)
	vest.pillow(
		up + Vector3(-0.02, 1.12, 0.21), Vector3(0.09, 0.13, 0.06), Basis.IDENTITY, 0.45, 4, 8
	)
	dark.sweep(
		[up + Vector3(0.0, 0.95, 0.0), up + Vector3(0.0, 0.99, 0.0)],
		[Vector2(0.178, 0.122), Vector2(0.176, 0.12)],
		16
	)


## AK-74M (or with `rpk` the RPK-74M: longer barrel and magazine, bipod down when `bipod`) in
## frame `t` (origin = butt, x along the bore): stock with the AK drop, receiver, lower
## handguard, gas tube over the barrel, front sight, muzzle brake, curved magazine, pistol grip;
## `gp30` adds the underbarrel grenade launcher. Returns [left, right] hand.
static func _ak(k: MeshKits, t: Transform3D, gp30: bool, rpk: bool, bipod: bool) -> Array[Vector3]:
	var gun := k.k(&"gun")
	var extra := 0.2 if rpk else 0.0
	var u := t.basis.x
	var v := t.basis.y
	var w := t.basis.z
	gun.plate(
		[Vector2(0.0, 0.0), Vector2(0.24, 0.03), Vector2(0.24, -0.02), Vector2(0.0, -0.11)],
		t.origin,
		u,
		v,
		w,
		-0.0175,
		0.0175,
		0.006
	)
	Soldier.part(gun, t, Vector3(0.39, 0.0, 0.0), Vector3(0.3, 0.07, 0.045))
	Soldier.part(gun, t, Vector3(0.63, -0.008, 0.0), Vector3(0.18, 0.055, 0.05))
	Soldier.part(gun, t, Vector3(0.84 + extra, 0.025, 0.0), Vector3(0.03, 0.05, 0.02), 0.0, 0.004)
	Soldier.part(gun, t, Vector3(0.3, -0.08, 0.0), Vector3(0.04, 0.11, 0.03), -0.3)
	gun.rod(t * Vector3(0.66, 0.038, 0.0), u, 0.013, 0.24, 8)
	(
		Soldier
		. bore_lathe(
			gun,
			t,
			Vector3(0.95 + extra, 0.0, 0.0),
			[
				Vector2(0.0, 0.0),
				Vector2(0.016, 0.0),
				Vector2(0.016, -0.07),
				Vector2(0.011, -0.075),
				Vector2(0.011, -0.41 - extra),
			]
		)
	)
	var magazine := _magazine(1.35 if rpk else 1.0)
	gun.plate(magazine, t.origin, u, v, w, -0.015, 0.015, 0.004)
	if gp30:
		gun.rod(t * Vector3(0.69, -0.065, 0.0), u, 0.024, 0.26, 10, 0.004)
		Soldier.part(gun, t, Vector3(0.56, -0.08, 0.0), Vector3(0.09, 0.07, 0.04))
	if rpk:
		# Bipod at the muzzle: legs splayed down, or folded back under the barrel.
		var leg_end := Vector3(1.0, -0.3, 0.07) if bipod else Vector3(0.68, -0.025, 0.012)
		for side: float in [-1.0, 1.0]:
			(
				gun
				. tube(
					[
						t * Vector3(0.95 + extra, -0.015, 0.0),
						t * Vector3(leg_end.x + extra, leg_end.y, leg_end.z * side),
					],
					0.008,
					4
				)
			)
	Soldier.sling(
		k,
		[
			t * Vector3(0.05, -0.06, -0.02),
			t * Vector3(0.3, -0.18, -0.06),
			t * Vector3(0.6, -0.04, -0.03)
		]
	)
	return [t * Vector3(0.62, -0.05, -0.02), t * Vector3(0.29, -0.11, 0.0)]


## Curved (banana) magazine outline in the frame's XY plane, metres; `length` stretches it
## (1.35 = the RPK's 45-round magazine).
static func _magazine(length: float) -> Array:
	var outline := []
	for point: Vector2 in [
		Vector2(0.395, -0.035),
		Vector2(0.465, -0.035),
		Vector2(0.475, -0.09),
		Vector2(0.5, -0.15),
		Vector2(0.535, -0.205),
		Vector2(0.475, -0.235),
		Vector2(0.445, -0.17),
		Vector2(0.415, -0.11),
	]:
		var below := -0.035 - point.y
		var curl := (point.x - 0.395) * (length - 1.0)
		outline.append(Vector2(point.x + curl, -0.035 - below * length))
	return outline


## The assistant grenadier's rocket carrier (EMR bag) with three PG-7 warheads standing out.
static func _rocket_carrier(k: MeshKits, up: Vector3) -> void:
	k.k(&"uniform").pillow(
		up + Vector3(-0.27, 1.22, 0.0), Vector3(0.16, 0.34, 0.3), Basis.IDENTITY, 0.35, 6, 12
	)
	for z: float in [-0.09, 0.0, 0.09]:
		var origin := up + Vector3(-0.27 + absf(z) * 0.2, 0.86 - absf(z) * 0.3, z)
		Soldier.pg7(k.k(&"vest"), origin, Basis(Vector3.BACK, 0.12))
	for z: float in [-0.08, 0.08]:
		k.k(&"dark").tube(
			[up + Vector3(-0.19, 1.4, z), up + Vector3(-0.14, 1.44, z * 1.4)], 0.012, 4
		)
