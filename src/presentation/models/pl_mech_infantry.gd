## Polish mechanised infantry squad (12th Mechanized Brigade dismounts, current kit): five
## soldiers in wz. 93 Pantera (faction uniform camo), wz. 2005 PASGT-like helmets, plate carriers
## with front pouches and assault packs; three MSBS Grot C riflemen, a kneeling RPG-7 gunner and a
## UKM-2000 machine gunner. Squad contract: Soldier0..4, each with a Rig; kneelers have Kneel +
## Stand (Stand hidden). Blueprint: docs/design/units/units/pl_mech_infantry/blueprint.md.
## The soldier (squad pivots, smooth MeshKit body, RPG-7, helpers) is the shared parts/soldier.gd;
## this file adds the Polish kit. SOLDIER_SCALE exaggerates the real 1.82 m so the squad reads at
## game zoom.

const Soldier := preload("res://src/presentation/models/parts/soldier.gd")
## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.5
## Exaggeration of the soldiers (real 1.82 m -> 3.2 m), the same on-screen size as the generic
## infantry squad (TASK-031); at true scale a soldier would be 0.24 world units on a 1.0 hex.
const SOLDIER_SCALE := 1.75
const RIFLE := 0
const RPG := 1
const MG := 2
## Squad layout: [x, z, kneeling, kit, carry, yaw] (Soldier.squad); front rifleman first, aiming;
## the rear rifleman carries low and watches the right flank, the kneeling one covers the left.
const SQUAD: Array = [
	[0.12, 0.0, false, RIFLE, Soldier.AIM],
	[-0.03, 0.15, true, RPG],
	[-0.04, -0.15, false, MG],
	[-0.19, 0.06, false, RIFLE, Soldier.LOW, 0.7],
	[-0.16, -0.13, true, RIFLE, Soldier.AIM, -0.5],
]
## wz. 2005 helmet (PASGT-like): dome flaring into a short brim, lower over the ears and neck
## (Vector2(radius, y) from the crown base, metres); crown base height and back tilt.
const HELMET: Array[Vector2] = [
	Vector2(0.0, 0.175),
	Vector2(0.07, 0.163),
	Vector2(0.112, 0.135),
	Vector2(0.138, 0.09),
	Vector2(0.15, 0.04),
	Vector2(0.155, 0.0),
	Vector2(0.165, -0.035),
	Vector2(0.172, -0.05),
	Vector2(0.15, -0.055),
	Vector2(0.0, -0.055),
]
const HELMET_BASE := 1.635
const HELMET_TILT := 0.16


static func build(faction: FactionDefinition) -> Node3D:
	var dress := func(
		k: MeshKits, up: Vector3, kit: int, kneel: bool, carry: int
	) -> Array[Vector3]:
		return _dress(k, up, kit, kneel, carry)
	return Soldier.squad(
		"pl_mech_infantry", SQUAD, SOLDIER_SCALE, Soldier.materials(faction), dress
	)


## The Polish kit on one soldier: helmet, plate carrier, pack and the weapon of `kit`.
static func _dress(k: MeshKits, up: Vector3, kit: int, kneel: bool, carry: int) -> Array[Vector3]:
	_helmet(k, up)
	_carrier(k, up)
	_pack(k, up)
	match kit:
		RPG:
			return Soldier.rpg7(k, Soldier.rpg7_shoulder(up))
		MG:
			return _mg(k, up)
	return _rifle(k, up, Soldier.carry_angle(carry, kneel, -0.45, -0.25))


## wz. 2005 helmet with the Pantera cover (uniform camo), elastic band, NVG shroud, chin strap and
## ballistic glasses.
static func _helmet(k: MeshKits, up: Vector3) -> void:
	var h := Soldier.helmet_frame(up, HELMET_BASE, HELMET_TILT)
	Soldier.helmet(k, up, h, HELMET, -0.03)
	var dark := k.k(&"dark")
	dark.lathe(
		h.origin,
		h.basis,
		[Vector2(0.149, 0.06), Vector2(0.155, 0.057), Vector2(0.157, 0.04), Vector2(0.151, 0.037)],
		18
	)
	dark.cbox(
		h * Vector3(0.14, 0.09, 0.0),
		Vector3(0.03, 0.05, 0.06),
		0.008,
		h.basis.rotated(Vector3.BACK, -0.6)
	)
	var c := up + Soldier.HEAD
	k.k(&"gun").cbox(
		c + Vector3(0.085, 0.022, 0.0), Vector3(0.03, 0.035, 0.15), 0.008, Basis(Vector3.BACK, 0.1)
	)


