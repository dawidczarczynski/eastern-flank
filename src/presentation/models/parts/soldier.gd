## Shared soldier for the infantry squad models (pl_mech_infantry, ru_motor_rifle), soldier v4
## (TASK-085): the squad pivots (SoldierN / Rig, kneelers Kneel + hidden Stand, see
## UnitModels.pose_infantry) and one soldier per pivot – a `SoldierPose` (ANSUR II proportions,
## stances with weight shift and the twist towards the weapon, limbs by two-bone IK, the head bent
## onto the stock when aiming), the anatomical body around it (parts/soldier_body.gd), the kit and
## weapon from the model's `dress` hook, and ambient occlusion from the body's and kit's proxies
## baked into the vertex masks (parts/occlusion_bake.gd). Also the helmet, RPG-7 and weapon
## helpers both kits use. Each soldier is built in metres (x forward, y up, z right, feet on y = 0)
## into one MeshKit per material role (base scale M -> model units); the geometry of a soldier does
## not depend on the faction and is cached per squad slot and posture (ModelParts.cached_meshes).

const Body := preload("res://src/presentation/models/parts/soldier_body.gd")
## Model units per metre (1 unit = 10 m).
const M := 0.1
## Weapon carry (optional 5th value of a layout entry, default READY): the model's `dress` hook
## turns it into the weapon angle (`carry_angle`). Mixed carries keep a squad from looking like
## five copies of one figure (TASK-068).
const READY := SoldierPose.READY
const AIM := SoldierPose.AIM
const LOW := SoldierPose.LOW
## Muzzle angle (rad, + = up) of an aimed and of a low-carried weapon.
const AIM_ANGLE := -0.03
const LOW_ANGLE := -0.85
## Stances of a kit (the model's STANCES): shouldered rifle, RPG on the shoulder, GPMG at the hip.
const RIFLE_STANCE := SoldierPose.RIFLE
const LAUNCHER_STANCE := SoldierPose.LAUNCHER
const HIP_STANCE := SoldierPose.HIP
## Openness (vertex mask g) of a helmet's lip and inner wall.
const HELMET_INSIDE := 0.45
## Material roles, in build order (the uniform camo first).
const ROLES: Array[StringName] = [&"uniform", &"vest", &"skin", &"dark", &"gun", &"accent"]
## Roles of the body itself (the rest is kit and weapons).
const BODY_ROLES: Array[StringName] = [&"uniform", &"skin", &"dark"]
## Roles the ambient occlusion is baked into (body, face, vest and pack); boots, gloves, straps
## and weapons are dark already and keep their masks as built (saves build time).
const AO_ROLES: Array[StringName] = [&"uniform", &"skin", &"vest"]
## Boots, gloves, knee pads, belts and straps: weathered dark paint with mud up to the ankles and
## on a kneeling knee (heights in model units of the unscaled soldier, 0.012 = 12 cm).
const GEAR_PAINT := {
	"color": Color("#2a2b25"),
	"base_roughness": 0.85,
	"metallic": 0.05,
	"wear_amount": 0.25,
	"tint_amount": 0.2,
	"dust_amount": 0.3,
	"mud_height": 0.012,
	"mud_amount": 0.45,
	"streak_amount": 0.0,
	"fade": 0.05,
	"mask_ao": 1.0,
}
## Plate carriers, pouches and packs (in the faction's vest colour): matt nylon, strong per-part
## tint so pouches, pack and carrier separate, worn lighter on the seams, dusty on top.
const VEST_PAINT := {
	"base_roughness": 0.93,
	"metallic": 0.0,
	"wear_amount": 0.12,
	"wear_color": Color("#8a8670"),
	"tint_amount": 0.55,
	"dust_amount": 0.35,
	"mud_height": 0.006,
	"mud_amount": 0.5,
	"streak_amount": 0.0,
	"fade": 0.1,
	"mask_ao": 1.0,
}
## Weapons: dark polymer and phosphated steel, edges worn bright.
const GUN_PAINT := {
	"color": Color("#1d1e1b"),
	"base_roughness": 0.5,
	"metallic": 0.35,
	"wear_amount": 0.6,
	"tint_amount": 0.25,
	"dust_amount": 0.15,
	"mud_height": 0.0,
	"mud_amount": 0.0,
	"streak_amount": 0.0,
	"fade": 0.0,
	"mask_ao": 1.0,
}
## Sleeve patch in the faction colour.
const ACCENT_PAINT := {
	"base_roughness": 0.75,
	"metallic": 0.0,
	"wear_amount": 0.1,
	"tint_amount": 0.05,
	"dust_amount": 0.1,
	"mud_height": 0.0,
	"mud_amount": 0.0,
	"streak_amount": 0.0,
	"fade": 0.05,
	"mask_ao": 1.0,
}


