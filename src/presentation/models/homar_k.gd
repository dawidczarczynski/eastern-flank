## Homar-K (K239PL): Polish 8x8 rocket launcher – Korean K239 Chunmoo launcher module (two closed
## pods of six 239 mm rockets) on the armoured Jelcz P882.57 cab-over chassis. Blueprint:
## docs/design/units/units/homar_k/blueprint.md. Measurements are metres (vehicle_frame.gd): `x`
## from the front bumper (0) to the rear (LENGTH_M), `h` above the ground, `z` across (positive =
## vehicle's right). The pod is stowed (level, tube ends facing the rear).
##
## Built with MeshKit (TASK-073, ADR 0012) like the v3 tanks: chamfered plates, bolts, hinges,
## handles, hydraulic lines; the shared WheeledRunningGear builds the tyres. Hidden geometry is cut
## (nothing inside the cab or the pod box, plain inner wheel halves, the frame as one box). The
## geometry does not depend on the faction, so it is generated once (ModelParts.cached_meshes) and
## only the materials differ.

## Label anchor height above the unit's feet (world units, read by UnitModels.label_height).
const LABEL_HEIGHT := 0.62
## Catalog mechanisms of the unit; a test keeps them equal to its unit.json.
const MECHANISMS := {
	"wheels": {},
	"stabilisers": {},
	"launcher": {"traverse_deg": "full", "max_elevation_deg": 40, "stowed": "rear"},
}
const Frame := preload("res://src/presentation/models/parts/vehicle_frame.gd")
const Gear := preload("res://src/presentation/models/parts/wheeled_running_gear.gd")

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
## Turntable centre (x, h) under the launcher: the "Launcher" node traverses about it; radius of
## the fixed bearing ring on the deck.
const TURNTABLE_X := 8.6
const TURNTABLE_H := 2.0
const TURNTABLE_RING_R := 1.0
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
## Armoured cab: x range, bottom, roof, half width.
const CAB_X0 := 0.1
const CAB_X1 := 3.15
const CAB_H0 := 1.45
const CAB_ROOF_H := 3.25
const CAB_HW := 1.27
## Middle module between the equipment block and the pod: front, end of the flat top, rear face
## (below MODULE_SLOPE_H); the rear slopes back so the raised pod's front face clears it at every
## traverse angle (see LAUNCHER_CLEARANCE_H and the blueprint).
const MODULE_X0 := 4.6
const MODULE_TOP_X1 := 5.42
const MODULE_X1 := 6.02
const MODULE_SLOPE_H := 1.95
const MODULE_H0 := 1.3
const MODULE_H1 := 2.85
const MODULE_HW := 1.2
## Rear deck over the rear axles (top h) and the launcher carriage on the turntable (girder |z|).
const DECK_H := 1.66
const CARRIAGE_H0 := 1.7
const GIRDER_Z := 1.1
## Exhaust stack outlet (x, h, z).
const EXHAUST := Vector3(4.47, 3.3, 0.9)
## Boxes strictly inside closed shells (vehicle metres: position = (x from the front, h, z)), at
## rest: the cab and the pod box. No triangle may lie entirely inside one (test_mlrs_models.gd).
const HULL_INTERIOR: Array[AABB] = [
	AABB(Vector3(0.5, 1.7, -0.95), Vector3(2.3, 1.3, 1.9)),
	AABB(Vector3(7.0, 2.2, -1.15), Vector3(3.4, 0.95, 2.3)),
]
## Lowest point of the pod outside the turntable ring when raised (its hinge edge, m): every hull
## part the raised pod sweeps over at any traverse angle stays below it.
const LAUNCHER_CLEARANCE_H := POD_H0
## Dark parts (frame, bumpers, launcher carriage): one-colour paint with worn edges, dust and mud
## low on the chassis.
const DARK_PAINT := {
	"color": Color("#2a2b25"),
	"base_roughness": 0.7,
	"metallic": 0.25,
	"wear_amount": 0.45,
	"tint_amount": 0.15,
	"dust_amount": 0.45,
	"mud_height": 0.1,
	"mud_amount": 0.6,
}


## The "Launcher" turntable sits on the rear deck; its "Pod" child hinges on the front-bottom
## edge of the launcher box, turned so its +X runs to the rear: "Mouth0".."Mouth11" lie just
## behind the tube ends (the volley effect spawns rockets there). UnitModels.pose_launcher
## traverses the Launcher, elevates the Pod about its local Z and aims the two actuators.
static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var frame := vehicle_frame()
	var m := materials(faction)
	var spec := running_gear()
	Gear.add_pivots(g, frame, spec, m)
	var hull := ModelParts.cached_meshes(
		"homar_k:hull", func() -> Dictionary: return _hull_meshes(frame, spec)
	)
	MeshKits.add_meshes(g, hull, m)
	_anchors(g, frame)
	_build_jacks(g, frame, m)
	_build_launcher(g, frame, m)
	ModelParts.declare_mechanisms(g, MECHANISMS)
	return g


## Metres -> model space: K model units per metre, the truck's length centred on x = 0.
static func vehicle_frame() -> Frame:
	return Frame.new(K, LENGTH_M / 2.0)


