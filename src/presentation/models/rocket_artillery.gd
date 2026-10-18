## Self-propelled rocket artillery truck with a tilted pod of six launch tubes.

## Rocket artillery layout: truck axle x positions, pod elevation (rad) and pod length.
const TRUCK_AXLES: Array[float] = [-0.3, -0.12, 0.27]
const POD_ELEVATION := 0.5
const POD_LENGTH := 0.52


## Self-propelled rocket artillery: 6-wheel truck with a cab at the front and a tilted pod of
## six launch tubes on the back. The "Pod" node holds "Mouth0".."Mouth5" (tube ends) – the
## volley effect spawns rockets there. Wheels are named Wheel0..5 (see pose_tank).
static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var body := ModelParts.faction_material(faction, &"truck_body")
	var dark := ModelParts.pbr(ModelParts.DARK)
	var metal := ModelParts.pbr(ModelParts.STEEL)
	var rubber := ModelParts.pbr(ModelParts.RUBBER)
	var glass := ModelParts.pbr(ModelParts.GLASS)
	var acc := ModelParts.faction_material(faction, &"accent")
	var wheel_index := 0
	for s: float in [-1.0, 1.0]:
		for x: float in TRUCK_AXLES:
			var pivot := Node3D.new()
			pivot.name = "Wheel%d" % wheel_index
			wheel_index += 1
			pivot.position = Vector3(x, 0.055, s * 0.17)
			g.add_child(pivot)
			var wheel := ModelParts.cyl(pivot, 0.055, 0.055, 0.04, 12, rubber, Vector3.ZERO)
			wheel.rotation.x = PI / 2.0
			ModelParts.box(pivot, Vector3(0.08, 0.014, 0.006), metal, 0.0, 0.0, s * 0.022)
		ModelParts.box(g, Vector3(0.7, 0.03, 0.03), dark, -0.04, 0.13, s * 0.11)  # mudguard rail
	# Chassis, cab, hood and the flat deck behind the cab.
	ModelParts.box(g, Vector3(0.82, 0.06, 0.24), dark, 0.0, 0.1, 0.0)
	ModelParts.box(g, Vector3(0.17, 0.15, 0.28), body, 0.27, 0.21, 0.0)
	ModelParts.box(g, Vector3(0.1, 0.08, 0.26), body, 0.4, 0.17, 0.0)
	# Windscreen.
	ModelParts.box(g, Vector3(0.012, 0.07, 0.22), glass, 0.358, 0.255, 0.0).rotation.z = 0.25
	ModelParts.box(g, Vector3(0.1, 0.012, 0.2), acc, 0.27, 0.292, 0.0)  # faction roof panel
	ModelParts.box(g, Vector3(0.52, 0.03, 0.3), body, -0.14, 0.145, 0.0)
	ModelParts.box(g, Vector3(0.04, 0.05, 0.3), dark, -0.42, 0.11, 0.0)  # rear stabiliser bar
	# Launcher: cradle + tilted pod. The pod's +X side is the muzzle end.
	ModelParts.box(g, Vector3(0.16, 0.05, 0.24), metal, -0.2, 0.18, 0.0)
	var pod := Node3D.new()
	pod.name = "Pod"
	pod.position = Vector3(-0.17, 0.25, 0.0)
	pod.rotation.z = POD_ELEVATION
	g.add_child(pod)
	ModelParts.box(pod, Vector3(0.52, 0.17, 0.28), body, 0.0, 0.0, 0.0)
	# Large flat plates stay matte: a big steel panel only mirrors the dark ground.
	ModelParts.box(pod, Vector3(0.5, 0.012, 0.3), dark, 0.0, 0.092, 0.0)
	ModelParts.box(pod, Vector3(0.5, 0.012, 0.3), dark, 0.0, -0.092, 0.0)
	ModelParts.box(pod, Vector3(0.08, 0.175, 0.285), acc, -0.12, 0.0, 0.0)  # faction band
	var mouth_index := 0
	for row: float in [1.0, -1.0]:
		for col: float in [-1.0, 0.0, 1.0]:
			var mouth_pos := Vector3(POD_LENGTH / 2.0 + 0.01, row * 0.04, col * 0.085)
			var tube := ModelParts.cyl(
				pod, 0.034, 0.034, 0.03, 10, dark, mouth_pos - Vector3(0.015, 0, 0)
			)
			tube.rotation.z = PI / 2.0
			var nose := ModelParts.cyl(
				pod, 0.02, 0.02, 0.02, 8, acc, mouth_pos - Vector3(0.02, 0, 0)
			)
			nose.rotation.z = PI / 2.0
			var mouth := Node3D.new()
			mouth.name = "Mouth%d" % mouth_index
			mouth_index += 1
			mouth.position = mouth_pos + Vector3(0.03, 0, 0)
			pod.add_child(mouth)
	return g
