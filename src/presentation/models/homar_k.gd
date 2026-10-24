## Homar-K (K239PL): Polish 8x8 rocket launcher – Korean K239 Chunmoo launcher module (two closed
## pods of six 239 mm rockets) on the armoured Jelcz P882.57 cab-over chassis. Blueprint:
## docs/design/units/units/homar_k/blueprint.md. All measurements below are metres taken from the
## side photo: `x` from the front bumper (0) to the rear (LENGTH_M), `h` above the ground, `z`
## across (positive = vehicle's right). The pod is stowed (level, tube ends facing the rear).

## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.62
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {
	"wheels": {},
	"stabilisers": {},
	"launcher": {"traverse_deg": "full", "max_elevation_deg": 40, "stowed": "rear"},
}

## Model units per metre: uniform, shrinks 11 m to 0.858 (x unit scale 1.3 = 1.115 <= 1.15).
const K := 0.078
const LENGTH_M := 11.0
## Axle positions (x from the front bumper), wheel radius, tyre width and wheel centre |z|.
const AXLES: Array[float] = [1.85, 3.69, 7.95, 9.46]
const WHEEL_RADIUS := 0.7
const TYRE_WIDTH := 0.45
const WHEEL_Z := 1.17
## Launcher box (pods stowed under the top cover): x range, h range, half width.
const POD_X0 := 6.52
const POD_X1 := 10.95
const POD_H0 := 2.0
const POD_H1 := 3.36
const POD_HALF_W := 1.4
## Rocket tube ends on the rear face: per pod (z centre) 2 rows x 3 columns.
const POD_CENTRES: Array[float] = [-0.7, 0.7]
const TUBE_ROWS: Array[float] = [2.38, 2.96]
const TUBE_COLUMNS: Array[float] = [-0.42, 0.0, 0.42]
const TUBE_RADIUS := 0.17
## Turntable centre (x, h) under the launcher: the "Launcher" node traverses about it.
const TURNTABLE_X := 8.6
const TURNTABLE_H := 2.0
## Elevation actuators, one per side (|z|): anchor on the turntable, mount under the pod (x, h);
## cylinder and piston lengths overlap at every elevation up to its max_elevation_deg
## (UnitModels.launcher_elevation).
const ACTUATOR_Z := 0.85
const ACTUATOR_BASE := Vector2(7.25, 1.92)
const ACTUATOR_MOUNT := Vector2(8.9, 2.0)
const ACTUATOR_LENGTH := 1.1
const CYLINDER_RADIUS := 0.13
const PISTON_RADIUS := 0.07
## Rear stabiliser jacks: x, |z|, housing bottom (h), stowed foot underside (h), leg radius.
const JACK_X := 10.51
const JACK_Z := 1.1
const JACK_HOUSING_H0 := 0.9
const JACK_STOWED_H := 0.45
const JACK_LEG_RADIUS := 0.07


## The "Launcher" turntable sits on the rear deck; its "Pod" child hinges on the front-bottom
## edge of the launcher box, turned so its +X runs to the rear: "Mouth0".."Mouth11" lie just
## behind the tube ends (the volley effect spawns rockets there). UnitModels.pose_launcher
## traverses the Launcher, elevates the Pod about its local Z and aims the two actuators.
static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var body := ModelParts.faction_material(faction, &"truck_body")
	var acc := ModelParts.accent(faction)
	var dark := ModelParts.pbr(ModelParts.DARK)
	var glass := ModelParts.pbr(ModelParts.GLASS)
	var steel := ModelParts.pbr(ModelParts.STEEL)
	var index := 0
	for s: float in [-1.0, 1.0]:
		for x: float in AXLES:
			ModelParts.wheel(
				g,
				index,
				_p(x, WHEEL_RADIUS, s * WHEEL_Z),
				WHEEL_RADIUS * K,
				TYRE_WIDTH * K,
				s,
				body
			)
			index += 1
	_merged(g, "homar_k:body", _body_parts(), body)
	_merged(g, "homar_k:dark", _dark_parts(), dark)
	_merged(g, "homar_k:glass", _glass_parts(), glass)
	_merged(g, "homar_k:accent", _accent_parts(), acc)
	_build_jacks(g, dark, steel)
	_build_pod(g, body, dark, steel, acc)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## Model-space point of a photo measurement.