## Materials by role: faction camo body and accent, weathered dark paint, plain steel, glass,
## rubber and light lenses.
static func materials(faction: FactionDefinition) -> Dictionary:
	return {
		&"body": ModelParts.faction_material(faction, &"truck_body"),
		&"dark": ModelParts.weathered_paint("homar_k:dark", DARK_PAINT),
		&"steel": ModelParts.pbr(ModelParts.STEEL),
		&"glass": ModelParts.pbr(ModelParts.GLASS),
		&"rubber": ModelParts.pbr(ModelParts.RUBBER),
		&"accent": ModelParts.accent(faction),
		&"lens": ModelParts.std_material(Color("#c9c4b0"), 0.1, 0.3),
		&"red_lens": ModelParts.std_material(Color("#6a1410"), 0.15, 0.2),
	}


## Jelcz P882.57 wheels: 8 large off-road tyres with directional lugs, steel discs with a bolt
## ring and the central tyre-inflation hub; mudflaps behind the rear axle.
static func running_gear() -> Gear.Spec:
	var spec := Gear.Spec.new()
	spec.key = "homar_k"
	spec.axle_x = AXLES
	spec.wheel_radius = WHEEL_RADIUS
	spec.tyre_width = TYRE_WIDTH
	spec.track_z = WHEEL_Z
	spec.wheel_sides = 18
	spec.tread_lugs = 16
	spec.lug_depth = 0.04
	spec.hub_bolts = 10
	spec.inflation_hub = true
	spec.mudflap_x = [10.3] as Array[float]
	spec.mudflap_top_h = DECK_H - 0.2
	spec.mudflap_bottom_h = 0.42
	return spec


## Effect anchors for MotionFx (TASK-064): the exhaust stack outlet, dust behind the rear tyres.
static func _anchors(g: Node3D, frame: Frame) -> void:
	var dust_x := AXLES[AXLES.size() - 1] + WHEEL_RADIUS * 0.9
	var at := {
		"Exhaust": frame.p(EXHAUST.x, EXHAUST.y + 0.02, EXHAUST.z),
		"Dust_L": frame.p(dust_x, 0.02, -WHEEL_Z),
		"Dust_R": frame.p(dust_x, 0.02, WHEEL_Z),
	}
	for name: String in at:
		var marker := Marker3D.new()
		marker.name = name
		marker.position = at[name]
		g.add_child(marker)


static func _hull_meshes(frame: Frame, spec: Gear.Spec) -> Dictionary:
	var h := MeshKits.new(frame)
	_cab(h)
	_cab_front(h)
	for s: float in [-1.0, 1.0]:
		_cab_side(h, s)
	_equipment(h)
	_module(h)
	_chassis(h)
	_rear(h)
	_turntable_base(h)
	Gear.add_hull_parts(h, spec)
	return h.commit_all()


# --- Cab ----------------------------------------------------------------------------------------