## Materials for the ROLES – all read the vertex masks (AO in COLOR.g): faction uniform camo
## (fabric), weathered vest / gun / gear / accent paints, the skin shader.
static func materials(faction: FactionDefinition) -> Dictionary:
	var id := String(faction.id) if faction != null else "neutral"
	var vest_color := faction.vest_color if faction != null else ModelParts.NEUTRAL_VEST
	var accent_color := faction.color if faction != null else ModelParts.NEUTRAL_ACCENT
	return {
		&"uniform": ModelParts.faction_material(faction, &"uniform"),
		&"vest":
		ModelParts.weathered_paint("soldier:vest:" + id, _with_color(VEST_PAINT, vest_color)),
		&"accent":
		ModelParts.weathered_paint("soldier:accent:" + id, _with_color(ACCENT_PAINT, accent_color)),
		&"skin": ModelParts.skin(),
		&"dark": ModelParts.weathered_paint("soldier:gear", GEAR_PAINT),
		&"gun": ModelParts.weathered_paint("soldier:gun", GUN_PAINT),
	}


static func _with_color(values: Dictionary, color: Color) -> Dictionary:
	var result := values.duplicate()
	result["color"] = color
	return result


## The squad: one "SoldierN" pivot per `layout` entry [x, z, kneeling, kit, carry, yaw] (model
## units; carry and yaw optional), scaled by `soldier_scale` and yawed by `yaw` rad, or by
## ±0.3 rad (TerrainNoise.hash) without one. `stances` = {kit: stance} (default RIFLE_STANCE).
## `dress` is func(k: MeshKits, pose: SoldierPose) -> Array[Vector3]: it adds the kit's helmet,
## armour and weapon around the pose (metres) and returns [left, right] grip points the hands
## close around, optionally followed by the fingers' curl directions [left, right].
static func squad(
	key: String,
	layout: Array,
	soldier_scale: float,
	mats: Dictionary,
	dress: Callable,
	stances: Dictionary
) -> Node3D:
	var g := Node3D.new()
	for i in layout.size():
		var entry: Array = layout[i]
		var kneel: bool = entry[2]
		var s := Node3D.new()
		s.name = "Soldier%d" % i
		s.position = Vector3(entry[0], 0.0, entry[1])
		s.scale = Vector3.ONE * soldier_scale
		s.rotation.y = (
			float(entry[5]) if entry.size() > 5 else (TerrainNoise.hash(i, 3, 1) - 0.5) * 0.6
		)
		g.add_child(s)
		var rig := Node3D.new()
		rig.name = "Rig"
		s.add_child(rig)
		if kneel:
			var kneeling := Node3D.new()
			kneeling.name = "Kneel"
			rig.add_child(kneeling)
			soldier(kneeling, key, mats, entry_pose(entry, i, stances, true), dress)
			var stand := Node3D.new()
			stand.name = "Stand"
			stand.visible = false
			rig.add_child(stand)
			soldier(stand, key, mats, entry_pose(entry, i, stances, false), dress)
		else:
			soldier(rig, key, mats, entry_pose(entry, i, stances, false), dress)
	return g


## Pose of the soldier of layout entry `entry` (slot `index`) in a posture.
static func entry_pose(entry: Array, index: int, stances: Dictionary, kneel: bool) -> SoldierPose:
	var kit: int = entry[3]
	var carry: int = entry[4] if entry.size() > 4 else READY
	return SoldierPose.make(kneel, kit, carry, stances.get(kit, RIFLE_STANCE), index)


