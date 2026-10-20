## Russian motor rifle squad (BMP dismounts in Ratnik kit): five soldiers in EMR (faction uniform
## camo), rounded 6B47 helmets and bulky 6B45 armour with a high collar and front pouches; a
## leader and a kneeling rifleman with AK-74M + GP-30, a standing RPG-7V gunner, a kneeling
## RPK-74M gunner and the assistant grenadier with a rocket carrier. Squad contract: Soldier0..4,
## each with a Rig; kneelers have Kneel + Stand (Stand hidden). The skeleton is the shared
## parts/soldier.gd. Blueprint: docs/design/units/units/ru_motor_rifle/blueprint.md.

const Soldier := preload("res://src/presentation/models/parts/soldier.gd")
## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.5
## Exaggeration of the soldiers (real 1.80 m -> 3.15 m), the same as the other squads.
const SOLDIER_SCALE := 1.75
const RIFLE := 0
const GP30 := 1
const RPG := 2
const MG := 3
const ASSIST := 4
## Squad layout: [x, z, kneeling, kit]; the leader first. 5 of the 6 dismounts (see blueprint).
const SQUAD: Array = [
	[0.13, 0.0, false, GP30],
	[-0.03, 0.16, false, RPG],
	[-0.03, -0.15, true, MG],
	[-0.19, 0.06, false, ASSIST],
	[-0.16, -0.13, true, GP30],
]


static func build(faction: FactionDefinition) -> Node3D:
	var dress := func(parts: Dictionary, up: Vector3, kit: int, kneel: bool) -> Array[Vector3]:
		return _dress(parts, up, kit, kneel)
	return Soldier.squad("ru_motor_rifle", SQUAD, SOLDIER_SCALE, Soldier.materials(faction), dress)


## The Ratnik kit on one soldier: 6B45 armour, 6B47 helmet and the weapon of `kit`.
static func _dress(parts: Dictionary, up: Vector3, kit: int, kneel: bool) -> Array[Vector3]:
	_armour(parts, up)
	match kit:
		RPG:
			return Soldier.rpg7(parts, Soldier.rpg7_shoulder(up))
		MG:
			return _ak(parts, _shouldered(up, -0.08 if kneel else -0.35), false, true, kneel)
		ASSIST:
			_rocket_carrier(parts, up)
	return _ak(parts, _shouldered(up, -0.2 if kneel else -0.4), kit == GP30, false, false)


## Rifle frame with the butt in the right shoulder, muzzle `angle` rad above level.
static func _shouldered(up: Vector3, angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, angle), up + Soldier.RIFLE_BUTT)


