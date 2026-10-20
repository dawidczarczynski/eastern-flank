## Shared soldier skeleton for the infantry squad models (pl_mech_infantry, ru_motor_rifle): the
## squad pivots (SoldierN / Rig, kneelers Kneel + hidden Stand, see UnitModels.pose_infantry),
## legs, hips, torso, head and arms, plus the RPG-7 both kits carry. The kit-specific pieces
## (helmet, armour, pack, weapons) come from the model's `dress` hook.
## Each soldier is built in metres (x forward, y up, z right, feet on y = 0) and merged into one
## mesh per material, cached by "<key>:<kit>:<kneel>:<role>".

const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
## Model units per metre (1 unit = 10 m).
const M := 0.1
## Hip height standing / kneeling (m): the upper body drops by the difference when kneeling.
const HIP := 0.92
const HIP_KNEEL := 0.55
## Rifle butt in the right shoulder (m, before the kneeling `up` offset).
const RIFLE_BUTT := Vector3(0.12, 1.34, 0.11)
## Merged-mesh material roles, in build order.
const ROLES: Array[StringName] = [&"uniform", &"vest", &"skin", &"dark", &"gun", &"accent"]


## Materials for the ROLES: faction uniform camo, vest colour and accent, PBR skin / dark / gun.
static func materials(faction: FactionDefinition) -> Dictionary:
	return {
		&"uniform": ModelParts.faction_material(faction, &"uniform"),
		&"vest": ModelParts.vest(faction),
		&"accent": ModelParts.accent(faction),
		&"skin": ModelParts.pbr(ModelParts.SKIN),
		&"dark": ModelParts.pbr(ModelParts.DARK),
		&"gun": ModelParts.pbr(ModelParts.GUN),
	}


## The squad: one "SoldierN" pivot per `layout` entry [x, z, kneeling, kit] (model units),
## scaled by `soldier_scale` and yawed by ±0.3 rad (TerrainNoise.hash). `dress` is
## func(parts: Dictionary, up: Vector3, kit: int, kneel: bool) -> Array[Vector3]: it adds the
## kit's helmet, armour and weapon (metres, upper body offset by `up`) and returns the
## [left, right] hand positions the arms reach for.
static func squad(
	key: String, layout: Array, soldier_scale: float, mats: Dictionary, dress: Callable
) -> Node3D:
	var g := Node3D.new()
	for i in layout.size():
		var entry: Array = layout[i]
		var kneel: bool = entry[2]
		var kit: int = entry[3]
		var s := Node3D.new()
		s.name = "Soldier%d" % i
		s.position = Vector3(entry[0], 0.0, entry[1])
		s.scale = Vector3.ONE * soldier_scale
		s.rotation.y = (TerrainNoise.hash(i, 3, 1) - 0.5) * 0.6
		g.add_child(s)
		var rig := Node3D.new()
		rig.name = "Rig"
		s.add_child(rig)
		if kneel:
			var kneeling := Node3D.new()
			kneeling.name = "Kneel"
			rig.add_child(kneeling)
			soldier(kneeling, key, mats, true, kit, dress)
			var stand := Node3D.new()
			stand.name = "Stand"
			stand.visible = false
			rig.add_child(stand)
			soldier(stand, key, mats, false, kit, dress)
		else:
			soldier(rig, key, mats, false, kit, dress)
	return g


## One soldier under `into`: legs, body, the kit from `dress` and the arms reaching its grips;
## one merged mesh per material role.
static func soldier(
	into: Node3D, key: String, mats: Dictionary, kneel: bool, kit: int, dress: Callable
) -> void:
	var parts := {}
	legs(parts, kneel)
	var up := Vector3(0.04, HIP_KNEEL - HIP, 0.0) if kneel else Vector3.ZERO
	body(parts, up)
	var hands: Array[Vector3] = dress.call(parts, up, kit, kneel)
	arms(parts, up, hands)
	for role in ROLES:
		if parts.has(role):
			var mesh_key := "%s:%d:%s:%s" % [key, kit, kneel, role]
			ModelParts.add(
				into, ModelParts.merged_mesh(mesh_key, parts[role]), mats[role], Vector3.ZERO
			)