## KKZ plate carrier: front and back plates, cummerbund, shoulder straps, three magazine pouches,
## radio and IFAK on the sides, belt with buckle.
static func _carrier(k: MeshKits, up: Vector3) -> void:
	var vest := k.k(&"vest")
	var dark := k.k(&"dark")
	vest.pillow(
		up + Vector3(0.11, 1.26, 0.0),
		Vector3(0.075, 0.34, 0.33),
		Basis(Vector3.BACK, -0.05),
		0.3,
		6,
		12
	)
	vest.pillow(
		up + Vector3(-0.115, 1.28, 0.0),
		Vector3(0.07, 0.36, 0.33),
		Basis(Vector3.BACK, 0.04),
		0.3,
		6,
		12
	)
	vest.sweep(
		[up + Vector3(0.0, 1.07, 0.0), up + Vector3(0.005, 1.18, 0.0)],
		[Vector2(0.185, 0.13), Vector2(0.19, 0.135)],
		16
	)
	for side: float in [-1.0, 1.0]:
		(
			vest
			. tube(
				[
					up + Vector3(0.12, 1.42, side * 0.12),
					up + Vector3(0.03, 1.47, side * 0.13),
					up + Vector3(-0.08, 1.46, side * 0.13),
					up + Vector3(-0.13, 1.42, side * 0.12),
				],
				0.022,
				6
			)
		)
	var tilt := Basis(Vector3.BACK, -0.05)
	for z: float in [-0.085, 0.0, 0.085]:
		vest.cbox(up + Vector3(0.165, 1.15, z), Vector3(0.05, 0.12, 0.075), 0.012, tilt)
		vest.cbox(up + Vector3(0.17, 1.2, z), Vector3(0.055, 0.025, 0.08), 0.008, tilt)
	# Radio (left) and IFAK (right) pouches.
	vest.pillow(
		up + Vector3(-0.02, 1.2, -0.2), Vector3(0.09, 0.16, 0.05), Basis.IDENTITY, 0.45, 4, 8
	)
	vest.pillow(
		up + Vector3(-0.03, 1.17, 0.2), Vector3(0.08, 0.12, 0.05), Basis.IDENTITY, 0.45, 4, 8
	)
	dark.sweep(
		[up + Vector3(0.0, 0.96, 0.0), up + Vector3(0.0, 1.0, 0.0)],
		[Vector2(0.178, 0.122), Vector2(0.176, 0.12)],
		16
	)
	dark.cbox(up + Vector3(0.12, 0.98, 0.0), Vector3(0.02, 0.04, 0.05), 0.006)


## Assault pack with lid, compression straps and a side bottle.
static func _pack(k: MeshKits, up: Vector3) -> void:
	var vest := k.k(&"vest")
	var dark := k.k(&"dark")
	vest.pillow(
		up + Vector3(-0.24, 1.25, 0.0), Vector3(0.15, 0.32, 0.27), Basis.IDENTITY, 0.35, 6, 12
	)
	vest.pillow(
		up + Vector3(-0.235, 1.4, 0.0), Vector3(0.17, 0.07, 0.28), Basis.IDENTITY, 0.4, 4, 12
	)
	for z: float in [-0.08, 0.08]:
		dark.tube(
			[
				up + Vector3(-0.32, 1.38, z),
				up + Vector3(-0.325, 1.2, z),
				up + Vector3(-0.31, 1.12, z)
			],
			0.008,
			4
		)
	(
		dark
		. lathe(
			up + Vector3(-0.24, 1.17, 0.16),
			Basis.IDENTITY,
			[
				Vector2(0.0, 0.09),
				Vector2(0.02, 0.09),
				Vector2(0.035, 0.07),
				Vector2(0.035, -0.07),
				Vector2(0.0, -0.07),
			],
			8
		)
	)


