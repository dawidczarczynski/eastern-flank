## 9K57 Uragan, 9P140 combat vehicle: 16 x 220 mm rocket launcher on the ZIL-135LM 8x8 chassis.
## Blueprint: docs/design/units/units/bm27_uragan/blueprint.md. Measurements are metres
## (vehicle_frame.gd): `x` from the front bumper (0) to the rear (LENGTH_M), `h` above the ground,
## `z` across (positive = vehicle's right). Travel order: the tube bundle lies level and points
## forward, muzzles just behind the cab, trunnions at its rear end over the last axle.

## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.62
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {
	"wheels": {},
	"launcher": {"traverse_deg": [-30, 30], "max_elevation_deg": 55, "stowed": "front"},
	"stabilisers": {},
	"blast_shields": {},
}
const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")

const LENGTH_M := 9.4
## Model units per metre: 9.4 m -> 0.874 (x unit scale 1.3 = 1.136 <= 1.15).
const K := 0.093
## ZIL-135 axles: 2.415 + 1.51 + 2.415 m (middle pair close together); wheel radius, tyre width,
## wheel centre |z|.
const AXLES: Array[float] = [2.3, 4.715, 6.225, 8.64]
const WHEEL_RADIUS := 0.67
const TYRE_WIDTH := 0.42
const WHEEL_Z := 1.1
## Fenders over the wheels: [x0, x1] per arch, top height, |z| centre and half width.
const ARCHES: Array[Vector2] = [Vector2(1.5, 3.1), Vector2(3.9, 7.04), Vector2(7.84, 9.35)]
const ARCH_TOP := 1.5
const ARCH_Z := 1.12
const ARCH_HW := 0.26
## Turntable centre (x, h) under the launcher: the "Launcher" node traverses about it.
const TURNTABLE := Vector2(6.0, 1.55)
## Pod hinge (trunnions) at the rear-bottom of the tube bundle.
const HINGE := Vector2(8.3, 2.33)
## Tubes: muzzle face and rear end (x), radius; rows (h) and the |z| columns of each row.
const TUBE_X0 := 2.8
const TUBE_X1 := 8.7
const TUBE_RADIUS := 0.13
const TUBE_ROWS: Array[float] = [2.5, 2.76, 3.02]
const COLUMNS_6: Array[float] = [-0.675, -0.405, -0.135, 0.135, 0.405, 0.675]
const COLUMNS_4: Array[float] = [-0.405, -0.135, 0.135, 0.405]
## Elevation actuators, one per side (|z|): anchor on the turntable, mount under the pod (x, h).
const ACTUATOR_Z := 0.5
const ACTUATOR_BASE := Vector2(6.3, 1.75)
const ACTUATOR_MOUNT := Vector2(5.85, 2.25)
## Cylinder and piston lengths: together 2.8 m, so they still overlap by 0.2 m at the 55 deg
## max elevation (span 2.6 m); stowed (span 0.67 m) the surplus hides in the tube bundle above
## the mount and in the carriage/deck below the anchor.
const CYLINDER_LENGTH := 1.45
const PISTON_LENGTH := 1.35
const CYLINDER_RADIUS := 0.1
const PISTON_RADIUS := 0.055


## The "Launcher" turntable stands behind the engines; its "Pod" child (the tube bundle with its
## cradle) hinges on the trunnions at the bundle's rear end, +X forward along the tubes:
## "Mouth0".."Mouth15" lie just in front of the muzzles. The tubes are stowed facing forward
## (MECHANISMS launcher `stowed: front`, read by UnitModels.launcher_aim).
static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var f := Frame.new(K, LENGTH_M / 2.0)
	var body := ModelParts.faction_material(faction, &"truck_body")
	var acc := ModelParts.accent(faction)
	var dark := ModelParts.pbr(ModelParts.DARK)
	var steel := ModelParts.pbr(ModelParts.STEEL)
	var index := 0
	for s: float in [-1.0, 1.0]:
		for x: float in AXLES:
			ModelParts.wheel(
				g,
				index,
				f.p(x, WHEEL_RADIUS, s * WHEEL_Z),
				WHEEL_RADIUS * K,
				TYRE_WIDTH * K,
				s,
				body
			)
			index += 1
	Frame.merged(g, "bm27_uragan:body", _body_parts(f), body)
	Frame.merged(g, "bm27_uragan:dark", _dark_parts(f), dark)
	Frame.merged(g, "bm27_uragan:glass", _glass_parts(f), ModelParts.pbr(ModelParts.GLASS))
	Frame.merged(g, "bm27_uragan:steel", _steel_parts(f), steel)
	Frame.merged(g, "bm27_uragan:accent", _accent_parts(f), acc)
	_build_launcher(g, f, body, dark, steel, acc)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## Arched fender over `x0..x1`: quarter-round ends of radius `r` joined by a level top at ARCH_TOP,