static func _p(x: float, h: float, z: float) -> Vector3:
	return Vector3((LENGTH_M / 2.0 - x) * K, h * K, z * K)


## Box over x in [x0, x1], h in [h0, h1], z in [z0 - hw, z0 + hw] (metres); `tilt` leans the top
## towards the front (radians).
static func _slab(
	parts: Array, x0: float, x1: float, h0: float, h1: float, hw: float, z0 := 0.0, tilt := 0.0
) -> void:
	var size := Vector3(x1 - x0, h1 - h0, hw * 2.0) * K
	var t := Transform3D(Basis(Vector3.BACK, -tilt), _p((x0 + x1) / 2.0, (h0 + h1) / 2.0, z0))
	parts.append([ModelParts.box_mesh(size), t])


## Same box on both sides (z0 = +-z).
static func _pair(
	parts: Array, x0: float, x1: float, h0: float, h1: float, hw: float, z: float
) -> void:
	for s: float in [-1.0, 1.0]:
		_slab(parts, x0, x1, h0, h1, hw, s * z)


## Cylinder of radius `r` and length `length` centred at (x, h, z); `axis` is &"x", &"y" or &"z".
static func _drum(
	parts: Array, x: float, h: float, z: float, r: float, length: float, axis: StringName
) -> void:
	var basis := Basis.IDENTITY
	if axis == &"z":
		basis = Basis(Vector3.RIGHT, PI / 2.0)
	elif axis == &"x":
		basis = Basis(Vector3.BACK, PI / 2.0)
	var mesh := ModelParts.cyl_mesh(r * K, r * K, length * K, 12)
	parts.append([mesh, Transform3D(basis, _p(x, h, z))])


static func _merged(
	parent: Node3D, key: String, parts: Array, material: Material, base := Transform3D.IDENTITY
) -> MeshInstance3D:
	return ModelParts.add(parent, ModelParts.merged_mesh(key, parts, base), material, Vector3.ZERO)


## Camo: cab, equipment behind the cab, middle module, lockers, rear deck.
static func _body_parts() -> Array:
	var p: Array = []
	_slab(p, 0.1, 3.15, 1.45, 3.12, 1.27)  # cab
	_slab(p, 0.22, 3.08, 3.12, 3.25, 1.2)  # cab roof
	_slab(p, 0.3, 3.1, 1.0, 1.45, 0.86)  # cab underside between the wheels
	_slab(p, 3.15, 4.4, 1.5, 2.85, 0.98)  # equipment block behind the cab
	_slab(p, 4.6, 6.5, 1.3, 2.7, 1.2)  # middle module
	_slab(p, 4.75, 6.5, 2.7, 2.85, 1.12)  # its rounded top edge
	_slab(p, 4.85, 7.0, 0.85, 1.3, 1.05)  # lockers under the module
	_slab(p, 7.0, 10.6, 1.45, 1.66, 1.38)  # rear deck over the rear axles
	for s: float in [-1.0, 1.0]:
		_drum(p, 3.5, 2.45, s * 1.06, 0.27, 0.2, &"z")  # air filter drums
	return p