## One soldier under `into`: one mesh instance per material role, the geometry (with its baked
## occlusion) cached per kit, carry, posture and – for the relaxed poses – squad slot.
static func soldier(
	into: Node3D, key: String, mats: Dictionary, pose: SoldierPose, dress: Callable
) -> void:
	# Aiming poses do not vary by slot: a kneeler's hidden Stand shares the standing aimer's meshes.
	var slot := -1 if pose.aiming() else pose.slot
	var meshes := ModelParts.cached_meshes(
		"%s:%d:%d:%d:%s" % [key, slot, pose.kit, pose.carry, pose.kneel],
		func() -> Dictionary: return variant_meshes(pose, dress)
	)
	MeshKits.add_meshes(into, meshes, mats)


## The meshes of one soldier ({role: ArrayMesh}) with the occlusion baked into COLOR.g of the
## AO_ROLES (indexed meshes: each shared vertex is baked once).
static func variant_meshes(pose: SoldierPose, dress: Callable) -> Dictionary:
	var meshes := soldier_kits(pose, dress).commit_all(AO_ROLES)
	for role: StringName in meshes:
		if role in AO_ROLES:
			meshes[role] = pose.occluders.bake(meshes[role], M)
	return meshes


## The kits of one soldier: legs, torso, head, the kit from `dress` and the arms reaching its grips.
static func soldier_kits(pose: SoldierPose, dress: Callable) -> MeshKits:
	var k := MeshKits.new(null, Transform3D(Basis.from_scale(Vector3.ONE * M), Vector3.ZERO))
	for role in ROLES:
		k.k(role)
	Body.legs(k, pose)
	Body.torso(k, pose)
	Body.head(k, pose)
	var hands: Array = dress.call(k, pose)
	Body.arms(k, pose, hands, &"dark")
	return k


## Weapon angle (rad, + = up) for a `carry`: READY uses the kit's own angle for the posture
## (`ready_stand` / `ready_kneel`), AIM and LOW are shared.
static func carry_angle(carry: int, kneel: bool, ready_stand: float, ready_kneel: float) -> float:
	match carry:
		AIM:
			return AIM_ANGLE
		LOW:
			return LOW_ANGLE
	return ready_kneel if kneel else ready_stand


# --- Kit helpers ----------------------------------------------------------------------------------


## Posed frame on the torso surface (see Body.on_torso): x outwards, y up the spine.
static func on_torso(pose: SoldierPose, y: float, th: float, out := 0.0) -> Transform3D:
	return Body.on_torso(pose, y, th, out)


## Shell around the torso (armour, cummerbund, belt), see Body.torso_shell.
static func torso_shell(
	kit: MeshKit, pose: SoldierPose, y0: float, y1: float, grow: Vector3, dip := 0.0, levels := 5
) -> void:
	Body.torso_shell(kit, pose, y0, y1, grow, dip, levels)


## Padded shoulder straps (see Body.shoulder_pads).
static func shoulder_pads(kit: MeshKit, pose: SoldierPose, size: Vector3) -> void:
	Body.shoulder_pads(kit, pose, size)


## Helmet shell (uniform camo cover) on the head: a smooth turned shell of `profile`
## (Vector2(radius, y) in metres around the frame's Y, top down, outside then the inner wall),
## stretched by `oval` (x length, z width) – the lip and the inside marked as a cavity –, in the
## frame at `at` (head pivot coordinates) tilted `tilt` rad back; the chin strap; an AO cap
## darkening the face and neck under the rim. Returns the frame (also stored in `pose.helmet`).
static func helmet(
	k: MeshKits, pose: SoldierPose, profile: Array, at: Vector3, tilt: float, oval: Vector2
) -> Transform3D:
	var h := pose.head * Transform3D(Basis(Vector3.BACK, tilt), SoldierPose.HEAD_PIVOT + at)
	pose.helmet = h
	# Outer shell down to the rim, then the lip and the inner wall as a cavity (dark inside).
	var rim := 0
	for i in profile.size():
		if (profile[i] as Vector2).x > (profile[rim] as Vector2).x:
			rim = i
	var shell := k.k(&"uniform")
	shell.loft_rings(oval_rings(h, profile.slice(0, rim + 1), oval, 16), false)
	shell.openness = HELMET_INSIDE
	shell.loft_rings(oval_rings(h, profile.slice(rim), oval, 16), false, false)
	shell.openness = 1.0
	var face := pose.head * Transform3D(Basis.IDENTITY, SoldierPose.HEAD_PIVOT)
	for side: float in [-1.0, 1.0]:
		(
			k
			. k(&"dark")
			. tube(
				[
					h * Vector3(-0.01, 0.0, side * 0.135 * oval.y),
					face * Vector3(0.022, -0.028, side * 0.062),
					face * Vector3(0.042, -0.05, side * 0.03),
					face * Vector3(0.046, -0.054, 0.0),
				],
				0.005,
				4
			)
		)
	# The cap's plane sits inside the shell: the brow under a tilted front rim is shaded too.
	pose.occluders.cap(h * Vector3(0.0, 0.03, 0.0), h.basis.y, 0.15, 1.3)
	return h