## both sides, as tilted strips.
static func _arch(f: Frame, parts: Array, x0: float, x1: float, r: float) -> void:
	var points: Array[Vector2] = []
	var steps := 3
	for i in steps + 1:
		var a := PI / 2.0 * i / steps
		points.append(Vector2(x0 + r - r * cos(a), ARCH_TOP - r + r * sin(a)))
	for i in steps + 1:
		var a := PI / 2.0 - PI / 2.0 * i / steps
		points.append(Vector2(x1 - r + r * cos(a), ARCH_TOP - r + r * sin(a)))
	for s: float in [-1.0, 1.0]:
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			var d := Vector2(-(b.x - a.x), b.y - a.y)
			if d.length() < 1e-4:
				continue
			var size := Vector3(d.length() + 0.04, 0.06, ARCH_HW * 2.0) * f.k
			var t := Transform3D(
				Basis(Vector3.BACK, d.angle()),
				f.p((a.x + b.x) / 2.0, (a.y + b.y) / 2.0, s * ARCH_Z)
			)
			parts.append([ModelParts.box_mesh(size), t])


## Camo: cab, folded blast shield, engine compartment, fenders, lockers, rear deck, bumper.
static func _body_parts(f: Frame) -> Array:
	var p: Array = []
	var cab := [
		Vector2(0.2, 1.1),
		Vector2(2.7, 1.1),
		Vector2(2.7, 2.62),
		Vector2(0.62, 2.62),
		Vector2(0.48, 2.04),
		Vector2(0.16, 1.98),
	]
	f.profile(p, "bm27_uragan:cab", cab, 1.22)
	f.slab(p, 0.7, 2.6, 2.62, 2.68, 1.1)  # cab roof
	f.slab(p, 0.05, 0.62, 1.99, 2.05, 1.18)  # blast shield folded on the nose ledge
	f.slab(p, 0.0, 0.4, 0.85, 1.28, 1.3)  # front bumper
	f.slab(p, 2.7, 4.55, 1.2, 2.16, 1.18)  # engine compartment
	f.slab(p, 2.8, 4.45, 2.16, 2.22, 1.08)  # its roof
	f.slab(p, 3.25, 3.95, 0.75, 1.2, 1.12)  # fuel tanks between axles 1 and 2
	f.slab(p, 4.55, 9.3, 1.3, 1.55, 1.16)  # rear deck under the launcher
	f.pair(p, 7.1, 7.8, 0.85, 1.45, 0.18, 1.0)  # lockers between axles 3 and 4
	f.slab(p, 9.1, 9.4, 0.85, 1.3, 1.2)  # rear bumper
	for arch: Vector2 in ARCHES:
		_arch(f, p, arch.x, arch.y, 0.55)
	return p


## Dark: chassis frame, underside, grilles, door seams, mirrors, lights housing, mudflaps.
static func _dark_parts(f: Frame) -> Array:
	var p: Array = []
	f.slab(p, 0.4, 9.2, 0.8, 1.2, 0.5)  # frame rails
	f.slab(p, 0.4, 2.5, 0.9, 1.1, 0.95)  # cab underside
	f.slab(p, 0.12, 0.17, 1.35, 1.85, 0.75)  # front grille panel
	f.pair(p, 3.2, 3.75, 1.4, 2.05, 0.02, 1.18)  # engine grilles
	f.pair(p, 3.85, 4.4, 1.4, 2.05, 0.02, 1.18)
	f.pair(p, 2.85, 3.05, 1.7, 2.05, 0.02, 1.18)  # louvre
	f.pair(p, 1.6, 1.64, 1.25, 2.55, 0.01, 1.225)  # door seams
	f.pair(p, 1.25, 1.31, 2.2, 2.62, 0.06, 1.38)  # mirrors
	f.pair(p, 1.28, 1.32, 2.55, 2.59, 0.08, 1.28)  # mirror arms
	f.pair(p, 9.3, 9.36, 0.45, 1.25, 0.22, 1.1)  # mudflaps
	f.slab(p, 4.4, 9.2, 1.55, 1.6, 0.7)  # turntable ring base
	return p


