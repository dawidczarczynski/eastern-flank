## 9K57 Uragan, 9P140 combat vehicle: 16 x 220 mm rocket launcher on the ZIL-135LM 8x8 chassis.
## Blueprint: docs/design/units/units/bm27_uragan/blueprint.md. Measurements are metres
## (vehicle_frame.gd): `x` from the front bumper (0) to the rear (LENGTH_M), `h` above the ground,
## `z` across (positive = vehicle's right). Travel order: the tube bundle lies level and points
## forward, muzzles just behind the cab, trunnions at its rear end over the last axle.
##
## Built with MeshKit (TASK-073, ADR 0012) like the v3 tanks: chamfered plates, bolts, hinges,
## hydraulic lines, lathed tubes with open muzzles, the shared WheeledRunningGear. What the camera
## never sees is cut (nothing inside the cab, plain inner wheel halves, the tubes hidden inside the
## bundle as plain 8-sided shells). The geometry does not depend on the faction, so it is generated
## once (ModelParts.cached_meshes) and only the materials differ.

## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.62
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {
	"wheels": {},
	"launcher": {"traverse_deg": [-30, 30], "max_elevation_deg": 55, "stowed": "front"},
	"stabilisers": {},
	"blast_shields": {},
}
## Stabiliser jacks at the rear of the frame (x, |z|): the telescopic rod slides down JACK_STROKE
## out of a fixed sleeve; stowed the foot pad hangs JACK_STOWED_H above the ground.
const JACK_X := 8.95
const JACK_Z := 0.62
const JACK_STOWED_H := 0.35
const JACK_ROD_TOP := 1.25
const JACK_PAD_RADIUS := 0.16
## Blast shields: plate size (m) and the glass they cover. Windscreen: three plates hinged at the
## lower edge of each pane (open = lying on the nose ledge); side: one per door window hinged at
## its top edge (open = awning over the window).
const SHIELD_THICKNESS := 0.05
const SCREEN_HINGE := Vector2(0.489, 2.106)
const SCREEN_LENGTH := 0.5
const SCREEN_RAKE := 0.23
const SCREEN_Z: Array[float] = [-0.78, 0.0, 0.78]
const SIDE_HINGE := Vector3(2.125, 2.54, 1.245)
const SIDE_SHIELD := Vector2(0.8, 0.52)
const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const Gear := preload("res://src/presentation/models/parts/wheeled_running_gear.gd")

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
const ARCH_RADIUS := 0.55
## Turntable centre (x, h) under the launcher: the "Launcher" node traverses about it; ring radius.
const TURNTABLE := Vector2(6.0, 1.55)
const TURNTABLE_RING_R := 0.95
## Pod hinge (trunnions) at the rear-bottom of the tube bundle.
const HINGE := Vector2(8.3, 2.33)
## Tubes: muzzle face and rear end (x), radius; rows (h) and the |z| columns of each row.
const TUBE_X0 := 2.8
const TUBE_X1 := 8.42
const TUBE_RADIUS := 0.13
const TUBE_ROWS: Array[float] = [2.5, 2.76, 3.02]
const COLUMNS_6: Array[float] = [-0.675, -0.405, -0.135, 0.135, 0.405, 0.675]
const COLUMNS_4: Array[float] = [-0.405, -0.135, 0.135, 0.405]
## Detailed muzzle section of each tube (inside the muzzle frame, which hides the seam to the plain
## rest of the tube), bore depth (dark, then closed) and the rim.
const MUZZLE_SECTION := 0.5
const BORE_DEPTH := 0.3
const BORE_RADIUS := 0.112
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
## Engine compartment behind the cab (x0, x1, top h, half width) and its side grilles (x spans).
const ENGINE := Vector4(2.7, 4.55, 2.16, 1.18)
const GRILLES: Array[Vector2] = [Vector2(3.2, 3.75), Vector2(3.85, 4.4)]
## Exhaust outlet under the left engine side, behind the first axle (x, h, z).
const EXHAUST := Vector3(3.15, 1.0, -1.2)
## Boxes strictly inside closed shells (vehicle metres: position = (x from the front, h, z)): the
## cab. No triangle may lie entirely inside one (hidden-geometry test, test_mlrs_models.gd).
const HULL_INTERIOR: Array[AABB] = [AABB(Vector3(0.75, 1.35, -0.95), Vector3(1.8, 0.85, 1.9))]
## Lowest raised-pod vertex outside the turntable ring (m) – above every hull / cab point inside
## the pod's swept circle (launcher sweep test).
const LAUNCHER_CLEARANCE_H := 2.24


static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var f := vehicle_frame()
	var m := materials(faction)
	var spec := running_gear()
	Gear.add_pivots(g, f, spec, m)
	var hull := ModelParts.cached_meshes(
		"bm27_uragan:hull", func() -> Dictionary: return _hull_meshes(f, spec)
	)
	MeshKits.add_meshes(g, hull, m)
	_anchors(g, f)
	_build_launcher(g, f, m)
	_build_jacks(g, f, m)
	_build_shields(g, m)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## Metres -> model space: K model units per metre, bumper to rear centred on x = 0.
static func vehicle_frame() -> Frame:
	return Frame.new(K, LENGTH_M / 2.0)


## Truck camo &"body" plus the kit tanks' weathered &"dark", PBR &"steel" / &"glass" /
## &"rubber", &"lens" and the faction &"accent" (Frame.kit_tank_materials).
static func materials(faction: FactionDefinition) -> Dictionary:
	var m := Frame.kit_tank_materials(faction)
	m[&"body"] = ModelParts.faction_material(faction, &"truck_body")
	return m