## 6B45 body armour (bulky, high collar, groin flap, MOLLE magazine pouches) and the 6B47 helmet.
static func _armour(parts: Dictionary, up: Vector3) -> void:
	Soldier.box(parts, &"vest", Vector3(0.36, 0.4, 0.42), Soldier.at(up + Vector3(0.02, 1.21, 0.0)))
	Soldier.box(parts, &"vest", Vector3(0.32, 0.08, 0.42), Soldier.at(up + Vector3(0.0, 0.99, 0.0)))
	Soldier.box(parts, &"vest", Vector3(0.05, 0.16, 0.2), Soldier.at(up + Vector3(0.15, 0.89, 0.0)))
	for z: float in [-0.12, 0.0, 0.12]:
		Soldier.box(
			parts, &"vest", Vector3(0.08, 0.15, 0.1), Soldier.at(up + Vector3(0.22, 1.14, z))
		)
	# High collar around the neck.
	Soldier.rod(
		parts,
		&"vest",
		up + Vector3(-0.01, 1.37, 0.0),
		up + Vector3(-0.01, 1.53, 0.0),
		0.14,
		0.12,
		10
	)
	# 6B47: rounded full-cut shell, no flared brim, deep over the ears and neck.
	var profile: Array[Vector2] = [
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
	Soldier.helmet(parts, "ru_motor_rifle:6b47", up, profile, 1.63, 0.08)


## AK-74M (or with `rpk` the RPK-74M: longer barrel and magazine, bipod down when `bipod`) in
## frame `t` (origin = butt, x along the bore): stock with the AK drop, receiver, lower
## handguard, gas tube over the barrel, front sight, muzzle brake, curved magazine, pistol grip;
## `gp30` adds the underbarrel grenade launcher. Returns [left, right] hand.
static func _ak(
	parts: Dictionary, t: Transform3D, gp30: bool, rpk: bool, bipod: bool
) -> Array[Vector3]:
	var extra := 0.2 if rpk else 0.0
	var stock: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(0.24, 0.03), Vector2(0.24, -0.02), Vector2(0.0, -0.11)
	]
	Soldier.put(
		parts,
		&"gun",
		ModelParts.prism_mesh("ru_motor_rifle:ak_stock", Soldier.scaled(stock), 0.0035),
		t
	)
	Soldier.box(parts, &"gun", Vector3(0.3, 0.07, 0.045), Soldier.on(t, Vector3(0.39, 0.0, 0.0)))
	Soldier.box(
		parts, &"gun", Vector3(0.18, 0.055, 0.05), Soldier.on(t, Vector3(0.63, -0.008, 0.0))
	)
	Soldier.rod(parts, &"gun", t * Vector3(0.54, 0.038, 0.0), t * Vector3(0.78, 0.038, 0.0), 0.013)
	Soldier.rod(
		parts, &"gun", t * Vector3(0.54, 0.0, 0.0), t * Vector3(0.9 + extra, 0.0, 0.0), 0.011
	)
	Soldier.rod(
		parts,
		&"gun",
		t * Vector3(0.88 + extra, 0.0, 0.0),
		t * Vector3(0.95 + extra, 0.0, 0.0),
		0.016
	)
	Soldier.box(
		parts, &"gun", Vector3(0.03, 0.05, 0.02), Soldier.on(t, Vector3(0.84 + extra, 0.025, 0.0))
	)
	Soldier.box(
		parts, &"gun", Vector3(0.04, 0.11, 0.03), Soldier.on(t, Vector3(0.3, -0.08, 0.0), -0.3)
	)
	var mag := _magazine(1.35 if rpk else 1.0)
	var mag_key := "ru_motor_rifle:mag:%s" % rpk
	Soldier.put(parts, &"gun", ModelParts.prism_mesh(mag_key, mag, 0.003), t)
	if gp30:
		Soldier.rod(
			parts, &"gun", t * Vector3(0.56, -0.065, 0.0), t * Vector3(0.82, -0.065, 0.0), 0.024
		)
		Soldier.box(
			parts, &"gun", Vector3(0.09, 0.07, 0.04), Soldier.on(t, Vector3(0.56, -0.08, 0.0))
		)
	if rpk:
		# Bipod at the muzzle: legs splayed down, or folded back under the barrel.
		var leg_end := Vector3(1.0, -0.3, 0.07) if bipod else Vector3(0.68, -0.025, 0.012)
		for side: float in [-1.0, 1.0]:
			var end := t * Vector3(leg_end.x + extra, leg_end.y, leg_end.z * side)
			Soldier.rod(parts, &"gun", t * Vector3(0.95 + extra, -0.015, 0.0), end, 0.008)
	return [t * Vector3(0.62, -0.05, -0.02), t * Vector3(0.29, -0.11, 0.0)]


## Curved (banana) magazine outline in the frame's XY plane, model units; `length` stretches it
## (1.35 = the RPK's 45-round magazine).
static func _magazine(length: float) -> Array[Vector2]:
	var outline: Array[Vector2] = []
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
		outline.append(Vector2(point.x + curl, -0.035 - below * length) * Soldier.M)
	return outline


## The assistant grenadier's rocket carrier (EMR bag) with three PG-7 warheads standing out.
static func _rocket_carrier(parts: Dictionary, up: Vector3) -> void:
	Soldier.box(
		parts, &"uniform", Vector3(0.16, 0.34, 0.3), Soldier.at(up + Vector3(-0.27, 1.22, 0.0))
	)
	var warhead := ModelParts.lathe_mesh("soldier:pg7", Soldier.pg7_profile(), 12)
	for z: float in [-0.09, 0.0, 0.09]:
		var origin := up + Vector3(-0.27 + absf(z) * 0.2, 0.86 - absf(z) * 0.3, z)
		Soldier.put(parts, &"vest", warhead, Transform3D(Basis(Vector3.BACK, 0.12), origin))