## MSBS Grot C at the ready: butt in the right shoulder, muzzle `angle` rad below level. Polymer
## stock, receiver, long top rail, handguard, magazine, pistol grip, round barrel with the muzzle
## device, red-dot tube and a sling. Returns [left, right] hand.
static func _rifle(k: MeshKits, up: Vector3, angle: float) -> Array[Vector3]:
	var gun := k.k(&"gun")
	var t := Transform3D(Basis(Vector3.BACK, angle), up + Soldier.RIFLE_BUTT)
	Soldier.part(gun, t, Vector3(0.12, -0.03, 0.0), Vector3(0.24, 0.09, 0.04))
	Soldier.part(gun, t, Vector3(0.37, 0.0, 0.0), Vector3(0.3, 0.07, 0.05))
	Soldier.part(gun, t, Vector3(0.48, 0.045, 0.0), Vector3(0.54, 0.022, 0.032), 0.0, 0.004)
	Soldier.part(gun, t, Vector3(0.65, -0.005, 0.0), Vector3(0.26, 0.06, 0.05))
	Soldier.part(gun, t, Vector3(0.44, -0.11, 0.0), Vector3(0.06, 0.17, 0.028), 0.2)
	Soldier.part(gun, t, Vector3(0.3, -0.08, 0.0), Vector3(0.04, 0.11, 0.03), -0.3)
	(
		Soldier
		. bore_lathe(
			gun,
			t,
			Vector3(0.86, 0.0, 0.0),
			[
				Vector2(0.0, 0.07),
				Vector2(0.017, 0.07),
				Vector2(0.017, 0.02),
				Vector2(0.011, 0.01),
				Vector2(0.011, -0.09),
			]
		)
	)
	Soldier.bore_lathe(
		gun,
		t,
		Vector3(0.38, 0.09, 0.0),
		[Vector2(0.0, 0.05), Vector2(0.02, 0.05), Vector2(0.02, -0.05), Vector2(0.0, -0.05)]
	)
	Soldier.sling(
		k,
		[
			t * Vector3(0.02, -0.06, -0.025),
			up + Vector3(0.1, 1.2, -0.17),
			t * Vector3(0.7, -0.03, -0.03)
		]
	)
	return [t * Vector3(0.62, -0.06, -0.02), t * Vector3(0.29, -0.11, 0.0)]


## UKM-2000 carried at the hip: stock, receiver, feed cover, carrying handle, long barrel with the
## flash hider and gas block, folded bipod, olive ammunition box on the left, sling over the
## shoulder.
static func _mg(k: MeshKits, up: Vector3) -> Array[Vector3]:
	var gun := k.k(&"gun")
	var t := Transform3D(Basis(Vector3.BACK, 0.05), up + Vector3(-0.12, 1.1, 0.22))
	Soldier.part(gun, t, Vector3(0.13, -0.03, 0.0), Vector3(0.26, 0.11, 0.045))
	Soldier.part(gun, t, Vector3(0.44, 0.0, 0.0), Vector3(0.36, 0.1, 0.07))
	Soldier.part(gun, t, Vector3(0.42, 0.06, 0.0), Vector3(0.22, 0.025, 0.045), 0.0, 0.004)
	Soldier.part(gun, t, Vector3(0.3, -0.09, 0.0), Vector3(0.04, 0.11, 0.035), -0.3)
	Soldier.part(gun, t, Vector3(0.68, 0.065, 0.0), Vector3(0.14, 0.025, 0.025), 0.0, 0.004)
	(
		Soldier
		. bore_lathe(
			gun,
			t,
			Vector3(0.9, 0.0, 0.0),
			[
				Vector2(0.0, 0.3),
				Vector2(0.02, 0.3),
				Vector2(0.02, 0.24),
				Vector2(0.014, 0.23),
				Vector2(0.014, -0.28),
			]
		)
	)
	Soldier.bore_lathe(
		gun,
		t,
		Vector3(0.76, 0.025, 0.0),
		[Vector2(0.0, 0.03), Vector2(0.028, 0.03), Vector2(0.028, -0.06), Vector2(0.0, -0.06)]
	)
	for s: float in [-1.0, 1.0]:
		gun.tube([t * Vector3(0.95, -0.02, s * 0.012), t * Vector3(0.6, -0.04, s * 0.02)], 0.007, 4)
	Soldier.part(k.k(&"vest"), t, Vector3(0.47, -0.1, -0.075), Vector3(0.12, 0.14, 0.09), 0.0, 0.02)
	(
		Soldier
		. sling(
			k,
			[
				t * Vector3(0.05, 0.0, -0.03),
				up + Vector3(0.12, 1.42, 0.14),
				up + Vector3(-0.1, 1.44, -0.14),
				t * Vector3(0.7, 0.02, -0.04),
			]
		)
	)
	return [t * Vector3(0.6, -0.04, -0.03), t * Vector3(0.29, -0.12, 0.0)]