## ZIL-135LM wheels: 1.34 m tyres with directional lugs, dished discs with the central tyre
## inflation hub.
static func running_gear() -> Gear.Spec:
	var spec := Gear.Spec.new()
	spec.key = "bm27_uragan"
	spec.axle_x = AXLES
	spec.wheel_radius = WHEEL_RADIUS
	spec.tyre_width = TYRE_WIDTH
	spec.track_z = WHEEL_Z
	spec.wheel_sides = 18
	spec.tread_lugs = 16
	spec.lug_depth = 0.04
	spec.inflation_hub = true
	return spec


## Effect anchors for MotionFx (TASK-064): the exhaust outlet, dust behind the rear tyres.
static func _anchors(g: Node3D, f: Frame) -> void:
	var rear := AXLES[AXLES.size() - 1] + WHEEL_RADIUS * 0.7
	var at := {
		"Exhaust": f.p(EXHAUST.x, EXHAUST.y - 0.05, EXHAUST.z - 0.08),
		"Dust_L": f.p(rear, 0.02, -WHEEL_Z),
		"Dust_R": f.p(rear, 0.02, WHEEL_Z),
	}
	for name: String in at:
		var marker := Marker3D.new()
		marker.name = name
		marker.position = at[name]
		g.add_child(marker)


static func _hull_meshes(f: Frame, spec: Gear.Spec) -> Dictionary:
	var h := MeshKits.new(f)
	_cab(h)
	_cab_front(h)
	_engine(h)
	_chassis(h)
	for i in ARCHES.size():
		for s: float in [-1.0, 1.0]:
			_fender(h.k(&"body"), ARCHES[i], s, i == 0)
	_rear(h)
	_jack_mounts(h)
	Gear.add_hull_parts(h, spec)
	return h.commit_all()


# --- Cab ----------------------------------------------------------------------------------------


