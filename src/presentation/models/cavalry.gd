## Tank (the `cavalry` unit): tracked hull with six road wheels per side and a turret.

const WHEELS_PER_SIDE := 6


static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	var body := ModelParts.faction_material(faction, &"body")
	var dark := ModelParts.pbr(ModelParts.DARK)
	var metal := ModelParts.pbr(ModelParts.STEEL)
	var rubber := ModelParts.pbr(ModelParts.RUBBER)
	var track := ModelParts.pbr(ModelParts.TRACK)
	var acc := ModelParts.faction_material(faction, &"accent")
	var wheel_index := 0
	for s: float in [-1.0, 1.0]:
		ModelParts.box(g, Vector3(0.74, 0.1, 0.1), track, 0.0, 0.06, s * 0.17)
		for i in WHEELS_PER_SIDE:
			var pivot := Node3D.new()
			pivot.name = "Wheel%d" % wheel_index
			wheel_index += 1
			pivot.position = Vector3(-0.27 + i * 0.108, 0.055, s * 0.2)
			g.add_child(pivot)
			var wheel := ModelParts.cyl(pivot, 0.045, 0.045, 0.03, 12, rubber, Vector3.ZERO)
			wheel.rotation.x = PI / 2.0
			ModelParts.box(pivot, Vector3(0.07, 0.012, 0.006), metal, 0.0, 0.0, s * 0.017)
		ModelParts.box(g, Vector3(0.62, 0.065, 0.012), body, 0.0, 0.135, s * 0.226)
	ModelParts.box(g, Vector3(0.7, 0.09, 0.36), body, 0.0, 0.13, 0.0)
	ModelParts.box(g, Vector3(0.64, 0.05, 0.46), body, -0.02, 0.195, 0.0)
	ModelParts.box(g, Vector3(0.16, 0.02, 0.44), body, 0.33, 0.17, 0.0).rotation.z = -0.55
	ModelParts.box(g, Vector3(0.13, 0.012, 0.3), dark, -0.27, 0.225, 0.0)
	var tur := Node3D.new()
	tur.name = "Turret"
	tur.position = Vector3(-0.03, 0.225, 0.0)
	g.add_child(tur)
	ModelParts.add(tur, ModelParts.turret_mesh(), body, Vector3.ZERO)
	ModelParts.box(tur, Vector3(0.07, 0.07, 0.1), body, 0.22, 0.045, 0.0)
	ModelParts.cyl(tur, 0.017, 0.019, 0.52, 10, metal, Vector3(0.5, 0.05, 0.0)).rotation.z = (
		PI / 2.0
	)
	ModelParts.cyl(tur, 0.026, 0.026, 0.07, 10, metal, Vector3(0.42, 0.05, 0.0)).rotation.z = (
		PI / 2.0
	)
	ModelParts.cyl(tur, 0.022, 0.022, 0.03, 10, dark, Vector3(0.76, 0.05, 0.0)).rotation.z = (
		PI / 2.0
	)
	ModelParts.cyl(tur, 0.04, 0.046, 0.035, 12, body, Vector3(-0.07, 0.115, 0.07))
	ModelParts.box(tur, Vector3(0.07, 0.012, 0.012), dark, -0.03, 0.142, 0.07)
	ModelParts.cyl(tur, 0.032, 0.036, 0.025, 10, body, Vector3(-0.05, 0.11, -0.07))
	ModelParts.cyl(tur, 0.004, 0.004, 0.34, 4, dark, Vector3(-0.2, 0.26, -0.11))
	for s: float in [-1.0, 1.0]:
		ModelParts.box(tur, Vector3(0.06, 0.04, 0.005), acc, -0.02, 0.05, s * 0.172)
		for i in 3:
			var pos := Vector3(0.06 - i * 0.025, 0.08, s * 0.15)
			ModelParts.cyl(tur, 0.012, 0.012, 0.04, 6, dark, pos).rotation.x = 0.4 * s
	return g