static func _glass_parts(f: Frame) -> Array:
	var p: Array = []
	for z: float in [-0.78, 0.0, 0.78]:
		f.slab(p, 0.5, 0.58, 2.1, 2.55, 0.36, z, -0.23)  # windscreen panes
	f.pair(p, 1.75, 2.5, 2.05, 2.52, 0.015, 1.225)  # door windows
	return p


## Headlights on the nose corners and the rear lights.
static func _steel_parts(f: Frame) -> Array:
	var p: Array = []
	for s: float in [-1.0, 1.0]:
		f.drum(p, 0.14, 1.6, s * 0.95, 0.13, 0.1, &"x", 10)
		f.drum(p, 0.3, 2.1, s * 1.15, 0.11, 0.12, &"x", 10)
	f.pair(p, 9.38, 9.42, 1.0, 1.15, 0.1, 1.05)
	return p


## Faction plates on both cab doors and the bumper.
static func _accent_parts(f: Frame) -> Array:
	var p: Array = []
	f.pair(p, 1.8, 2.45, 1.5, 1.85, 0.015, 1.225)
	f.slab(p, -0.02, 0.0, 0.95, 1.15, 0.35)
	return p


static func _build_launcher(
	g: Node3D, f: Frame, body: Material, dark: Material, steel: Material, acc: Material
) -> void:
	var launcher := Node3D.new()
	launcher.name = "Launcher"
	launcher.position = f.p(TURNTABLE.x, TURNTABLE.y)
	g.add_child(launcher)
	var to_launcher := launcher.transform.affine_inverse()
	var carriage: Array = []
	f.slab(carriage, 4.95, 7.0, 1.6, 2.18, 0.85)  # upper carriage
	f.slab(carriage, 4.95, 5.6, 1.6, 1.95, 0.85, 0.0, 0.9)  # its sloped front
	f.pair(carriage, 6.8, 8.6, 1.6, 2.2, 0.07, 0.72)  # side girders to the trunnions
	f.pair(carriage, 8.05, 8.55, 1.9, 2.55, 0.06, 0.9)  # trunnion brackets
	Frame.merged(launcher, "bm27_uragan:carriage", carriage, body, to_launcher)
	var ring: Array = []
	f.drum(ring, TURNTABLE.x, TURNTABLE.y + 0.05, 0.0, 0.95, 0.12, &"y", 20)
	f.pair(ring, HINGE.x - 0.1, HINGE.x + 0.1, HINGE.y - 0.1, HINGE.y + 0.1, 0.14, 0.9)  # trunnions
	Frame.merged(launcher, "bm27_uragan:ring", ring, dark, to_launcher)
	var pod := Node3D.new()
	pod.name = "Pod"
	pod.position = f.p(HINGE.x, HINGE.y) - launcher.position
	pod.set_meta(&"rest", pod.transform)
	launcher.add_child(pod)
	var to_pod := Frame.to_local(pod)
	Frame.merged(pod, "bm27_uragan:tubes", _tube_parts(f), body, to_pod)
	Frame.merged(pod, "bm27_uragan:pod_dark", _pod_dark_parts(f), dark, to_pod)
	var band: Array = []
	f.pair(band, TUBE_X0 + 0.15, TUBE_X0 + 0.5, 2.45, 2.8, 0.015, 0.875)
	Frame.merged(pod, "bm27_uragan:pod_accent", band, acc, to_pod)
	var index := 0
	for row in TUBE_ROWS.size():
		for z: float in COLUMNS_4 if row == 2 else COLUMNS_6:
			var mouth := Node3D.new()
			mouth.name = "Mouth%d" % index
			index += 1
			mouth.position = to_pod * f.p(TUBE_X0 - 0.1, TUBE_ROWS[row], z)
			pod.add_child(mouth)
	_build_actuators(f, launcher, pod, dark, steel)
	UnitModels.pose_launcher(g, 0.0, 0.0)