## Cab shell (side profile with the raked windscreen), roof, framed windscreen panes and door
## windows, doors with seams, hinges and handles, mirrors, roof lamps, antenna, faction plates.
static func _cab(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var glass := h.k(&"glass")
	var cab := [
		Vector2(0.2, 1.1),
		Vector2(2.7, 1.1),
		Vector2(2.7, 2.6),
		Vector2(0.62, 2.6),
		Vector2(0.48, 2.04),
		Vector2(0.16, 1.98),
	]
	body.profile(cab, 1.22, 0.0, 0.06)
	body.slab(0.6, 2.7, 2.58, 2.68, 1.2, 0.0, 0.05)  # roof with rounded edge
	# Windscreen: three raked panes in thick frames.
	var rake := -atan2(0.14, 0.58)
	var rot := Basis(Vector3.BACK, rake)
	var out := Vector3(-0.58, 0.14, 0.0).normalized()
	var mid := Vector3(0.55, 2.33, 0.0)
	for z: float in SCREEN_Z:
		glass.cbox(mid + out * 0.012 + Vector3(0, 0, z), Vector3(0.012, 0.5, 0.7), 0.0, rot)
	for z: float in [-1.17, -0.39, 0.39, 1.17]:
		body.cbox(mid + out * 0.025 + Vector3(0, 0, z), Vector3(0.04, 0.6, 0.08), 0.012, rot)
	for dh: float in [-0.28, 0.28]:
		var bar := mid + Vector3(0.14, 0.58, 0.0).normalized() * dh + out * 0.025
		body.cbox(bar, Vector3(0.04, 0.06, 2.42), 0.012, rot)
	# Wipers parked on the lower frame bar.
	for z: float in [-0.6, 0.2]:
		var root := mid + Vector3(0.14, 0.58, 0.0).normalized() * -0.24 + out * 0.05
		dark.tube([root + Vector3(0, 0, z), root + Vector3(0, 0.02, z + 0.42)], 0.008, 4)
	for s: float in [-1.0, 1.0]:
		var z := s * 1.22
		# Door: seams, door window in a frame, hinges, handle; faction plate below the window.
		dark.openness = 0.4
		dark.slab(1.6, 1.63, 1.2, 2.56, 0.008, z, 0.0)
		dark.slab(2.6, 2.63, 1.2, 2.56, 0.008, z, 0.0)
		dark.slab(1.6, 2.63, 1.2, 1.23, 0.008, z, 0.0)
		dark.openness = 1.0
		glass.slab(1.75, 2.5, 2.05, 2.52, 0.006, s * 1.225, 0.0)
		body.slab(1.71, 2.54, 2.0, 2.05, 0.02, s * 1.23, 0.01)
		body.slab(1.71, 2.54, 2.52, 2.56, 0.02, s * 1.23, 0.01)
		body.slab(1.71, 1.75, 2.05, 2.52, 0.02, s * 1.23, 0.01)
		body.slab(2.5, 2.54, 2.05, 2.52, 0.02, s * 1.23, 0.01)
		for hh: float in [1.45, 2.3]:
			steel.rod(Vector3(1.63, hh, s * 1.235), Vector3.UP, 0.025, 0.14, 8, 0.006)
		steel.tube(
			[
				Vector3(2.38, 1.92, s * 1.225),
				Vector3(2.4, 1.92, s * 1.26),
				Vector3(2.52, 1.92, s * 1.26),
				Vector3(2.54, 1.92, s * 1.225)
			],
			0.012,
			6
		)
		h.k(&"accent").slab(1.8, 2.45, 1.5, 1.85, 0.008, s * 1.226, 0.004)
		# Grab handle on the cab's rear corner.
		steel.tube(
			[
				Vector3(2.66, 1.5, s * 1.22),
				Vector3(2.66, 1.52, s * 1.27),
				Vector3(2.66, 2.3, s * 1.27),
				Vector3(2.66, 2.32, s * 1.22)
			],
			0.014,
			6
		)
		# Mirror on a bent arm from the front door post.
		steel.tube(
			[
				Vector3(1.5, 2.3, s * 1.22),
				Vector3(1.42, 2.36, s * 1.33),
				Vector3(1.3, 2.4, s * 1.38)
			],
			0.015,
			6
		)
		dark.cbox(Vector3(1.28, 2.42, s * 1.39), Vector3(0.05, 0.36, 0.12), 0.012)
		# Roof marker lamp over the windscreen corner.
		body.rod(Vector3(0.68, 2.71, s * 1.05), Vector3.UP, 0.06, 0.06, 10, 0.012)
		h.k(&"lens").rod(Vector3(0.68, 2.745, s * 1.05), Vector3.UP, 0.045, 0.01, 10)
	# Rain gutter along the roof edge, antenna base and a short whip stub on the right rear.
	dark.rod(Vector3(2.45, 2.72, 0.95), Vector3.UP, 0.06, 0.08, 10, 0.012)
	steel.tube([Vector3(2.45, 2.76, 0.95), Vector3(2.45, 3.1, 0.95)], 0.012, 5)


## Nose: lower front panel with the raised bonnet bulge and its grille, round headlights in
## housings with wire guards, indicators, the heavy bumper with tow hooks and the towing cable,
## the bumper's faction plate.
static func _cab_front(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var lens := h.k(&"lens")
	body.slab(0.1, 0.5, 1.45, 2.02, 0.44, 0.0, 0.09)  # bonnet bulge
	dark.openness = 0.3
	dark.slab(0.09, 0.11, 1.52, 1.8, 0.34, 0.0, 0.0)
	dark.openness = 1.0
	for i in 5:
		var hh := 1.55 + i * 0.055
		body.cbox(Vector3(0.095, hh, 0.0), Vector3(0.02, 0.022, 0.7), 0.005)
	for s: float in [-1.0, 1.0]:
		var c := Vector3(0.14, 1.6, s * 0.95)
		body.rod(c, Vector3.RIGHT, 0.15, 0.14, 16, 0.035)
		dark.openness = 0.5
		dark.rod(c + Vector3(-0.075, 0, 0), Vector3.RIGHT, 0.125, 0.012, 16, 0.004)
		dark.openness = 1.0
		lens.rod(c + Vector3(-0.08, 0, 0), Vector3.RIGHT, 0.11, 0.01, 16)
		for dh: float in [-0.06, 0.0, 0.06]:
			steel.tube(
				[
					c + Vector3(-0.03, dh, -0.13),
					c + Vector3(-0.1, dh, -0.08),
					c + Vector3(-0.1, dh, 0.08),
					c + Vector3(-0.03, dh, 0.13)
				],
				0.006,
				4
			)
		# Indicator lamp beside the headlight.
		body.rod(c + Vector3(0.02, 0.0, s * 0.24), Vector3.RIGHT, 0.06, 0.08, 10, 0.012)
		lens.rod(c + Vector3(-0.025, 0.0, s * 0.24), Vector3.RIGHT, 0.045, 0.01, 10)
		# Tow hook hanging under the bumper.
		dark.slab(0.04, 0.2, 0.8, 0.86, 0.07, s * 0.7, 0.012)
		var hook := MeshKit.arc(
			Vector3(0.12, 0.76, s * 0.7), 0.06, Vector3.LEFT, Vector3.DOWN, 0.0, PI * 1.2, 8
		)
		steel.tube(hook, 0.02, 6)
	# Heavy bumper, towing cable lying along its top with eyes at both ends.
	body.slab(0.0, 0.4, 0.85, 1.28, 1.3, 0.0, 0.06)
	var cable := []
	for i in 9:
		var z := lerpf(-1.15, 1.15, i / 8.0)
		cable.append(Vector3(0.12 + 0.01 * sin(i * 1.3), 1.3, z))
	steel.tube(cable, 0.025, 6)
	for s: float in [-1.0, 1.0]:
		var eye := MeshKit.arc(
			Vector3(0.12, 1.3, s * 1.2), 0.07, Vector3.RIGHT, Vector3.BACK * s, 0.3, PI * 1.7, 8
		)
		steel.tube(eye, 0.015, 5)
	h.k(&"accent").slab(-0.01, 0.0, 0.95, 1.15, 0.35, 0.0, 0.003)


# --- Engine compartment, chassis, fenders, rear ------------------------------------------------


## Twin-engine compartment behind the cab: chamfered box and roof, two tall slatted grilles and a
## louvre per side, roof hatch seam, the exhaust outlet under the left side, the fuel
## tanks between axles 1 and 2.
static func _engine(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	body.slab(ENGINE.x, ENGINE.y, 1.2, ENGINE.z, ENGINE.w, 0.0, 0.05)
	body.slab(2.8, 4.45, ENGINE.z - 0.02, 2.22, 1.08, 0.0, 0.03)
	dark.openness = 0.4
	dark.slab(3.5, 3.52, 2.212, 2.221, 0.9, 0.0, 0.0)
	dark.openness = 1.0
	for s: float in [-1.0, 1.0]:
		var face := s * ENGINE.w
		for span: Vector2 in GRILLES:
			dark.openness = 0.25
			dark.slab(span.x, span.y, 1.4, 2.05, 0.01, face, 0.0)
			dark.openness = 1.0
			body.slab(span.x - 0.03, span.y + 0.03, 2.03, 2.08, 0.02, face, 0.01)
			body.slab(span.x - 0.03, span.y + 0.03, 1.37, 1.42, 0.02, face, 0.01)
			body.slab(span.x - 0.03, span.x + 0.01, 1.42, 2.03, 0.02, face, 0.01)
			body.slab(span.y - 0.01, span.y + 0.03, 1.42, 2.03, 0.02, face, 0.01)
			for i in 9:
				var hh := 1.47 + i * 0.065
				var slat := Vector3((span.x + span.y) / 2.0, hh, face + s * 0.005)
				body.cbox(
					slat, Vector3(span.y - span.x, 0.018, 0.02), 0.0, Basis(Vector3.RIGHT, s * 0.5)
				)
		dark.openness = 0.3
		dark.slab(2.85, 3.05, 1.7, 2.05, 0.01, face, 0.0)
		dark.openness = 1.0
		for i in 4:
			body.cbox(
				Vector3(2.95, 1.75 + i * 0.08, face + s * 0.008), Vector3(0.2, 0.02, 0.02), 0.0
			)
		# Fuel tank: a lathed drum along x with straps and a filler cap.
		var c := Vector3(3.6, 0.98, s * 0.88)
		var r := 0.22
		var tank := [
			Vector2(0.0, 0.35),
			Vector2(r - 0.03, 0.35),
			Vector2(r, 0.32),
			Vector2(r, -0.32),
			Vector2(r - 0.03, -0.35),
			Vector2(0.0, -0.35)
		]
		body.lathe(c, Frame.axis_basis(Vector3.RIGHT), tank, 14)
		for dx: float in [-0.18, 0.18]:
			var strap := MeshKit.arc(
				c + Vector3(dx, 0, 0), r + 0.01, Vector3.BACK, Vector3.UP, -0.3, PI + 0.3, 10
			)
			dark.tube(strap, 0.014, 4)
		steel.rod(c + Vector3(0.2, r + 0.01, 0.0), Vector3.UP, 0.04, 0.04, 8, 0.008)
	# Exhaust: pipe from under the engine to the outlet pointing out and down, with a heat shield.
	var e := EXHAUST
	dark.tube([e + Vector3(0.0, 0.05, 0.5), e + Vector3(0.0, 0.05, 0.12), e], 0.05, 8)
	dark.openness = 0.1
	dark.rod(e + Vector3(0.0, -0.01, -0.02), Vector3(0.0, -0.4, -1.0), 0.04, 0.02, 8)
	dark.openness = 1.0
	body.cbox(e + Vector3(0.0, 0.12, 0.15), Vector3(0.22, 0.02, 0.3), 0.006)


## Chassis: frame rails and cross members seen between the wheel groups, axle housings with
## differentials (simple shapes, mostly hidden), cab underside, steps, rear deck under the
## launcher, the fixed turntable base, lockers between axles 3 and 4.
static func _chassis(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	dark.pair(0.4, 9.2, 0.8, 1.2, 0.07, 0.45, 0.01)
	for x: float in [1.1, 3.5, 5.45, 7.5, 9.05]:
		dark.slab(x - 0.06, x + 0.06, 0.85, 1.15, 0.4, 0.0, 0.0)
	for x: float in AXLES:
		dark.rod(Vector3(x, WHEEL_RADIUS, 0.0), Vector3.BACK, 0.1, 1.8, 8)
		dark.cbox(Vector3(x, WHEEL_RADIUS, 0.0), Vector3(0.4, 0.36, 0.36), 0.04)
	dark.slab(0.4, 2.5, 0.9, 1.1, 0.95, 0.0, 0.0)  # cab underside
	# Rear deck under the launcher, fixed turntable base.
	body.slab(4.55, 9.3, 1.3, 1.55, 1.16, 0.0, 0.03)
	dark.slab(4.4, 9.2, 1.55, 1.6, 0.7, 0.0, 0.01)
	for s: float in [-1.0, 1.0]:
		# Locker with hinges along the top and two latches.
		body.slab(7.1, 7.8, 0.85, 1.45, 0.18, s * 1.0, 0.03)
		dark.openness = 0.4
		dark.slab(7.13, 7.77, 0.88, 1.42, 0.004, s * 1.181, 0.0)
		dark.openness = 1.0
		body.slab(7.15, 7.75, 0.9, 1.4, 0.01, s * 1.183, 0.005)
		for x: float in [7.25, 7.65]:
			steel.rod(Vector3(x, 1.4, s * 1.19), Vector3.RIGHT, 0.018, 0.12, 6)
			dark.cbox(Vector3(x, 1.0, s * 1.195), Vector3(0.05, 0.07, 0.025), 0.006)
		# Step under the door, behind the first wheel arch.
		dark.slab(2.75, 3.15, 1.06, 1.1, 0.12, s * 1.1, 0.01)
		dark.slab(2.75, 2.79, 0.85, 1.1, 0.02, s * 1.1, 0.0)
		dark.slab(3.11, 3.15, 0.85, 1.1, 0.02, s * 1.1, 0.0)
		# Deck edge rub rail and tie-down eyes.
		body.slab(4.6, 9.25, 1.48, 1.53, 0.025, s * 1.17, 0.01)
		for x: float in [5.2, 7.0, 8.9]:
			var eye := MeshKit.arc(
				Vector3(x, 1.42, s * 1.18), 0.04, Vector3.RIGHT, Vector3.DOWN, 0.0, PI, 6
			)
			steel.tube(eye, 0.01, 4)


## Arched fender over x0..x1 on side `s`: a smooth swept plate (quarter-round ends of ARCH_RADIUS
## joined by a level top at ARCH_TOP) with a valance lip along its outer edge. The front arch runs
## into the cab: its inner part stops at the cab side wall zone (`trim`), nothing inside the cab.
static func _fender(body: MeshKit, arch: Vector2, s: float, trim: bool) -> void:
	var r := ARCH_RADIUS
	var plate := _arch_band(arch.x, arch.y, r + 0.03, r - 0.03)
	var inner := s * (1.0 if trim else ARCH_Z - ARCH_HW)
	var outer := s * (ARCH_Z + ARCH_HW)
	body.plate(
		plate,
		Vector3.ZERO,
		Vector3.RIGHT,
		Vector3.UP,
		Vector3.BACK,
		minf(inner, outer),
		maxf(inner, outer),
		0.02
	)
	var lip := _arch_band(arch.x, arch.y, r + 0.03, r - 0.09)
	body.plate(
		lip,
		Vector3.ZERO,
		Vector3.RIGHT,
		Vector3.UP,
		Vector3.BACK,
		outer - 0.015,
		outer + 0.015,
		0.008
	)


## Closed outline (x, h) of an arch band between the radii `outer` and `inner` (same centres).
static func _arch_band(x0: float, x1: float, outer: float, inner: float) -> Array:
	var r := ARCH_RADIUS
	var steps := 6
	var centres := [Vector2(x0 + r, ARCH_TOP - r), Vector2(x1 - r, ARCH_TOP - r)]
	var a_out := []
	var a_in := []
	for i in steps + 1:
		var a := PI - PI / 2.0 * i / steps
		var d := Vector2(cos(a), sin(a))
		a_out.append((centres[0] as Vector2) + d * outer)
		a_in.append((centres[0] as Vector2) + d * inner)
	for i in steps + 1:
		var a := PI / 2.0 - PI / 2.0 * i / steps
		var d := Vector2(cos(a), sin(a))
		a_out.append((centres[1] as Vector2) + d * outer)
		a_in.append((centres[1] as Vector2) + d * inner)
	a_in.reverse()
	return a_out + a_in


## Rear: bumper with tail lights under guards, the towing pintle, mudflaps behind the last axle.
static func _rear(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	body.slab(9.1, 9.4, 0.85, 1.3, 1.2, 0.0, 0.04)
	for s: float in [-1.0, 1.0]:
		var z := s * 1.0
		body.slab(9.36, 9.42, 1.02, 1.16, 0.12, z, 0.01)
		h.k(&"lens").slab(9.42, 9.43, 1.05, 1.13, 0.09, z, 0.0)
		steel.tube(
			[
				Vector3(9.4, 1.19, z - 0.13),
				Vector3(9.43, 1.19, z - 0.13),
				Vector3(9.43, 1.19, z + 0.13),
				Vector3(9.4, 1.19, z + 0.13)
			],
			0.008,
			4
		)
		dark.slab(9.3, 9.34, 0.45, 1.25, 0.22, s * WHEEL_Z, 0.008)
	dark.slab(9.2, 9.36, 0.8, 0.86, 0.1, 0.0, 0.015)
	var pintle := MeshKit.arc(
		Vector3(9.28, 0.76, 0.0), 0.06, Vector3.RIGHT, Vector3.DOWN, 0.0, PI * 1.2, 8
	)
	steel.tube(pintle, 0.02, 6)


## Fixed parts of the stabiliser jacks: brackets on the frame, round sleeves the legs slide in,
## hydraulic lines from the sleeve tops to the frame.
static func _jack_mounts(h: MeshKits) -> void:
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	for s: float in [-1.0, 1.0]:
		var z := s * JACK_Z
		dark.slab(JACK_X - 0.15, JACK_X + 0.15, 0.85, 1.15, 0.16, z, 0.02)
		dark.rod(Vector3(JACK_X, 0.95, z), Vector3.UP, 0.09, 0.7, 12, 0.015)
		dark.rod(Vector3(JACK_X, 1.27, z), Vector3.UP, 0.105, 0.06, 12, 0.01)
		steel.tube(
			[
				Vector3(JACK_X + 0.08, 1.24, z),
				Vector3(JACK_X + 0.12, 1.3, z - s * 0.05),
				Vector3(JACK_X + 0.1, 1.3, z - s * 0.2)
			],
			0.015,
			5
		)


# --- Launcher -----------------------------------------------------------------------------------


## The "Launcher" turntable stands behind the engines; its "Pod" child (the tube bundle with its
## cradle) hinges on the trunnions at the bundle's rear end, +X forward along the tubes:
## "Mouth0".."Mouth15" lie just in front of the muzzles. The tubes are stowed facing forward
## (MECHANISMS launcher `stowed: front`, read by UnitModels.launcher_aim).
static func _build_launcher(g: Node3D, f: Frame, m: Dictionary) -> void:
	var launcher := Node3D.new()
	launcher.name = "Launcher"
	launcher.position = f.p(TURNTABLE.x, TURNTABLE.y)
	g.add_child(launcher)
	var to_launcher := Frame.to_local(launcher)
	var top := ModelParts.cached_meshes(
		"bm27_uragan:launcher", func() -> Dictionary: return _launcher_meshes(f, to_launcher)
	)
	MeshKits.add_meshes(launcher, top, m)
	var pod := Node3D.new()
	pod.name = "Pod"
	pod.position = f.p(HINGE.x, HINGE.y) - launcher.position
	pod.set_meta(&"rest", pod.transform)
	launcher.add_child(pod)
	var to_pod := Frame.to_local(pod)
	var bundle := ModelParts.cached_meshes(
		"bm27_uragan:pod", func() -> Dictionary: return _pod_meshes(f, to_pod)
	)
	MeshKits.add_meshes(pod, bundle, m)
	var index := 0
	for row in TUBE_ROWS.size():
		for z: float in COLUMNS_4 if row == 2 else COLUMNS_6:
			var mouth := Node3D.new()
			mouth.name = "Mouth%d" % index
			index += 1
			mouth.position = to_pod * f.p(TUBE_X0 - 0.1, TUBE_ROWS[row], z)
			pod.add_child(mouth)
	_build_actuators(f, launcher, pod, m)
	UnitModels.pose_launcher(g, 0.0, 0.0)


## On `Launcher`: turntable ring with its bolt circle, the upper carriage (sloped front, bolted
## cover plates), side girders to the trunnion brackets, trunnion bosses, hydraulic lines.
static func _launcher_meshes(f: Frame, to_launcher: Transform3D) -> Dictionary:
	var t := MeshKits.new(f, to_launcher)
	var body := t.k(&"body")
	var dark := t.k(&"dark")
	var ring_top := Vector3(TURNTABLE.x, TURNTABLE.y + 0.11, 0.0)
	dark.rod(ring_top, Vector3.UP, TURNTABLE_RING_R, 0.1, 32, 0.02)
	for i in 20:
		var a := TAU * i / 20.0
		var at := Vector3(TURNTABLE.x + cos(a) * 0.86, TURNTABLE.y + 0.16, sin(a) * 0.86)
		dark.bolt(at, Vector3.UP, 0.025)
	var carriage := [
		Vector2(4.95, 1.62),
		Vector2(7.0, 1.62),
		Vector2(7.0, 2.18),
		Vector2(5.55, 2.18),
		Vector2(4.95, 1.86)
	]
	body.profile(carriage, 0.85, 0.0, 0.04)
	for x: float in [5.75, 6.4]:
		body.slab(x, x + 0.55, 2.18, 2.195, 0.7, 0.0, 0.005)
		for z: float in [-0.6, 0.0, 0.6]:
			body.bolt(Vector3(x + 0.04, 2.195, z), Vector3.UP, 0.016)
			body.bolt(Vector3(x + 0.51, 2.195, z), Vector3.UP, 0.016)
	for s: float in [-1.0, 1.0]:
		var girder := [Vector2(6.8, 1.62), Vector2(8.6, 1.62), Vector2(8.6, 2.2), Vector2(7.4, 2.2)]
		body.profile(girder, 0.07, s * 0.72, 0.02)
		body.slab(8.05, 8.55, 1.9, 2.55, 0.06, s * 0.9, 0.02)
		dark.rod(Vector3(HINGE.x, HINGE.y, s * 0.98), Vector3.BACK, 0.12, 0.06, 14, 0.012)
		for d: Vector2 in [Vector2(8.13, 2.0), Vector2(8.47, 2.0), Vector2(8.13, 2.45)]:
			body.bolt(Vector3(d.x, d.y, s * 0.96), Vector3.BACK * s, 0.02)
		# Hydraulic line along the carriage side up to the actuator anchor.
		dark.tube(
			[
				Vector3(6.9, 1.75, s * 0.86),
				Vector3(6.6, 1.8, s * 0.87),
				Vector3(6.4, 1.82, s * 0.87),
				Vector3(6.35, 1.85, s * 0.6)
			],
			0.018,
			5
		)
	return t.commit_all()


## On `Launcher/Pod`: the 16 tubes (open muzzles with rims and a dark bore; the four inner tubes
## of the middle row, hidden by their neighbours, as plain 8-sided shells), the stepped muzzle
## frame with bolts, clamp bands, cradle beams with hydraulic lines, the trunnion axle and the
## faction band. Nothing reaches behind the trunnions further than TUBE_X1, so the raised bundle
## stays above the engine compartment (LAUNCHER_CLEARANCE_H).
static func _pod_meshes(f: Frame, to_pod: Transform3D) -> Dictionary:
	var p := MeshKits.new(f, to_pod)
	var body := p.k(&"body")
	var dark := p.k(&"dark")
	var along := Frame.axis_basis(Vector3.RIGHT)
	var length := TUBE_X1 - TUBE_X0
	var r := TUBE_RADIUS
	var muzzle := [
		Vector2(r, MUZZLE_SECTION),
		Vector2(r, 0.07),
		Vector2(r + 0.012, 0.06),
		Vector2(r + 0.012, 0.012),
		Vector2(r, 0.0),
		Vector2(BORE_RADIUS, 0.0)
	]
	var bore := [
		Vector2(BORE_RADIUS, 0.0), Vector2(BORE_RADIUS, BORE_DEPTH), Vector2(0.0, BORE_DEPTH)
	]
	for row in TUBE_ROWS.size():
		for z: float in COLUMNS_4 if row == 2 else COLUMNS_6:
			var c := Vector3(TUBE_X0, TUBE_ROWS[row], z)
			var hidden := row == 1 and absf(z) < 0.5
			body.lathe(c, along, muzzle, 16)
			dark.openness = 0.12
			dark.lathe(c, along, bore, 12)
			dark.openness = 1.0
			var rest := [
				Vector2(0.0, length),
				Vector2(r - 0.015, length),
				Vector2(r, length - 0.015),
				Vector2(r, MUZZLE_SECTION)
			]
			body.lathe(c, along, rest, 8 if hidden else 14)
	_muzzle_frame(p)
	for x: float in [5.6, 8.0]:
		_clamp_band(p, x)
	dark.pair(TUBE_X0 + 0.5, HINGE.x - 0.05, 2.2, 2.34, 0.07, 0.5, 0.015)  # cradle beams
	dark.slab(ACTUATOR_MOUNT.x - 0.12, ACTUATOR_MOUNT.x + 0.12, 2.18, 2.34, 0.6, 0.0, 0.015)
	dark.rod(Vector3(HINGE.x, HINGE.y, 0.0), Vector3.BACK, 0.09, 1.9, 12, 0.012)  # trunnion axle
	for s: float in [-1.0, 1.0]:
		var line := []
		for i in 7:
			var x := lerpf(HINGE.x - 0.1, TUBE_X0 + 0.7, i / 6.0)
			line.append(Vector3(x, 2.25 - 0.01 * sin(i * 0.9), s * 0.585))
		dark.tube(line, 0.016, 5)
	p.k(&"accent").pair(TUBE_X0 + 0.15, TUBE_X0 + 0.5, 2.45, 2.8, 0.008, 0.88, 0.003)
	return p.commit_all()


## Stepped muzzle frame: lower box around the two rows of six, narrower top box around the four,
## bolted side plates, lifting eyes on the sides.
static func _muzzle_frame(p: MeshKits) -> void:
	var body := p.k(&"body")
	var dark := p.k(&"dark")
	var x0 := TUBE_X0 + 0.08
	var x1 := TUBE_X0 + 0.58
	var low := TUBE_ROWS[0] - 0.18
	var mid := TUBE_ROWS[1] + 0.18
	var top := TUBE_ROWS[2] + 0.16
	body.pair(x0, x1, low, mid, 0.04, 0.84, 0.015)
	body.pair(x0, x1, mid - 0.05, top, 0.04, 0.57, 0.015)
	body.slab(x0, x1, low - 0.04, low + 0.02, 0.88, 0.0, 0.015)
	body.pair(x0, x1, mid - 0.05, mid + 0.01, 0.16, 0.72, 0.015)
	body.slab(x0, x1, top - 0.04, top + 0.04, 0.61, 0.0, 0.015)
	for s: float in [-1.0, 1.0]:
		for x: float in [x0 + 0.06, x1 - 0.06]:
			for hh: float in [low + 0.1, (low + mid) / 2.0, mid - 0.1]:
				body.bolt(Vector3(x, hh, s * 0.88), Vector3.BACK * s, 0.018)
		var eye := MeshKit.arc(
			Vector3((x0 + x1) / 2.0, top - 0.06, s * 0.61),
			0.05,
			Vector3.RIGHT,
			Vector3.BACK * s,
			0.0,
			PI,
			6
		)
		dark.tube(eye, 0.012, 4)


## Clamp band around the bundle at x: lower and upper stepped boxes, bolted tension lugs on the
## sides.
static func _clamp_band(p: MeshKits, x: float) -> void:
	var body := p.k(&"body")
	var low := TUBE_ROWS[0] - 0.18
	var mid := TUBE_ROWS[1] + 0.18
	var top := TUBE_ROWS[2] + 0.16
	body.slab(x - 0.06, x + 0.06, low, mid - 0.03, 0.83, 0.0, 0.015)
	body.slab(x - 0.06, x + 0.06, mid - 0.03, top - 0.04, 0.56, 0.0, 0.015)
	for s: float in [-1.0, 1.0]:
		body.slab(x - 0.09, x + 0.09, mid - 0.1, mid + 0.02, 0.05, s * 0.85, 0.01)
		body.bolt(Vector3(x, mid + 0.02, s * 0.85), Vector3.UP, 0.02)
		body.bolt(Vector3(x, top - 0.04, s * 0.4), Vector3.UP, 0.018)


## Two elevation actuators: "Actuator<i>" (dark cylinder with a gland ring, base clevis and
## hydraulic port, from its turntable anchor) and "ActuatorRod<i>" (steel piston with its end eye,
## from the "ActuatorMount<i>" under the pod), both along local +Y in metres x K.
static func _build_actuators(f: Frame, launcher: Node3D, pod: Node3D, m: Dictionary) -> void:
	var to_launcher := Frame.to_local(launcher)
	var to_pod := Frame.to_local(pod)
	var cylinder := ModelParts.cached_meshes("bm27_uragan:cylinder", _cylinder_meshes)
	var piston := ModelParts.cached_meshes("bm27_uragan:piston", _piston_meshes)
	for i in 2:
		var z := ACTUATOR_Z * (-1.0 if i == 0 else 1.0)
		var barrel := Node3D.new()
		barrel.name = "Actuator%d" % i
		barrel.position = to_launcher * f.p(ACTUATOR_BASE.x, ACTUATOR_BASE.y, z)
		launcher.add_child(barrel)
		MeshKits.add_meshes(barrel, cylinder, m)
		var rod := Node3D.new()
		rod.name = "ActuatorRod%d" % i
		launcher.add_child(rod)
		MeshKits.add_meshes(rod, piston, m)
		var mount := Node3D.new()
		mount.name = "ActuatorMount%d" % i
		mount.position = to_pod * f.p(ACTUATOR_MOUNT.x, ACTUATOR_MOUNT.y, z)
		pod.add_child(mount)


static func _metre_kits() -> MeshKits:
	return MeshKits.new(null, Transform3D(Basis.from_scale(Vector3.ONE * K), Vector3.ZERO))


static func _cylinder_meshes() -> Dictionary:
	var kits := _metre_kits()
	var dark := kits.k(&"dark")
	var length := CYLINDER_LENGTH
	dark.rod(Vector3(0, length / 2.0, 0), Vector3.UP, CYLINDER_RADIUS, length, 12, 0.02)
	dark.rod(Vector3(0, length - 0.05, 0), Vector3.UP, CYLINDER_RADIUS + 0.015, 0.08, 12, 0.012)
	dark.rod(Vector3(0, 0.0, 0), Vector3.BACK, 0.07, 0.16, 10, 0.012)
	dark.cbox(Vector3(CYLINDER_RADIUS, 0.3, 0), Vector3(0.05, 0.08, 0.06), 0.01)
	dark.tube(
		[
			Vector3(CYLINDER_RADIUS + 0.02, 0.3, 0),
			Vector3(CYLINDER_RADIUS + 0.03, length - 0.15, 0)
		],
		0.012,
		5
	)
	return kits.commit_all()


static func _piston_meshes() -> Dictionary:
	var kits := _metre_kits()
	var steel := kits.k(&"steel")
	steel.rod(
		Vector3(0, PISTON_LENGTH / 2.0, 0), Vector3.UP, PISTON_RADIUS, PISTON_LENGTH, 10, 0.01
	)
	steel.rod(Vector3(0, 0.0, 0), Vector3.BACK, 0.06, 0.14, 10, 0.012)
	return kits.commit_all()


# --- Deployables --------------------------------------------------------------------------------


## "Stabiliser0/1" (left, right): telescopic leg with a round chamfered foot pad sliding down out
## of the fixed sleeves in the hull; meta "deployed" = the pivot lowered until the pad touches
## y = 0.
static func _build_jacks(g: Node3D, f: Frame, m: Dictionary) -> void:
	for i in 2:
		var z := JACK_Z * (-1.0 if i == 0 else 1.0)
		var jack := Node3D.new()
		jack.name = "Stabiliser%d" % i
		g.add_child(jack)
		var meshes := ModelParts.cached_meshes(
			"bm27_uragan:jack%d" % i, func() -> Dictionary: return _jack_meshes(f, z)
		)
		MeshKits.add_meshes(jack, meshes, m)
		jack.set_meta(
			&"deployed", Transform3D(Basis.IDENTITY, Vector3(0.0, -JACK_STOWED_H * f.k, 0.0))
		)


static func _jack_meshes(f: Frame, z: float) -> Dictionary:
	var kits := MeshKits.new(f)
	var steel := kits.k(&"steel")
	var rod_bottom := JACK_STOWED_H + 0.1
	var leg := JACK_ROD_TOP - rod_bottom
	steel.rod(Vector3(JACK_X, rod_bottom + leg / 2.0, z), Vector3.UP, 0.06, leg, 10, 0.01)
	var r := JACK_PAD_RADIUS
	var bottom := JACK_STOWED_H
	var pad := [
		Vector2(0.0, bottom + 0.1),
		Vector2(0.07, bottom + 0.1),
		Vector2(r - 0.01, bottom + 0.035),
		Vector2(r, bottom + 0.025),
		Vector2(r, bottom + 0.008),
		Vector2(r - 0.008, bottom),
		Vector2(0.0, bottom)
	]
	steel.lathe(Vector3(JACK_X, 0.0, z), Basis.IDENTITY, pad, 16)
	steel.rod(Vector3(JACK_X, rod_bottom + 0.02, z), Vector3.UP, 0.075, 0.04, 10, 0.008)
	return kits.commit_all()


## "BlastShield0..2" over the windscreen panes, "BlastShield3/4" over the door windows. Built pose
## = open, meta "deployed" = closed in front of the glass. Chamfered armour plates with a
## stiffener rib, hinge knuckles on the hinge line and a handle.
static func _build_shields(g: Node3D, m: Dictionary) -> void:
	var f := vehicle_frame()
	var index := 0
	var screen_closed := Basis(Vector3.BACK, PI / 2.0 + SCREEN_RAKE)
	var screen := ModelParts.cached_meshes("bm27_uragan:screen_shield", _screen_shield_meshes)
	for z: float in SCREEN_Z:
		var pivot := Node3D.new()
		pivot.name = "BlastShield%d" % index
		index += 1
		pivot.position = f.p(SCREEN_HINGE.x, SCREEN_HINGE.y, z)
		g.add_child(pivot)
		MeshKits.add_meshes(pivot, screen, m)
		pivot.set_meta(&"deployed", Transform3D(screen_closed, pivot.position))
	for s: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "BlastShield%d" % index
		index += 1
		pivot.position = f.p(SIDE_HINGE.x, SIDE_HINGE.y, s * SIDE_HINGE.z)
		pivot.basis = Basis(Vector3.RIGHT, -s * PI / 2.0)
		g.add_child(pivot)
		var side := ModelParts.cached_meshes(
			"bm27_uragan:side_shield%d" % int(s),
			func() -> Dictionary: return _side_shield_meshes(s)
		)
		MeshKits.add_meshes(pivot, side, m)
		pivot.set_meta(&"deployed", Transform3D(Basis.IDENTITY, pivot.position))


## Windscreen shield in its pivot's space (metres x K): the plate reaches forward from the hinge
## line (local z) lying open; ribs on the face that is up when open.
static func _screen_shield_meshes() -> Dictionary:
	var kits := _metre_kits()
	var body := kits.k(&"body")
	var t := SHIELD_THICKNESS
	body.cbox(Vector3(SCREEN_LENGTH / 2.0, -0.065, 0.0), Vector3(SCREEN_LENGTH, t, 0.74), 0.012)
	for z: float in [-0.25, 0.25]:
		body.cbox(Vector3(0.26, -0.03, z), Vector3(0.42, 0.025, 0.04), 0.008)
	for z: float in [-0.3, 0.0, 0.3]:
		body.rod(Vector3(0.0, -0.065, z), Vector3.BACK, 0.03, 0.12, 8, 0.006)
	body.tube(
		[
			Vector3(0.47, -0.04, -0.08),
			Vector3(0.5, -0.0, -0.06),
			Vector3(0.5, -0.0, 0.06),
			Vector3(0.47, -0.04, 0.08)
		],
		0.01,
		5
	)
	return kits.commit_all()


## Door-window shield on side `s` in its pivot's space (metres x K): the plate hangs from the hinge
## line (local x) down local -y, a rib and a handle on its outer face (+z s).
static func _side_shield_meshes(s: float) -> Dictionary:
	var kits := _metre_kits()
	var body := kits.k(&"body")
	var t := SHIELD_THICKNESS
	body.cbox(
		Vector3(0.0, -SIDE_SHIELD.y / 2.0, s * t / 2.0),
		Vector3(SIDE_SHIELD.x, SIDE_SHIELD.y, t),
		0.012
	)
	body.cbox(Vector3(0.0, -0.3, s * (t + 0.012)), Vector3(0.7, 0.04, 0.025), 0.008)
	for x: float in [-0.3, 0.0, 0.3]:
		body.rod(Vector3(x, 0.0, s * t / 2.0), Vector3.RIGHT, 0.03, 0.12, 8, 0.006)
	body.tube(
		[
			Vector3(-0.08, -0.47, s * t),
			Vector3(-0.06, -0.47, s * (t + 0.04)),
			Vector3(0.06, -0.47, s * (t + 0.04)),
			Vector3(0.08, -0.47, s * t)
		],
		0.01,
		5
	)
	return kits.commit_all()
