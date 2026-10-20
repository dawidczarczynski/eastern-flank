## Polish mechanised infantry squad (12th Mechanized Brigade dismounts, current kit): five
## soldiers in wz. 93 Pantera (faction uniform camo), wz. 2005 PASGT-like helmets, plate carriers
## with front pouches and assault packs; three MSBS Grot C riflemen, a kneeling RPG-7 gunner and a
## UKM-2000 machine gunner. Squad contract: Soldier0..4, each with a Rig; kneelers have Kneel +
## Stand (Stand hidden). Blueprint: docs/design/units/units/pl_mech_infantry/blueprint.md.
## The skeleton (squad pivots, legs, body, arms, RPG-7) is the shared parts/soldier.gd; this file
## adds the Polish kit. SOLDIER_SCALE exaggerates the real 1.82 m so the squad reads at game zoom.

const Soldier := preload("res://src/presentation/models/parts/soldier.gd")
## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.5
## Exaggeration of the soldiers (real 1.82 m -> 3.2 m), the same on-screen size as the generic
## infantry squad (TASK-031); at true scale a soldier would be 0.24 world units on a 1.0 hex.
const SOLDIER_SCALE := 1.75
const RIFLE := 0
const RPG := 1
const MG := 2
## Squad layout: [x, z, kneeling, kit]; front rifleman first.
const SQUAD: Array = [
	[0.12, 0.0, false, RIFLE],
	[-0.03, 0.15, true, RPG],
	[-0.04, -0.15, false, MG],
	[-0.19, 0.06, false, RIFLE],
	[-0.16, -0.13, true, RIFLE],
]


static func build(faction: FactionDefinition) -> Node3D:
	var dress := func(parts: Dictionary, up: Vector3, kit: int, kneel: bool) -> Array[Vector3]:
		return _dress(parts, up, kit, kneel)
	return Soldier.squad(
		"pl_mech_infantry", SQUAD, SOLDIER_SCALE, Soldier.materials(faction), dress
	)


## The Polish kit on one soldier: plate carrier, pack, helmet and the weapon of `kit`.
static func _dress(parts: Dictionary, up: Vector3, kit: int, kneel: bool) -> Array[Vector3]:
	_gear(parts, up)
	match kit:
		RPG:
			return Soldier.rpg7(parts, Soldier.rpg7_shoulder(up))
		MG:
			return _mg(parts, up)
		_:
			return _rifle(parts, up, -0.25 if kneel else -0.45)