## Armoured cab-over cab as one chamfered side profile (slightly raked windscreen, rounded roof
## edges), the underside between the front wheels, roof hatch, armour seams, antenna bases.
static func _cab(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var outline := [
		Vector2(0.14, CAB_H0),
		Vector2(CAB_X0, 1.6),
		Vector2(CAB_X0, 2.32),
		Vector2(0.17, 3.12),
		Vector2(0.32, CAB_ROOF_H),
		Vector2(3.02, CAB_ROOF_H),
		Vector2(CAB_X1, 3.12),
		Vector2(CAB_X1, CAB_H0),
	]
	body.profile(outline, CAB_HW, 0.0, 0.06)
	dark.slab(0.3, 3.1, 1.0, CAB_H0, 0.86, 0.0, 0.03)
	# Roof: hatch with hinge, a raised armour plate seam across, antenna bases at the rear corners.
	body.rod(Vector3(2.2, CAB_ROOF_H + 0.03, -0.45), Vector3.UP, 0.3, 0.06, 16, 0.015)
	h.k(&"steel").rod(Vector3(1.9, CAB_ROOF_H + 0.05, -0.45), Vector3.BACK, 0.025, 0.24, 8)
	body.slab(1.2, 1.26, CAB_ROOF_H, CAB_ROOF_H + 0.02, 1.15, 0.0, 0.008)
	for s: float in [-1.0, 1.0]:
		dark.rod(Vector3(2.9, CAB_ROOF_H + 0.025, s * 1.05), Vector3.UP, 0.05, 0.05, 10, 0.01)
		h.k(&"steel").rod(Vector3(2.9, CAB_ROOF_H + 0.09, s * 1.05), Vector3.UP, 0.014, 0.08, 6)


## Cab front: two windscreen panes in thick frames with wipers, grille slats, faction plate,
## bumper with headlights in wire guards, tow hooks, front steps.
static func _cab_front(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var rake := atan2(0.07, 0.8)
	var lean := Basis(Vector3.BACK, -rake)
	var face_x := func(hh: float) -> float: return CAB_X0 + (hh - 2.32) * 0.07 / 0.8
	for zc: float in [-0.6, 0.6]:
		var pane_h := 2.66
		var at := Vector3(face_x.call(pane_h) - 0.004, pane_h, zc)
		h.k(&"glass").cbox(at, Vector3(0.01, 0.56, 0.86), 0.0, lean)
		# Wiper: pivot on the lower frame, arm and blade.
		var root := Vector3(face_x.call(2.4) - 0.03, 2.4, zc + 0.3)
		var tip := Vector3(face_x.call(2.8) - 0.03, 2.8, zc - 0.05)
		dark.tube([root, tip], 0.01, 5)
		dark.tube([tip + Vector3(0, -0.12, 0.05), tip + Vector3(0.02, 0.18, -0.06)], 0.012, 5)
	# Windscreen frame: bottom, top and centre posts, side posts.
	for hh: float in [2.35, 2.97]:
		body.cbox(Vector3(face_x.call(hh) - 0.02, hh, 0.0), Vector3(0.05, 0.07, 2.3), 0.015, lean)
	for zc: float in [-1.12, 0.0, 1.12]:
		var at := Vector3(face_x.call(2.66) - 0.02, 2.66, zc)
		body.cbox(at, Vector3(0.05, 0.66, 0.1 if zc == 0.0 else 0.16), 0.015, lean)
	# Grille slats under the windscreen, faction plate above them.
	dark.openness = 0.3
	dark.slab(CAB_X0 - 0.005, CAB_X0 + 0.01, 1.62, 1.96, 0.72, 0.0, 0.0)
	dark.openness = 1.0
	for i in 5:
		var hh := 1.66 + i * 0.07
		body.cbox(Vector3(CAB_X0 - 0.02, hh, 0.0), Vector3(0.03, 0.025, 1.44), 0.008)
	h.k(&"accent").slab(CAB_X0 - 0.02, CAB_X0 + 0.01, 2.06, 2.24, 0.5, 0.0, 0.006)
	# Bumper: chamfered beam with a lower lip, headlights in guards, tow hooks, number plate.
	(
		dark
		. profile(
			[
				Vector2(-0.02, 1.0),
				Vector2(-0.02, 1.34),
				Vector2(0.03, 1.38),
				Vector2(0.32, 1.38),
				Vector2(0.32, 0.95),
				Vector2(0.06, 0.95),
			],
			1.25,
			0.0,
			0.03
		)
	)
	for s: float in [-1.0, 1.0]:
		var z := s * 0.98
		dark.rod(Vector3(-0.04, 1.2, z), Vector3.LEFT, 0.1, 0.06, 14, 0.015)
		h.k(&"lens").rod(Vector3(-0.075, 1.2, z), Vector3.LEFT, 0.08, 0.012, 14)
		var guard := [
			Vector3(-0.02, 1.08, z - 0.13),
			Vector3(-0.09, 1.08, z - 0.13),
			Vector3(-0.09, 1.32, z - 0.13),
			Vector3(-0.09, 1.32, z + 0.13),
			Vector3(-0.09, 1.08, z + 0.13),
			Vector3(-0.02, 1.08, z + 0.13),
		]
		steel.tube(guard, 0.01, 5)
		steel.tube([Vector3(-0.09, 1.08, z), Vector3(-0.09, 1.32, z)], 0.008, 4)
		# Tow hook: a bracket and a hook loop under the bumper.
		dark.slab(-0.04, 0.08, 0.92, 1.04, 0.07, s * 0.55, 0.012)
		var hook := MeshKit.arc(
			Vector3(-0.03, 0.97, s * 0.55), 0.05, Vector3.UP, Vector3.LEFT, -1.4, 1.9, 9
		)
		steel.tube(hook, 0.022, 7)
		# Front steps: two tread plates on a bracket in front of the first axle.
		_step(h, 0.22, 0.84, [0.82, 1.12], s * 1.18)
	body.slab(-0.03, 0.0, 1.06, 1.24, 0.28, 0.0, 0.005)
	for i in 6:
		body.bolt(Vector3(-0.02, 1.36, -1.0 + i * 0.4), Vector3.UP, 0.02)


## One cab side `s`: two doors (seams, hinges, handles, windows in thick frames, the front door's
## faction plate), door steps, grab handles, mirror on its arm.
static func _cab_side(h: MeshKits, s: float) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var face := s * CAB_HW
	# Doors: x0, x1, window x0, x1.
	for door: Array in [[0.42, 1.36, 0.5, 1.26], [1.88, 2.8, 1.97, 2.7]]:
		var x0: float = door[0]
		var x1: float = door[1]
		var seam := func(a: Vector3, b: Vector3) -> void:
			var c := (a + b) / 2.0
			var size := (b - a).abs() + Vector3(0.016, 0.016, 0.0)
			size.z = 0.01
			dark.cbox(c + Vector3(0, 0, s * 0.002), size, 0.0)
		seam.call(Vector3(x0, 1.55, face), Vector3(x0, 3.02, face))
		seam.call(Vector3(x1, 1.55, face), Vector3(x1, 3.02, face))
		seam.call(Vector3(x0, 3.02, face), Vector3(x1, 3.02, face))
		seam.call(Vector3(x0, 1.55, face), Vector3(x1, 1.55, face))
		for hh: float in [1.85, 2.75]:
			steel.rod(Vector3(x0 + 0.03, hh, face + s * 0.02), Vector3.UP, 0.024, 0.16, 8, 0.006)
			body.cbox(Vector3(x0 + 0.09, hh, face + s * 0.012), Vector3(0.12, 0.1, 0.024), 0.008)
		var grip_x := x1 - 0.1
		var handle := [
			Vector3(grip_x, 2.25, face),
			Vector3(grip_x, 2.25, face + s * 0.05),
			Vector3(grip_x - 0.18, 2.25, face + s * 0.05),
			Vector3(grip_x - 0.18, 2.25, face),
		]
		steel.tube(handle, 0.014, 6)
		# Window: glass flush in the armour, thick frame around it.
		var wx0: float = door[2]
		var wx1: float = door[3]
		var wh0 := 2.39
		var wh1 := 2.92
		h.k(&"glass").slab(wx0, wx1, wh0, wh1, 0.006, face + s * 0.002, 0.0)
		var fz := face + s * 0.016
		body.slab(wx0 - 0.06, wx1 + 0.06, wh1, wh1 + 0.06, 0.016, fz, 0.008)
		body.slab(wx0 - 0.06, wx1 + 0.06, wh0 - 0.06, wh0, 0.016, fz, 0.008)
		body.slab(wx0 - 0.06, wx0, wh0, wh1, 0.016, fz, 0.008)
		body.slab(wx1, wx1 + 0.06, wh0, wh1, 0.016, fz, 0.008)
	h.k(&"accent").slab(0.58, 1.2, 1.72, 2.05, 0.008, face + s * 0.004, 0.004)
	# Grab handles beside the doors, door step between the front axles, armour seam.
	for x: float in [0.3, 1.74]:
		var rail := [
			Vector3(x, 1.75, face),
			Vector3(x, 1.75, face + s * 0.06),
			Vector3(x, 2.65, face + s * 0.06),
			Vector3(x, 2.65, face),
		]
		steel.tube(rail, 0.016, 6)
	_step(h, 2.62, 2.96, [0.86, 1.14], s * 1.18)
	dark.cbox(Vector3(1.62, 2.2, face + s * 0.002), Vector3(0.38, 0.012, 0.01), 0.0)
	dark.cbox(Vector3(2.97, 2.2, face + s * 0.002), Vector3(0.3, 0.012, 0.01), 0.0)
	# Mirror: arm from the cab's front corner, mirror head with a dark back.
	var arm := [
		Vector3(0.25, 2.98, face),
		Vector3(0.12, 3.0, s * 1.35),
		Vector3(0.06, 2.95, s * 1.4),
		Vector3(0.06, 2.84, s * 1.4),
	]
	steel.tube(arm, 0.016, 6)
	dark.cbox(Vector3(0.06, 2.62, s * 1.4), Vector3(0.06, 0.42, 0.1), 0.015)


## Step: tread plates (x0..x1) at the heights `treads` on two side brackets, at z.
static func _step(h: MeshKits, x0: float, x1: float, treads: Array, z: float) -> void:
	var dark := h.k(&"dark")
	for hh: float in treads:
		dark.slab(x0, x1, hh - 0.02, hh + 0.02, 0.09, z, 0.008)
		for i in 3:
			var x := lerpf(x0 + 0.06, x1 - 0.06, i / 2.0)
			dark.cbox(Vector3(x, hh + 0.025, z), Vector3(0.02, 0.012, 0.16), 0.0)
	var top: float = treads[treads.size() - 1]
	for x: float in [x0 + 0.02, x1 - 0.02]:
		dark.slab(x - 0.015, x + 0.015, (treads[0] as float) - 0.04, top + 0.3, 0.07, z, 0.006)


# --- Body behind the cab ------------------------------------------------------------------------


## Equipment block behind the cab: chamfered housing, ribbed air-filter drums with clamp bands,
## louvred engine grilles, the exhaust stack with its heat shield and brackets.
static func _equipment(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	body.slab(CAB_X1, 4.4, 1.5, 2.85, 0.98, 0.0, 0.04)
	body.slab(CAB_X1 + 0.05, 4.35, 2.85, 2.9, 0.9, 0.0, 0.015)
	for s: float in [-1.0, 1.0]:
		var c := Vector3(3.5, 2.45, s * 1.06)
		var basis := Frame.axis_basis(Vector3(0, 0, s))
		var prof := [
			Vector2(0.0, 0.1),
			Vector2(0.18, 0.1),
			Vector2(0.24, 0.088),
			Vector2(0.27, 0.07),
			Vector2(0.27, 0.05),
			Vector2(0.255, 0.044),
			Vector2(0.255, 0.012),
			Vector2(0.27, 0.006),
			Vector2(0.27, -0.03),
			Vector2(0.255, -0.036),
			Vector2(0.255, -0.064),
			Vector2(0.27, -0.07),
			Vector2(0.27, -0.1),
		]
		body.lathe(c, basis, prof, 16)
		dark.rod(c + Vector3(0, 0, s * 0.105), Vector3(0, 0, s), 0.06, 0.02, 8, 0.006)
		var band := MeshKit.arc(
			c + Vector3(0, 0, s * -0.01), 0.28, Vector3.UP, Vector3.RIGHT, 0.0, TAU, 16
		)
		steel.tube(band, 0.012, 5)
		steel.cbox(Vector3(3.5, 2.17, s * 1.02), Vector3(0.08, 0.04, 0.1), 0.006)
		# Engine grille: recessed dark panel with slanted slats and a frame.
		dark.openness = 0.25
		dark.slab(3.7, 4.3, 1.75, 2.35, 0.012, s * 0.976, 0.0)
		dark.openness = 1.0
		for i in 7:
			var hh := 1.8 + i * 0.08
			dark.cbox(
				Vector3(4.0, hh, s * 0.985),
				Vector3(0.56, 0.035, 0.012),
				0.0,
				Basis(Vector3.RIGHT, s * 0.5)
			)
		body.slab(3.66, 4.34, 2.35, 2.39, 0.014, s * 0.985, 0.006)
		body.slab(3.66, 4.34, 1.71, 1.75, 0.014, s * 0.985, 0.006)
	# Exhaust stack on the right with a rain cap, a heat shield on clamps and two brackets.
	var e := EXHAUST
	dark.rod(Vector3(e.x, (1.6 + e.y) / 2.0, e.z), Vector3.UP, 0.08, e.y - 1.6, 12, 0.01)
	dark.lathe(
		Vector3(e.x, e.y, e.z),
		Basis.IDENTITY,
		[Vector2(0.06, 0.0), Vector2(0.1, 0.0), Vector2(0.1, -0.06), Vector2(0.085, -0.08)],
		12
	)
	body.cbox(Vector3(e.x, 2.55, e.z + 0.11), Vector3(0.2, 1.0, 0.02), 0.006)
	for hh: float in [2.15, 2.95]:
		var clamp := MeshKit.arc(
			Vector3(e.x, hh, e.z), 0.095, Vector3.RIGHT, Vector3.BACK, 0.0, TAU, 12
		)
		steel.tube(clamp, 0.01, 4)
	for hh: float in [1.9, 2.7]:
		dark.slab(4.38, e.x - 0.07, hh - 0.02, hh + 0.02, 0.025, e.z, 0.006)


## Middle module (camo), its rear sloping away from the raised pod; side louvres, access panels
## with hinges and latches, lockers below it.
static func _module(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	var outline := [
		Vector2(MODULE_X0, MODULE_H0),
		Vector2(MODULE_X0, MODULE_H1 - 0.1),
		Vector2(MODULE_X0 + 0.1, MODULE_H1),
		Vector2(MODULE_TOP_X1, MODULE_H1),
		Vector2(MODULE_X1, MODULE_SLOPE_H),
		Vector2(MODULE_X1, MODULE_H0),
	]
	body.profile(outline, MODULE_HW, 0.0, 0.04)
	var face := MODULE_HW
	for s: float in [-1.0, 1.0]:
		var z := s * face
		# Two louvre panels.
		for x0: float in [4.98, 5.43]:
			dark.openness = 0.25
			dark.slab(x0, x0 + 0.38, 1.8, 2.15, 0.006, z, 0.0)
			dark.openness = 1.0
			for i in 5:
				var hh := 1.84 + i * 0.065
				dark.cbox(
					Vector3(x0 + 0.19, hh, z + s * 0.01),
					Vector3(0.36, 0.03, 0.012),
					0.0,
					Basis(Vector3.RIGHT, s * 0.6)
				)
		# Access panel above the louvres with hinges on top and two latches.
		dark.cbox(Vector3(4.8, 2.16, z), Vector3(0.012, 0.92, 0.01), 0.0)
		dark.cbox(Vector3(5.45, 2.36, z), Vector3(0.012, 0.52, 0.01), 0.0)
		dark.cbox(Vector3(5.125, 2.62, z), Vector3(0.65, 0.012, 0.01), 0.0)
		dark.cbox(Vector3(5.32, 1.7, z), Vector3(1.04, 0.012, 0.01), 0.0)
		for x: float in [4.95, 5.3]:
			steel.rod(Vector3(x, 2.6, z + s * 0.015), Vector3.RIGHT, 0.018, 0.14, 6)
		for x: float in [4.7, 5.0]:
			dark.cbox(Vector3(x, 1.5, z + s * 0.012), Vector3(0.06, 0.1, 0.024), 0.008)
		# Lockers below the module: two doors with hinges and latch handles.
		body.slab(4.85, 7.0, 0.85, MODULE_H0, 0.012, s * 1.05, 0.006)
		for x0: float in [4.9, 5.97]:
			dark.cbox(Vector3(x0 + 0.5, 0.87, s * 1.065), Vector3(1.0, 0.012, 0.01), 0.0)
			dark.cbox(Vector3(x0, 1.07, s * 1.065), Vector3(0.012, 0.4, 0.01), 0.0)
			for hh: float in [0.95, 1.2]:
				steel.rod(Vector3(x0 + 0.04, hh, s * 1.075), Vector3.UP, 0.016, 0.08, 6)
			var latch := [
				Vector3(x0 + 0.8, 1.02, s * 1.062),
				Vector3(x0 + 0.8, 1.02, s * 1.09),
				Vector3(x0 + 0.8, 1.14, s * 1.09),
				Vector3(x0 + 0.8, 1.14, s * 1.062),
			]
			steel.tube(latch, 0.01, 5)
	body.slab(4.85, 7.0, 0.85, MODULE_H0, 1.05, 0.0, 0.03)


## Chassis: the frame rails (one box: only its sides show between the wheel groups), axle
## housings with their suspension blocks and cross members seen from the front and below.
static func _chassis(h: MeshKits) -> void:
	var dark := h.k(&"dark")
	dark.slab(0.4, 10.8, 1.0, 1.5, 0.5, 0.0, 0.02)
	for x: float in AXLES:
		dark.rod(Vector3(x, WHEEL_RADIUS, 0.0), Vector3.BACK, 0.11, 1.9, 8)
		dark.slab(x - 0.2, x + 0.2, WHEEL_RADIUS + 0.05, 1.0, 0.12, -0.55, 0.01)
		dark.slab(x - 0.2, x + 0.2, WHEEL_RADIUS + 0.05, 1.0, 0.12, 0.55, 0.01)
	for x: float in [4.4, 7.3]:
		dark.slab(x - 0.06, x + 0.06, 1.05, 1.45, 0.95, 0.0, 0.01)


## Rear: deck over the rear axles with tie-down rings, stabiliser housings with hydraulic lines,
## bumper with lights and the towing pintle, accent-free (the pod carries the rear band).
static func _rear(h: MeshKits) -> void:
	var body := h.k(&"body")
	var dark := h.k(&"dark")
	var steel := h.k(&"steel")
	body.slab(7.0, 10.6, 1.45, DECK_H, 1.38, 0.0, 0.03)
	for s: float in [-1.0, 1.0]:
		for x: float in [7.3, 8.9, 10.3]:
			var ring := MeshKit.arc(
				Vector3(x, 1.52, s * 1.39), 0.045, Vector3.RIGHT, Vector3.DOWN, -1.6, 1.6, 6
			)
			steel.tube(ring, 0.01, 4)
		# Stabiliser housing: chamfered sleeve with a collar, its hydraulic lines up to the deck.
		var z := s * JACK_Z
		dark.slab(JACK_X - 0.13, JACK_X + 0.13, JACK_HOUSING_H0, 1.55, 0.14, z, 0.03)
		dark.rod(Vector3(JACK_X, JACK_HOUSING_H0 + 0.03, z), Vector3.UP, 0.16, 0.06, 12, 0.012)
		for dz: float in [-0.05, 0.05]:
			var line := [
				Vector3(JACK_X - 0.14, 1.0, z + dz),
				Vector3(JACK_X - 0.2, 1.1, z + dz),
				Vector3(JACK_X - 0.24, 1.42, z + dz),
				Vector3(JACK_X - 0.36, 1.48, z + dz),
			]
			dark.tube(line, 0.016, 5)
		# Lights on the bumper.
		h.k(&"red_lens").rod(Vector3(11.0, 1.32, s * 1.1), Vector3.RIGHT, 0.06, 0.02, 10)
		h.k(&"lens").rod(Vector3(11.0, 1.32, s * 0.9), Vector3.RIGHT, 0.05, 0.02, 10)
	dark.slab(10.6, 10.98, 1.1, 1.48, 1.3, 0.0, 0.03)
	steel.slab(10.98, 11.0, 1.14, 1.2, 0.22, 0.0, 0.0)
	var pintle := MeshKit.arc(
		Vector3(10.98, 1.17, 0.0), 0.045, Vector3.RIGHT, Vector3.UP, -PI / 2.0, PI * 1.2, 9
	)
	steel.tube(pintle, 0.022, 6)


## The fixed part of the launcher: the bearing ring on the deck with its bolt ring (the upper
## carriage turns on it).
static func _turntable_base(h: MeshKits) -> void:
	var dark := h.k(&"dark")
	var c := Vector3(TURNTABLE_X, DECK_H, 0.0)
	var r := TURNTABLE_RING_R
	dark.lathe(
		c,
		Basis.IDENTITY,
		[Vector2(0.0, 0.04), Vector2(r - 0.03, 0.04), Vector2(r, 0.01), Vector2(r, 0.0)],
		24
	)
	for i in 20:
		var a := TAU * i / 20.0
		dark.bolt(c + Vector3(cos(a) * (r - 0.08), 0.04, sin(a) * (r - 0.08)), Vector3.UP, 0.025)


# --- Stabilisers --------------------------------------------------------------------------------


## "Stabiliser0/1": a chamfered steel leg with a dark round foot pad sliding down out of the fixed
## housing; built stowed (foot JACK_STOWED_H above the ground), meta "deployed" lowers it onto
## y = 0. Both jacks share their meshes (built in the pivot's space, symmetric).
static func _build_jacks(g: Node3D, frame: Frame, m: Dictionary) -> void:
	var meshes := ModelParts.cached_meshes("homar_k:jack", _jack_meshes)
	for i in 2:
		var jack := Node3D.new()
		jack.name = "Stabiliser%d" % i
		jack.position = frame.p(JACK_X, 0.0, JACK_Z * (-1.0 if i == 0 else 1.0))
		g.add_child(jack)
		MeshKits.add_meshes(jack, meshes, m)
		jack.set_meta(
			&"deployed",
			Transform3D(Basis.IDENTITY, jack.position - Vector3(0.0, JACK_STOWED_H * K, 0.0))
		)


## Kits in the pivot's space measured in metres (uniform scale K, no mirroring).
static func _local_kits() -> MeshKits:
	return MeshKits.new(null, Transform3D(Basis.from_scale(Vector3.ONE * K), Vector3.ZERO))


static func _jack_meshes() -> Dictionary:
	var kits := _local_kits()
	var steel := kits.k(&"steel")
	var dark := kits.k(&"dark")
	var foot := JACK_STOWED_H
	var top := 1.45
	var r := JACK_LEG_RADIUS
	steel.lathe(
		Vector3(0.0, foot + 0.08, 0.0),
		Basis.IDENTITY,
		[
			Vector2(0.0, top - foot - 0.08),
			Vector2(r, top - foot - 0.08),
			Vector2(r, 0.02),
			Vector2(r + 0.02, 0.0),
			Vector2(r + 0.02, -0.03)
		],
		10
	)
	(
		dark
		. lathe(
			Vector3(0.0, foot, 0.0),
			Basis.IDENTITY,
			[
				Vector2(0.0, 0.08),
				Vector2(0.06, 0.08),
				Vector2(0.09, 0.06),
				Vector2(0.17, 0.035),
				Vector2(0.2, 0.025),
				Vector2(0.2, 0.0),
				Vector2(0.0, 0.0),
			],
			14
		)
	)
	return kits.commit_all()


# --- Launcher -----------------------------------------------------------------------------------


static func _build_launcher(g: Node3D, frame: Frame, m: Dictionary) -> void:
	var launcher := Node3D.new()
	launcher.name = "Launcher"
	launcher.position = frame.p(TURNTABLE_X, TURNTABLE_H)
	g.add_child(launcher)
	var to_launcher := Frame.to_local(launcher)
	var pod := Node3D.new()
	pod.name = "Pod"
	pod.transform = to_launcher * Transform3D(Basis(Vector3.UP, PI), frame.p(POD_X0, POD_H0))
	pod.set_meta(&"rest", pod.transform)
	launcher.add_child(pod)
	var to_pod := Frame.to_local(pod)
	var carriage := ModelParts.cached_meshes(
		"homar_k:carriage", func() -> Dictionary: return _carriage_meshes(frame, to_launcher)
	)
	MeshKits.add_meshes(launcher, carriage, m)
	var shell := ModelParts.cached_meshes(
		"homar_k:pod", func() -> Dictionary: return _pod_meshes(frame, to_pod)
	)
	MeshKits.add_meshes(pod, shell, m)
	var index := 0
	for zc: float in POD_CENTRES:
		for hh: float in TUBE_ROWS:
			for dz: float in TUBE_COLUMNS:
				var mouth := Node3D.new()
				mouth.name = "Mouth%d" % index
				index += 1
				mouth.position = to_pod * frame.p(POD_X1 + 0.15, hh, zc + dz)
				pod.add_child(mouth)
	_build_actuators(launcher, pod, frame, to_launcher, to_pod, m)
	UnitModels.pose_launcher(g, 0.0, 0.0)


## Upper carriage on the turntable (traverses, never elevates): two side girders, cross beams, a
## floor plate between them, the hinge brackets with their pins at the pod's front-bottom edge.
static func _carriage_meshes(frame: Frame, to_launcher: Transform3D) -> Dictionary:
	var kits := MeshKits.new(frame, to_launcher)
	var dark := kits.k(&"dark")
	var top := TURNTABLE_H
	dark.lathe(
		Vector3(TURNTABLE_X, DECK_H + 0.04, 0.0),
		Basis.IDENTITY,
		[Vector2(0.0, 0.08), Vector2(0.84, 0.08), Vector2(0.88, 0.04), Vector2(0.88, 0.0)],
		20
	)
	dark.pair(6.7, 10.5, CARRIAGE_H0, top, 0.08, GIRDER_Z, 0.02)
	dark.slab(6.7, 6.95, CARRIAGE_H0, top, GIRDER_Z, 0.0, 0.02)
	dark.slab(10.25, 10.5, CARRIAGE_H0, top, GIRDER_Z, 0.0, 0.02)
	dark.slab(6.95, 10.25, CARRIAGE_H0, CARRIAGE_H0 + 0.06, GIRDER_Z - 0.08, 0.0, 0.0)
	for s: float in [-1.0, 1.0]:
		dark.slab(6.42, 6.7, CARRIAGE_H0 + 0.05, top - 0.01, 0.06, s * 1.26, 0.015)
		dark.rod(Vector3(POD_X0, POD_H0, s * 1.26), Vector3.BACK, 0.05, 0.16, 10, 0.01)
		for x: float in [7.4, 8.6, 9.8]:
			dark.bolt(Vector3(x, 1.85, s * (GIRDER_Z + 0.08)), Vector3(0, 0, s), 0.025)
		var line := [
			Vector3(7.0, 1.95, s * (GIRDER_Z + 0.09)),
			Vector3(8.2, 1.95, s * (GIRDER_Z + 0.09)),
			Vector3(8.4, 1.8, s * (GIRDER_Z + 0.09)),
			Vector3(9.6, 1.8, s * (GIRDER_Z + 0.09)),
		]
		dark.tube(line, 0.018, 5)
	return kits.commit_all()


## Pod: the launcher box with a bevelled front-top edge, seams and rivets on the cover, the dark
## centre seam, lifting eyes, bottom rails, the accent band, the rear frames with 12
## tube caps (shallow lathes with rims). Closed box: nothing inside.
static func _pod_meshes(frame: Frame, to_pod: Transform3D) -> Dictionary:
	var kits := MeshKits.new(frame, to_pod)
	var body := kits.k(&"body")
	var dark := kits.k(&"dark")
	var steel := kits.k(&"steel")
	var outline := [
		Vector2(POD_X0, POD_H0),
		Vector2(POD_X0, POD_H1 - 0.16),
		Vector2(POD_X0 + 0.16, POD_H1),
		Vector2(POD_X1, POD_H1),
		Vector2(POD_X1, POD_H0),
	]
	body.profile(outline, POD_HALF_W, 0.0, 0.05)
	# Dark centre seam between the two pods on the cover and the rear face.
	dark.slab(POD_X0 + 0.2, POD_X1, POD_H1, POD_H1 + 0.03, 0.04, 0.0, 0.01)
	dark.slab(POD_X1, POD_X1 + 0.02, POD_H0 + 0.08, POD_H1 - 0.04, 0.05, 0.0, 0.0)
	for x: float in [7.65, 8.75, 9.95]:
		body.slab(x - 0.03, x + 0.03, POD_H1, POD_H1 + 0.015, POD_HALF_W - 0.1, 0.0, 0.006)
	for s: float in [-1.0, 1.0]:
		var z := s * POD_HALF_W
		# Cover rivets along both top edges.
		for i in 10:
			var x := lerpf(POD_X0 + 0.35, POD_X1 - 0.15, i / 9.0)
			body.bolt(Vector3(x, POD_H1, s * (POD_HALF_W - 0.08)), Vector3.UP, 0.022)
		# Side panel seams, bottom rail, hinge lug, lifting eyes.
		for x: float in [7.65, 8.75, 9.95]:
			dark.cbox(
				Vector3(x, (POD_H0 + POD_H1) / 2.0, z + s * 0.002), Vector3(0.014, 1.2, 0.01), 0.0
			)
		dark.slab(POD_X0 + 0.1, POD_X1 - 0.1, POD_H0, POD_H0 + 0.1, 0.012, z + s * 0.008, 0.006)
		for x: float in [POD_X0 + 0.5, POD_X1 - 0.45]:
			var eye := MeshKit.arc(
				Vector3(x, POD_H1, s * (POD_HALF_W - 0.2)),
				0.04,
				Vector3.RIGHT,
				Vector3.UP,
				0.0,
				PI,
				6
			)
			steel.tube(eye, 0.012, 5)
		kits.k(&"accent").slab(9.55, 9.85, POD_H0 + 0.1, POD_H1 - 0.02, 0.008, z + s * 0.004, 0.004)
		# Actuator mount: clevis under the pod (inside the turntable ring).
		dark.slab(
			ACTUATOR_MOUNT.x - 0.1,
			ACTUATOR_MOUNT.x + 0.1,
			POD_H0 - 0.06,
			POD_H0,
			0.08,
			s * ACTUATOR_Z,
			0.01
		)
	# Rear: one dark frame per pod, six tube caps each.
	for zc: float in POD_CENTRES:
		dark.slab(POD_X1, POD_X1 + 0.02, POD_H0 + 0.1, POD_H1 - 0.1, 0.62, zc, 0.008)
		for hh: float in TUBE_ROWS:
			for dz: float in TUBE_COLUMNS:
				var r := TUBE_RADIUS
				(
					steel
					. lathe(
						Vector3(POD_X1 + 0.02, hh, zc + dz),
						Frame.axis_basis(Vector3.RIGHT),
						[
							Vector2(0.0, 0.035),
							Vector2(r - 0.06, 0.035),
							Vector2(r - 0.03, 0.045),
							Vector2(r - 0.01, 0.04),
							Vector2(r, 0.025),
							Vector2(r, 0.0),
						],
						14
					)
				)
	return kits.commit_all()


## Two elevation actuators: "Actuator<i>" (dark cylinder with a gland, a base eye and a hydraulic
## line, from its turntable anchor) and "ActuatorRod<i>" (steel piston with its eye, from the
## "ActuatorMount<i>" under the pod), both along +Y; both pairs share their meshes.
static func _build_actuators(
	launcher: Node3D,
	pod: Node3D,
	frame: Frame,
	to_launcher: Transform3D,
	to_pod: Transform3D,
	m: Dictionary
) -> void:
	var cylinder := ModelParts.cached_meshes("homar_k:actuator", _cylinder_meshes)
	var piston := ModelParts.cached_meshes("homar_k:piston", _piston_meshes)
	for i in 2:
		var z := ACTUATOR_Z * (-1.0 if i == 0 else 1.0)
		var barrel := Node3D.new()
		barrel.name = "Actuator%d" % i
		barrel.position = to_launcher * frame.p(ACTUATOR_BASE.x, ACTUATOR_BASE.y, z)
		launcher.add_child(barrel)
		MeshKits.add_meshes(barrel, cylinder, m)
		var rod := Node3D.new()
		rod.name = "ActuatorRod%d" % i
		launcher.add_child(rod)
		MeshKits.add_meshes(rod, piston, m)
		var mount := Node3D.new()
		mount.name = "ActuatorMount%d" % i
		mount.position = to_pod * frame.p(ACTUATOR_MOUNT.x, ACTUATOR_MOUNT.y, z)
		pod.add_child(mount)


static func _cylinder_meshes() -> Dictionary:
	var kits := _local_kits()
	var dark := kits.k(&"dark")
	var r := CYLINDER_RADIUS
	var length := ACTUATOR_LENGTH
	(
		dark
		. lathe(
			Vector3.ZERO,
			Basis.IDENTITY,
			[
				Vector2(0.0, length),
				Vector2(r - 0.02, length),
				Vector2(r + 0.015, length - 0.02),
				Vector2(r + 0.015, length - 0.1),
				Vector2(r, length - 0.11),
				Vector2(r, 0.12),
				Vector2(r + 0.015, 0.1),
				Vector2(r + 0.015, 0.04),
				Vector2(0.0, 0.04),
			],
			12
		)
	)
	dark.rod(Vector3.ZERO, Vector3.BACK, 0.07, 0.22, 10, 0.01)
	var line := [
		Vector3(r + 0.03, 0.16, 0.0),
		Vector3(r + 0.05, 0.24, 0.0),
		Vector3(r + 0.05, length - 0.2, 0.0),
		Vector3(r + 0.02, length - 0.13, 0.0),
	]
	dark.tube(line, 0.018, 5)
	return kits.commit_all()


static func _piston_meshes() -> Dictionary:
	var kits := _local_kits()
	var steel := kits.k(&"steel")
	steel.rod(
		Vector3(0.0, ACTUATOR_LENGTH / 2.0, 0.0),
		Vector3.UP,
		PISTON_RADIUS,
		ACTUATOR_LENGTH,
		10,
		0.01
	)
	steel.rod(Vector3.ZERO, Vector3.BACK, 0.06, 0.18, 10, 0.01)
	return kits.commit_all()