## Dark: frame, bumpers, steps, grilles, exhaust, launcher base, stabilisers, mirrors.
static func _dark_parts() -> Array:
	var p: Array = []
	_slab(p, 0.4, 10.8, 1.0, 1.5, 0.5)  # frame rails
	_slab(p, -0.02, 0.32, 0.95, 1.38, 1.25)  # front bumper
	_slab(p, 0.06, 0.12, 1.6, 1.9, 0.7)  # front grille
	_pair(p, 0.18, 0.86, 0.75, 1.32, 0.08, 1.18)  # front steps
	_pair(p, 2.64, 2.95, 0.8, 1.35, 0.08, 1.18)  # door steps
	_pair(p, 1.32, 1.36, 1.6, 3.0, 0.01, 1.275)  # door seams
	_pair(p, 3.7, 4.3, 1.75, 2.35, 0.02, 0.98)  # engine grilles
	_pair(p, 5.0, 5.8, 1.8, 2.15, 0.02, 1.2)  # module louvres
	_drum(p, 4.47, 2.45, 0.9, 0.08, 1.7, &"y")  # exhaust stack
	_slab(p, 6.8, 10.4, 1.66, 2.0, 1.05)  # launcher base and turntable
	_pair(p, 10.3, 10.36, 0.4, 1.45, 0.22, 1.17)  # mudflaps
	_pair(p, 10.38, 10.64, JACK_HOUSING_H0, 1.55, 0.14, JACK_Z)  # stabiliser housings
	_slab(p, 10.6, 11.0, 1.1, 1.48, 1.3)  # rear bumper and light bar
	_pair(p, 0.02, 0.1, 2.35, 3.0, 0.05, 1.4)  # mirrors
	_pair(p, 0.1, 0.3, 2.9, 2.94, 0.13, 1.33)  # mirror arms
	return p


static func _glass_parts() -> Array:
	var p: Array = []
	_pair(p, 0.5, 1.26, 2.39, 2.92, 0.015, 1.27)  # front side windows
	_pair(p, 1.97, 2.7, 2.39, 2.92, 0.015, 1.27)  # rear side windows
	_pair(p, 0.08, 0.11, 2.35, 2.95, 0.45, 0.6)  # windscreen panes
	return p


## Faction plates on both cab doors and the cab front.
static func _accent_parts() -> Array:
	var p: Array = []
	_pair(p, 0.55, 1.2, 1.72, 2.05, 0.015, 1.27)
	_slab(p, 0.08, 0.11, 2.1, 2.25, 0.5)
	return p


## "Stabiliser0/1": a steel leg with a dark foot sliding down out of the fixed housing; built
## stowed (foot JACK_STOWED_H above the ground), meta "deployed" lowers it onto y = 0.
static func _build_jacks(g: Node3D, dark: Material, steel: Material) -> void:
	var leg_top := 1.45
	var leg_len := leg_top - JACK_STOWED_H
	var leg := ModelParts.cyl_mesh(JACK_LEG_RADIUS * K, JACK_LEG_RADIUS * K, leg_len * K, 8)
	var foot := ModelParts.cyl_mesh(0.2 * K, 0.2 * K, 0.06 * K, 10)
	for i in 2:
		var jack := Node3D.new()
		jack.name = "Stabiliser%d" % i
		jack.position = _p(JACK_X, 0.0, JACK_Z * (-1.0 if i == 0 else 1.0))
		g.add_child(jack)
		ModelParts.add(jack, leg, steel, Vector3(0.0, (JACK_STOWED_H + leg_len / 2.0) * K, 0.0))
		ModelParts.add(jack, foot, dark, Vector3(0.0, (JACK_STOWED_H + 0.03) * K, 0.0))
		jack.set_meta(
			&"deployed",
			Transform3D(Basis.IDENTITY, jack.position - Vector3(0.0, JACK_STOWED_H * K, 0.0))
		)