## Camo: the 16 tubes (6 + 6 + 4), the muzzle frame and the clamp bands.
static func _tube_parts(f: Frame) -> Array:
	var p: Array = []
	var length := TUBE_X1 - TUBE_X0
	for row in TUBE_ROWS.size():
		for z: float in COLUMNS_4 if row == 2 else COLUMNS_6:
			f.drum(p, (TUBE_X0 + TUBE_X1) / 2.0, TUBE_ROWS[row], z, TUBE_RADIUS, length, &"x", 10)
	# Muzzle frame: lower box around the two rows of six, narrower top box around the four.
	var x0 := TUBE_X0 + 0.08
	var x1 := TUBE_X0 + 0.58
	var low := TUBE_ROWS[0] - 0.18
	var mid := TUBE_ROWS[1] + 0.18
	var top := TUBE_ROWS[2] + 0.16
	f.pair(p, x0, x1, low, mid, 0.04, 0.84)
	f.pair(p, x0, x1, mid - 0.05, top, 0.04, 0.57)
	f.slab(p, x0, x1, low - 0.04, low + 0.02, 0.88)
	f.pair(p, x0, x1, mid - 0.05, mid + 0.01, 0.16, 0.72)
	f.slab(p, x0, x1, top - 0.04, top + 0.04, 0.61)
	# Clamp bands.
	for x: float in [5.6, 8.0]:
		f.slab(p, x - 0.06, x + 0.06, low, mid - 0.03, 0.83)
		f.slab(p, x - 0.06, x + 0.06, mid - 0.03, top - 0.04, 0.56)
	return p


## Dark: muzzle openings, cradle beams under the bundle, the trunnion axle.
static func _pod_dark_parts(f: Frame) -> Array:
	var p: Array = []
	for row in TUBE_ROWS.size():
		for z: float in COLUMNS_4 if row == 2 else COLUMNS_6:
			f.drum(p, TUBE_X0 - 0.005, TUBE_ROWS[row], z, TUBE_RADIUS * 0.8, 0.02, &"x", 10)
	f.pair(p, TUBE_X0 + 0.5, HINGE.x + 0.25, 2.2, 2.34, 0.07, 0.5)  # cradle beams
	f.slab(p, ACTUATOR_MOUNT.x - 0.12, ACTUATOR_MOUNT.x + 0.12, 2.18, 2.34, 0.6)  # cross beam
	f.drum(p, HINGE.x, HINGE.y, 0.0, 0.09, 1.9, &"z", 10)  # trunnion axle
	return p


## Two elevation actuators: "Actuator<i>" (dark cylinder, from its turntable anchor) and
## "ActuatorRod<i>" (steel piston, from the "ActuatorMount<i>" under the pod), both along +Y.
static func _build_actuators(
	f: Frame, launcher: Node3D, pod: Node3D, dark: Material, steel: Material
) -> void:
	var to_launcher := Frame.to_local(launcher)
	var to_pod := Frame.to_local(pod)
	var cylinder := ModelParts.cyl_mesh(
		CYLINDER_RADIUS * K, CYLINDER_RADIUS * K, CYLINDER_LENGTH * K, 10
	)
	var piston := ModelParts.cyl_mesh(PISTON_RADIUS * K, PISTON_RADIUS * K, PISTON_LENGTH * K, 8)
	for i in 2:
		var z := ACTUATOR_Z * (-1.0 if i == 0 else 1.0)
		var barrel := Node3D.new()
		barrel.name = "Actuator%d" % i
		barrel.position = to_launcher * f.p(ACTUATOR_BASE.x, ACTUATOR_BASE.y, z)
		launcher.add_child(barrel)
		ModelParts.add(barrel, cylinder, dark, Vector3(0.0, CYLINDER_LENGTH * K / 2.0, 0.0))
		var rod := Node3D.new()
		rod.name = "ActuatorRod%d" % i
		launcher.add_child(rod)
		ModelParts.add(rod, piston, steel, Vector3(0.0, PISTON_LENGTH * K / 2.0, 0.0))
		var mount := Node3D.new()
		mount.name = "ActuatorMount%d" % i
		mount.position = to_pod * f.p(ACTUATOR_MOUNT.x, ACTUATOR_MOUNT.y, z)
		pod.add_child(mount)