## Legs and boots; the lowest point (boot soles, kneeling knee) is y = 0.
static func legs(parts: Dictionary, kneel: bool) -> void:
	if kneel:
		# Left knee up, right knee on the ground, right foot behind on its toes.
		var hl := Vector3(0.0, HIP_KNEEL, -0.1)
		var kl := Vector3(0.44, 0.55, -0.12)
		var al := Vector3(0.42, 0.12, -0.13)
		leg(parts, hl, kl, al)
		box(parts, &"dark", Vector3(0.27, 0.11, 0.1), at(al + Vector3(0.06, -0.065, 0.0)))
		var hr := Vector3(0.0, HIP_KNEEL, 0.1)
		var kr := Vector3(0.06, 0.08, 0.12)
		var ar := Vector3(-0.36, 0.16, 0.13)
		leg(parts, hr, kr, ar)
		box(
			parts,
			&"dark",
			Vector3(0.25, 0.1, 0.1),
			Transform3D(Basis(Vector3.BACK, -0.75), Vector3(-0.38, 0.13, 0.13))
		)
		return
	for side: float in [-1.0, 1.0]:
		var stride := -side * 0.06
		var hip := Vector3(0.0, HIP, side * 0.1)
		var knee := Vector3(stride, 0.5, side * 0.11)
		var ankle := Vector3(stride * 1.6, 0.12, side * 0.12)
		leg(parts, hip, knee, ankle)
		box(parts, &"dark", Vector3(0.27, 0.11, 0.1), at(ankle + Vector3(0.05, -0.065, 0.0)))


static func leg(parts: Dictionary, hip: Vector3, knee: Vector3, ankle: Vector3) -> void:
	rod(parts, &"uniform", hip, knee, 0.1, 0.082)
	rod(parts, &"uniform", knee, ankle, 0.078, 0.062)
	ball(parts, &"uniform", knee, 0.08)


## Hips, torso, shoulders, neck and head (no helmet, armour or pack – those are the kit's).
static func body(parts: Dictionary, up: Vector3) -> void:
	box(parts, &"uniform", Vector3(0.24, 0.18, 0.34), at(up + Vector3(0.0, HIP + 0.04, 0.0)))
	box(parts, &"uniform", Vector3(0.22, 0.42, 0.38), at(up + Vector3(0.0, 1.22, 0.0)))
	for side: float in [-1.0, 1.0]:
		ball(parts, &"uniform", up + Vector3(0.0, 1.42, side * 0.2), 0.075)
	rod(parts, &"skin", up + Vector3(0.01, 1.44, 0.0), up + Vector3(0.02, 1.56, 0.0), 0.055)
	ball(parts, &"skin", up + Vector3(0.03, 1.6, 0.0), 0.1, 12, 8)


## Upper arms, forearms, gloves and a faction-colour shoulder patch on each sleeve; `hands` =
## [left, right] hand positions.
static func arms(parts: Dictionary, up: Vector3, hands: Array[Vector3]) -> void:
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var shoulder := up + Vector3(0.0, 1.41, side * 0.21)
		var hand := hands[i]
		var elbow := (shoulder + hand) / 2.0 + Vector3(-0.08, -0.12, side * 0.07)
		rod(parts, &"uniform", shoulder, elbow, 0.065, 0.058)
		rod(parts, &"uniform", elbow, hand, 0.056, 0.045)
		ball(parts, &"dark", hand, 0.045)
		var patch := shoulder.lerp(elbow, 0.35) + Vector3(0.0, 0.0, side * 0.066)
		box(parts, &"accent", Vector3(0.08, 0.055, 0.012), at(patch))


## Helmet shell: a lathe of `profile` (Vector2(radius, y) in metres, top down) on the head,
## crown base at `up` + (0, base_y, 0), tilted `tilt` rad back.
static func helmet(
	parts: Dictionary, key: String, up: Vector3, profile: Array[Vector2], base_y: float, tilt: float
) -> void:
	put(
		parts,
		&"uniform",
		ModelParts.lathe_mesh(key, scaled(profile), 16),
		Transform3D(Basis(Vector3.BACK, tilt), up + Vector3(0.0, base_y, 0.0))
	)