## Plate carrier with front pouches, assault pack and the wz. 2005 helmet.
static func _gear(parts: Dictionary, up: Vector3) -> void:
	# Plate carrier (KKZ-01): bulky front/back plates, cummerbund, a row of front pouches.
	Soldier.box(parts, &"vest", Vector3(0.32, 0.38, 0.4), Soldier.at(up + Vector3(0.02, 1.26, 0.0)))
	Soldier.box(
		parts, &"vest", Vector3(0.08, 0.14, 0.34), Soldier.at(up + Vector3(0.21, 1.15, 0.0))
	)
	Soldier.box(parts, &"vest", Vector3(0.28, 0.07, 0.37), Soldier.at(up + Vector3(0.0, 1.0, 0.0)))
	# Assault pack with a lid.
	Soldier.box(
		parts, &"vest", Vector3(0.14, 0.3, 0.27), Soldier.at(up + Vector3(-0.23, 1.25, 0.0))
	)
	Soldier.box(
		parts, &"vest", Vector3(0.16, 0.05, 0.28), Soldier.at(up + Vector3(-0.225, 1.4, 0.0))
	)
	# PASGT-like helmet: dome flaring into a short brim, lower over the ears and neck; tilted
	# back so the front edge clears the eyes.
	var profile: Array[Vector2] = [
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
	Soldier.helmet(parts, "pl_mech_infantry:helmet", up, profile, 1.635, 0.16)


## MSBS Grot C at the ready: butt in the right shoulder, muzzle `angle` rad below level. Long
## top rail over receiver and handguard, red-dot sight, polymer stock. Returns [left, right] hand.
static func _rifle(parts: Dictionary, up: Vector3, angle: float) -> Array[Vector3]:
	var t := Transform3D(Basis(Vector3.BACK, angle), up + Soldier.RIFLE_BUTT)
	Soldier.box(parts, &"gun", Vector3(0.24, 0.09, 0.04), Soldier.on(t, Vector3(0.12, -0.03, 0.0)))
	Soldier.box(parts, &"gun", Vector3(0.3, 0.07, 0.05), Soldier.on(t, Vector3(0.37, 0.0, 0.0)))
	Soldier.box(
		parts, &"gun", Vector3(0.54, 0.022, 0.032), Soldier.on(t, Vector3(0.48, 0.045, 0.0))
	)
	Soldier.box(parts, &"gun", Vector3(0.26, 0.06, 0.05), Soldier.on(t, Vector3(0.65, -0.005, 0.0)))
	Soldier.box(parts, &"gun", Vector3(0.07, 0.05, 0.032), Soldier.on(t, Vector3(0.38, 0.08, 0.0)))
	Soldier.box(
		parts, &"gun", Vector3(0.06, 0.17, 0.028), Soldier.on(t, Vector3(0.44, -0.11, 0.0), 0.2)
	)
	Soldier.box(
		parts, &"gun", Vector3(0.04, 0.11, 0.03), Soldier.on(t, Vector3(0.3, -0.08, 0.0), -0.3)
	)
	Soldier.rod(parts, &"gun", t * Vector3(0.78, 0.0, 0.0), t * Vector3(0.9, 0.0, 0.0), 0.011)
	Soldier.rod(parts, &"gun", t * Vector3(0.88, 0.0, 0.0), t * Vector3(0.93, 0.0, 0.0), 0.017)
	return [t * Vector3(0.62, -0.06, -0.02), t * Vector3(0.29, -0.11, 0.0)]


## UKM-2000 carried at the hip: long barrel, folded bipod, ammunition box on the left.
static func _mg(parts: Dictionary, up: Vector3) -> Array[Vector3]:
	var t := Transform3D(Basis(Vector3.BACK, 0.05), up + Vector3(-0.12, 1.1, 0.22))
	Soldier.box(parts, &"gun", Vector3(0.26, 0.11, 0.045), Soldier.on(t, Vector3(0.13, -0.03, 0.0)))
	Soldier.box(parts, &"gun", Vector3(0.36, 0.1, 0.07), Soldier.on(t, Vector3(0.44, 0.0, 0.0)))
	Soldier.box(parts, &"gun", Vector3(0.22, 0.025, 0.045), Soldier.on(t, Vector3(0.42, 0.06, 0.0)))
	Soldier.box(
		parts, &"gun", Vector3(0.04, 0.11, 0.035), Soldier.on(t, Vector3(0.3, -0.09, 0.0), -0.3)
	)
	Soldier.box(
		parts, &"gun", Vector3(0.14, 0.025, 0.025), Soldier.on(t, Vector3(0.68, 0.065, 0.0))
	)
	Soldier.box(
		parts, &"gun", Vector3(0.4, 0.018, 0.035), Soldier.on(t, Vector3(0.86, -0.045, 0.0))
	)
	Soldier.rod(parts, &"gun", t * Vector3(0.62, 0.0, 0.0), t * Vector3(1.14, 0.0, 0.0), 0.014)
	Soldier.rod(
		parts, &"gun", t * Vector3(0.62, -0.025, 0.0), t * Vector3(0.95, -0.025, 0.0), 0.009
	)
	Soldier.rod(parts, &"gun", t * Vector3(1.13, 0.0, 0.0), t * Vector3(1.2, 0.0, 0.0), 0.02)
	Soldier.box(
		parts, &"vest", Vector3(0.12, 0.14, 0.09), Soldier.on(t, Vector3(0.47, -0.1, -0.075))
	)
	return [t * Vector3(0.6, -0.04, -0.03), t * Vector3(0.29, -0.12, 0.0)]
