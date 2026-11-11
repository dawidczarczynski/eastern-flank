extends RefCounted
## AGM-158B JASSM-ER (TASK-144): procedural turntable model for the strike panel's model card.
## Catalog entry: docs/design/units/weapons/jassm_er/ (real dimensions, features, blueprint).
##
## Weapon model contract (WeaponModels): 1 unit = 1 m, origin at the centre of mass, nose along
## +X, wings deployed. Built with MeshKits (one MeshKit per material, two MeshInstance3D in all),
## plain PBR materials (no faction: a weapon has no camouflage).
##
## Shape (side view): a faceted, trapezoid-section body (flat belly, chines low on the sides,
## narrower flat top) with a wedge nose whose top slopes down to a chined tip near the belly line,
## a short tapering boat tail with the exhaust, a ventral air intake scoop under the rear half, a
## high-mounted swept wing just aft of the centre of mass and a single swept vertical fin on top
## of the tail.

## Real data (metres): length, deployed span, body width and height (Wikipedia / CSIS, see the
## catalog entry); the fin height is estimated from photographs.
const LENGTH := 4.27
const SPAN := 2.4
const BODY_WIDTH := 0.55
const BODY_HEIGHT := 0.45
## Nose and tail ends along X (centre of mass at 47 % of the length from the nose: the warhead and
## seeker are forward, the engine aft).
const NOSE_X := LENGTH * 0.47
const TAIL_X := NOSE_X - LENGTH
## Body cross-section (z, y) at full size: flat belly, chines at the widest point, narrower top.
const SECTION: Array[Vector2] = [
	Vector2(-0.21, -0.225),
	Vector2(0.21, -0.225),
	Vector2(0.275, -0.1),
	Vector2(0.13, 0.225),
	Vector2(-0.13, 0.225),
	Vector2(-0.275, -0.1),
]
## Body stations from the nose tip to the tail: [x, width scale, height scale, centre y]. The nose
## tip sits low (flat chined nose, top sloping down), the tail tapers slightly upwards.
const STATIONS := [
	[NOSE_X, 0.3, 0.16, -0.16],
	[NOSE_X - 0.35, 0.68, 0.5, -0.11],
	[NOSE_X - 0.85, 1.0, 1.0, 0.0],
	[TAIL_X + 0.75, 1.0, 1.0, 0.0],
	[TAIL_X, 0.62, 0.62, 0.03],
]
## Wing (each side): root at the body top, chord and sweep from photographs.
const WING_ROOT_X := -0.05
const WING_ROOT_CHORD := 0.42
const WING_TIP_CHORD := 0.2
const WING_SWEEP_DEG := 30.0
const WING_THICKNESS := 0.035
## Vertical fin on the tail top.
const FIN_HEIGHT := 0.28
const FIN_ROOT_CHORD := 0.55
const FIN_TIP_CHORD := 0.2
const FIN_SWEEP_DEG := 45.0
const FIN_THICKNESS := 0.03
## Ventral intake scoop: x range (lip forward), width and depth below the belly.
const INTAKE_FRONT_X := -0.55
const INTAKE_BACK_X := -1.5
const INTAKE_WIDTH := 0.26
const INTAKE_DEPTH := 0.07

const BODY := [Color("#5d6157"), 0.78, 0.12]


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "JassmEr"
	var meshes := ModelParts.cached_meshes("weapon:jassm_er", _meshes)
	(
		MeshKits
		. add_meshes(
			root,
			meshes,
			{
				&"body": ModelParts.pbr(BODY),
				&"dark": ModelParts.pbr(ModelParts.DARK),
				&"glass": ModelParts.pbr(ModelParts.GLASS),
			}
		)
	)
	return root


static func _meshes() -> Dictionary:
	var kits := MeshKits.new()
	_body(kits.k(&"body"))
	_wings(kits.k(&"body"))
	_fin(kits.k(&"body"))
	_intake(kits.k(&"body"), kits.k(&"dark"))
	_exhaust(kits.k(&"dark"))
	_seeker(kits.k(&"glass"))
	return kits.commit_all()


static func _ring(station: Array) -> Array:
	var ring := []
	for p: Vector2 in SECTION:
		ring.append(
			Vector3(
				station[0], p.y * float(station[2]) + float(station[3]), p.x * float(station[1])
			)
		)
	return ring


static func _body(kit: MeshKit) -> void:
	var rings := []
	var edges := []
	for station: Array in STATIONS:
		rings.append(_ring(station))
	for i in rings.size() - 1:
		edges.append(0.0)
	kit.stack(rings, edges)