static func _build_pod(
	g: Node3D, body: Material, dark: Material, steel: Material, acc: Material
) -> void:
	var launcher := Node3D.new()
	launcher.name = "Launcher"
	launcher.position = _p(TURNTABLE_X, TURNTABLE_H, 0.0)
	g.add_child(launcher)
	var to_launcher := launcher.transform.affine_inverse()
	var pod := Node3D.new()
	pod.name = "Pod"
	pod.transform = to_launcher * Transform3D(Basis(Vector3.UP, PI), _p(POD_X0, POD_H0, 0.0))
	pod.set_meta(&"rest", pod.transform)
	launcher.add_child(pod)
	var to_pod := (launcher.transform * pod.transform).affine_inverse()
	var shell: Array = []
	_slab(shell, POD_X0, POD_X1, POD_H0, POD_H1, POD_HALF_W)  # launcher box
	_slab(shell, 6.25, 6.55, 2.05, 3.22, 1.36, 0.0, 0.2)  # tilted front face
	_merged(pod, "homar_k:pod", shell, body, to_pod)
	var trim: Array = []
	_slab(trim, POD_X1, POD_X1 + 0.04, POD_H0 + 0.06, POD_H1 - 0.06, POD_HALF_W - 0.06)  # rear face
	_slab(trim, POD_X0 + 0.1, POD_X1, POD_H1, POD_H1 + 0.03, 0.04)  # seam between the two pods
	_slab(trim, POD_X0 + 0.2, POD_X1 - 0.2, POD_H0 - 0.03, POD_H0 + 0.08, POD_HALF_W + 0.01)
	_merged(pod, "homar_k:pod_trim", trim, dark, to_pod)
	var band: Array = []
	_slab(band, 9.55, 9.85, POD_H0 + 0.1, POD_H1 - 0.02, POD_HALF_W + 0.015)
	_merged(pod, "homar_k:pod_band", band, acc, to_pod)
	var caps: Array = []
	var index := 0
	for zc: float in POD_CENTRES:
		for h: float in TUBE_ROWS:
			for dz: float in TUBE_COLUMNS:
				_drum(caps, POD_X1 + 0.05, h, zc + dz, TUBE_RADIUS, 0.04, &"x")
				var mouth := Node3D.new()
				mouth.name = "Mouth%d" % index
				index += 1
				mouth.position = to_pod * _p(POD_X1 + 0.15, h, zc + dz)
				pod.add_child(mouth)
	_merged(pod, "homar_k:pod_caps", caps, steel, to_pod)
	_build_actuators(launcher, pod, to_launcher, to_pod, dark, steel)
	UnitModels.pose_launcher(g, 0.0, 0.0)


## Two elevation actuators: "Actuator<i>" (dark cylinder, from its turntable anchor) and
## "ActuatorRod<i>" (steel piston, from the "ActuatorMount<i>" under the pod), both along +Y.
static func _build_actuators(
	launcher: Node3D,
	pod: Node3D,
	to_launcher: Transform3D,
	to_pod: Transform3D,
	dark: Material,
	steel: Material
) -> void:
	var half := Vector3(0.0, ACTUATOR_LENGTH * K / 2.0, 0.0)
	var cylinder := ModelParts.cyl_mesh(
		CYLINDER_RADIUS * K, CYLINDER_RADIUS * K, ACTUATOR_LENGTH * K, 10
	)
	var piston := ModelParts.cyl_mesh(PISTON_RADIUS * K, PISTON_RADIUS * K, ACTUATOR_LENGTH * K, 8)
	for i in 2:
		var z := ACTUATOR_Z * (-1.0 if i == 0 else 1.0)
		var barrel := Node3D.new()
		barrel.name = "Actuator%d" % i
		barrel.position = to_launcher * _p(ACTUATOR_BASE.x, ACTUATOR_BASE.y, z)
		launcher.add_child(barrel)
		ModelParts.add(barrel, cylinder, dark, half)
		var rod := Node3D.new()
		rod.name = "ActuatorRod%d" % i
		launcher.add_child(rod)
		ModelParts.add(rod, piston, steel, half)
		var mount := Node3D.new()
		mount.name = "ActuatorMount%d" % i
		mount.position = to_pod * _p(ACTUATOR_MOUNT.x, ACTUATOR_MOUNT.y, z)
		pod.add_child(mount)