## Rings of a smooth turned shell in frame `t`: one ring of `sides` points per `profile` point
## (Vector2(radius, y) around the frame's Y), the radius stretched by `oval` along X and Z.
static func oval_rings(t: Transform3D, profile: Array, oval: Vector2, sides: int) -> Array:
	var loops := []
	for q: Vector2 in profile:
		var loop := []
		for j in sides:
			var a := TAU * j / sides
			loop.append(t * Vector3(cos(a) * q.x * oval.x, q.y, sin(a) * q.x * oval.y))
		loops.append(loop)
	return loops


## Chamfered box at `pos` in the frame `t` (metres), rolled by `roll` rad about the frame's Z.
static func part(
	kit: MeshKit, t: Transform3D, pos: Vector3, size: Vector3, roll := 0.0, b := 0.006
) -> void:
	kit.cbox(t * pos, size, b, t.basis * Basis(Vector3.BACK, roll))


## Turned part along the frame's X (bore axis): `profile` = Vector2(radius, distance along x from
## `x`) from the muzzle end backwards.
static func bore_lathe(
	kit: MeshKit, t: Transform3D, at: Vector3, profile: Array, sides := 8
) -> void:
	kit.lathe(t * at, t.basis * Basis(Vector3.BACK, -PI / 2.0), profile, sides)


## Sling (dark tube) through `points`.
static func sling(k: MeshKits, points: Array) -> void:
	k.k(&"dark").tube(points, 0.007, 4)


## RPG-7 along the X axis of frame `t` (origin = the tube's middle, on the shoulder, see
## SoldierPose.launcher): tube with the heat shield and venturi flare, the conical PG-7 warhead
## (olive, vest colour), two pistol grips and the sight on the left. Returns the [left, right]
## grips and the fingers' curl directions.
static func rpg7(k: MeshKits, t: Transform3D) -> Array[Vector3]:
	var gun := k.k(&"gun")
	bore_lathe(
		gun,
		t,
		Vector3.ZERO,
		[
			Vector2(0.0, 0.46),
			Vector2(0.02, 0.46),
			Vector2(0.02, 0.14),
			Vector2(0.033, 0.13),
			Vector2(0.034, 0.12),
			Vector2(0.034, -0.12),
			Vector2(0.033, -0.13),
			Vector2(0.02, -0.14),
			Vector2(0.02, -0.4),
			Vector2(0.046, -0.54),
			Vector2(0.04, -0.545),
			Vector2(0.0, -0.545),
		],
		12
	)
	pg7(k.k(&"vest"), t.origin, t.basis * Basis(Vector3.BACK, -PI / 2.0))
	part(gun, t, Vector3(0.0, -0.07, 0.0), Vector3(0.03, 0.1, 0.025), -0.25)
	part(gun, t, Vector3(0.2, -0.07, 0.0), Vector3(0.03, 0.1, 0.025), -0.25)
	part(gun, t, Vector3(0.1, 0.04, -0.045), Vector3(0.09, 0.04, 0.03))
	var curl := -t.basis.z
	return [t * Vector3(0.2, -0.115, 0.0), t * Vector3(0.0, -0.115, 0.0), curl, curl]


## PG-7 round on the lathe axis (+Y of `rot`) at `c`: the bulbous warhead with its conical nose
## from 0.45 to 0.82 m, the tail end at 0.45 sits in the launcher's muzzle.
static func pg7(kit: MeshKit, c: Vector3, rot: Basis) -> void:
	(
		kit
		. lathe(
			c,
			rot,
			[
				Vector2(0.0, 0.82),
				Vector2(0.012, 0.78),
				Vector2(0.0425, 0.62),
				Vector2(0.0425, 0.53),
				Vector2(0.022, 0.48),
				Vector2(0.022, 0.45),
				Vector2(0.0, 0.45),
			],
			12
		)
	)