## RPG-7 along the X axis of frame `t` (origin = the tube's middle, on the shoulder): tube with
## the heat shield and venturi flare, the conical PG-7 warhead (olive, vest colour), two pistol
## grips and the sight. Returns the [left, right] hand positions on the grips.
static func rpg7(parts: Dictionary, t: Transform3D) -> Array[Vector3]:
	var along := t.basis * Basis(Vector3.BACK, -PI / 2.0)
	var tube: Array[Vector2] = [
		Vector2(0.0, 0.46),
		Vector2(0.02, 0.46),
		Vector2(0.02, 0.14),
		Vector2(0.033, 0.12),
		Vector2(0.033, -0.12),
		Vector2(0.02, -0.14),
		Vector2(0.02, -0.4),
		Vector2(0.046, -0.54),
		Vector2(0.0, -0.54),
	]
	var at_t := Transform3D(along, t.origin)
	put(parts, &"gun", ModelParts.lathe_mesh("soldier:rpg7", scaled(tube), 12), at_t)
	put(parts, &"vest", ModelParts.lathe_mesh("soldier:pg7", pg7_profile(), 12), at_t)
	box(parts, &"gun", Vector3(0.03, 0.1, 0.025), on(t, Vector3(0.0, -0.07, 0.0), -0.25))
	box(parts, &"gun", Vector3(0.03, 0.1, 0.025), on(t, Vector3(0.2, -0.07, 0.0), -0.25))
	box(parts, &"gun", Vector3(0.05, 0.05, 0.02), on(t, Vector3(0.16, 0.05, -0.03)))
	return [t * Vector3(0.2, -0.12, -0.02), t * Vector3(0.0, -0.12, 0.0)]


## PG-7 round (model units, lathe profile along +Y): the bulbous warhead with its conical nose
## from y 0.45 to 0.82 m, the tail end at y 0.45 sits in the launcher's muzzle.
static func pg7_profile() -> Array[Vector2]:
	return scaled(
		[
			Vector2(0.0, 0.82),
			Vector2(0.012, 0.78),
			Vector2(0.0425, 0.62),
			Vector2(0.0425, 0.53),
			Vector2(0.022, 0.48),
			Vector2(0.022, 0.45),
			Vector2(0.0, 0.45),
		]
	)


## RPG-7 frame on the right shoulder (tube middle at the shoulder, muzzle 0.04 rad up) for
## `rpg7`; `up` = the kneeling offset of the upper body.
static func rpg7_shoulder(up: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, 0.04), up + Vector3(0.02, 1.49, 0.16))


## Metres -> model units for a 2D outline or lathe profile.
static func scaled(points: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for point in points:
		out.append(point * M)
	return out


## Translation-only transform (metres).
static func at(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, pos)


## A part at `pos` in the frame `t` (metres), rolled by `roll` rad about the frame's Z.
static func on(t: Transform3D, pos: Vector3, roll := 0.0) -> Transform3D:
	return Transform3D(t.basis * Basis(Vector3.BACK, roll), t * pos)


## Appends a part (mesh already in model units, transform in metres) to the material's list.
static func put(parts: Dictionary, role: StringName, mesh: Mesh, t: Transform3D) -> void:
	if not parts.has(role):
		parts[role] = []
	(parts[role] as Array).append([mesh, Transform3D(t.basis, t.origin * M)])


static func box(parts: Dictionary, role: StringName, size: Vector3, t: Transform3D) -> void:
	put(parts, role, ModelParts.box_mesh(size * M), t)


## Tapered rod from `a` (radius r0) to `b` (radius r1; r0 when negative), metres.
static func rod(
	parts: Dictionary, role: StringName, a: Vector3, b: Vector3, r0: float, r1 := -1.0, sides := 8
) -> void:
	var top := r0 if r1 < 0.0 else r1
	var mesh := ModelParts.cyl_mesh(top * M, r0 * M, a.distance_to(b) * M, sides)
	put(parts, role, mesh, Transform3D(Frame.axis_basis(b - a), (a + b) / 2.0))


static func ball(
	parts: Dictionary, role: StringName, centre: Vector3, r: float, segments := 8, rings := 5
) -> void:
	put(parts, role, ModelParts.sphere_mesh(r * M, false, segments, rings), at(centre))