## Top surface height of the full-size body.
static func _top() -> float:
	return SECTION[3].y


static func _wings(kit: MeshKit) -> void:
	var half_span := SPAN / 2.0
	var sweep := tan(deg_to_rad(WING_SWEEP_DEG)) * half_span
	var front := WING_ROOT_X + WING_ROOT_CHORD / 2.0
	# Plan outline in (x, z), one wing; the other one mirrored. Both roots meet on the body top.
	for side: float in [-1.0, 1.0]:
		var outline := [
			Vector2(front, 0.0),
			Vector2(front - sweep, half_span * side),
			Vector2(front - sweep - WING_TIP_CHORD, half_span * side),
			Vector2(front - WING_ROOT_CHORD, 0.0),
		]
		var y := _top() + WING_THICKNESS / 2.0
		kit.plate(
			outline,
			Vector3(0.0, y, 0.0),
			Vector3.RIGHT,
			Vector3.BACK,
			Vector3.UP,
			-WING_THICKNESS / 2.0,
			WING_THICKNESS / 2.0
		)


static func _fin(kit: MeshKit) -> void:
	var tail_station: Array = STATIONS[STATIONS.size() - 1]
	var root_back := float(tail_station[0]) + 0.05
	var root_y := _top() * float(tail_station[2]) + float(tail_station[3]) + 0.02
	var root_front := root_back + FIN_ROOT_CHORD
	var sweep := tan(deg_to_rad(FIN_SWEEP_DEG)) * FIN_HEIGHT
	var outline := [
		Vector2(root_front, root_y - 0.03),
		Vector2(root_front - sweep, root_y + FIN_HEIGHT),
		Vector2(root_front - sweep - FIN_TIP_CHORD, root_y + FIN_HEIGHT),
		Vector2(root_back, root_y - 0.03),
	]
	kit.plate(
		outline,
		Vector3.ZERO,
		Vector3.RIGHT,
		Vector3.UP,
		Vector3.BACK,
		-FIN_THICKNESS / 2.0,
		FIN_THICKNESS / 2.0
	)


static func _intake(body: MeshKit, dark: MeshKit) -> void:
	var belly := SECTION[0].y
	var hw := INTAKE_WIDTH / 2.0
	var lip := belly - INTAKE_DEPTH
	# Scoop: open trapezoid front face, the bottom ramping back up into the belly.
	var front := [
		Vector3(INTAKE_FRONT_X, belly + 0.01, -hw),
		Vector3(INTAKE_FRONT_X, belly + 0.01, hw),
		Vector3(INTAKE_FRONT_X, lip, hw * 0.8),
		Vector3(INTAKE_FRONT_X, lip, -hw * 0.8),
	]
	var back := [
		Vector3(INTAKE_BACK_X, belly + 0.01, -hw * 0.6),
		Vector3(INTAKE_BACK_X, belly + 0.01, hw * 0.6),
		Vector3(INTAKE_BACK_X, belly + 0.005, hw * 0.5),
		Vector3(INTAKE_BACK_X, belly + 0.005, -hw * 0.5),
	]
	body.stack([front, back], [0.0])
	var mouth := []
	for p: Vector3 in front:
		mouth.append(p + Vector3(0.004, 0.0, 0.0))
	dark.poly_auto(mouth, Vector3(INTAKE_FRONT_X - 1.0, belly - INTAKE_DEPTH / 2.0, 0.0))


static func _exhaust(kit: MeshKit) -> void:
	var tail: Array = STATIONS[STATIONS.size() - 1]
	var ring := []
	for p: Vector3 in _ring(tail):
		var centre := Vector3(p.x, float(tail[3]), 0.0)
		ring.append(centre + (p - centre) * 0.7 + Vector3(-0.004, 0.0, 0.0))
	kit.poly_auto(ring, Vector3(TAIL_X + 1.0, float(tail[3]), 0.0))


## Seeker window: a dark facet on each upper nose face (the imaging infrared seeker of the real
## missile sits behind a flat window in the nose).
static func _seeker(kit: MeshKit) -> void:
	var a: Array = _ring(STATIONS[0])
	var b: Array = _ring(STATIONS[1])
	var top_centre := (
		((a[3] as Vector3) + (a[4] as Vector3) + (b[3] as Vector3) + (b[4] as Vector3)) / 4.0
	)
	var inside := top_centre + Vector3(0.0, -0.3, 0.0)
	var quad := []
	for p: Vector3 in [a[3], a[4], b[4], b[3]]:
		quad.append(top_centre + (p - top_centre) * 0.7 + Vector3(0.0, 0.004, 0.0))
	kit.poly_auto(quad, inside)
