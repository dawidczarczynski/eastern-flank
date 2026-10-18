## Infantry squad: five soldiers (Soldier0..4, each with a Rig; kneelers have Kneel + Stand).
## Port of makeInf / soldier in docs/design/game_screen.scene.js.

const SOLDIER_SCALE := 1.5
## Squad layout: [x, z, kneeling].
const SQUAD: Array = [
	[0.13, 0.0, false],
	[-0.02, 0.15, true],
	[-0.03, -0.15, false],
	[-0.18, 0.06, false],
	[-0.15, -0.12, true],
]


static func build(faction: FactionDefinition) -> Node3D:
	var g := Node3D.new()
	for i in SQUAD.size():
		var entry: Array = SQUAD[i]
		var s := Node3D.new()
		s.name = "Soldier%d" % i
		var rig := Node3D.new()
		rig.name = "Rig"
		s.add_child(rig)
		if entry[2]:
			var kneel := make_soldier(faction, true, i == 1)
			kneel.name = "Kneel"
			var stand := make_soldier(faction, false, i == 1)
			stand.name = "Stand"
			stand.visible = false
			rig.add_child(kneel)
			rig.add_child(stand)
		else:
			make_soldier(faction, false, i == 1, rig)
		s.scale = Vector3.ONE * SOLDIER_SCALE
		s.position = Vector3(entry[0], 0.0, entry[1])
		s.rotation.y = (TerrainNoise.hash(i, 3, 1) - 0.5) * 0.6
		g.add_child(s)
	return g


## Builds a soldier's meshes under `into` (a new Node3D when null) and returns it.
static func make_soldier(
	faction: FactionDefinition, kneel: bool, gun: bool, into: Node3D = null
) -> Node3D:
	var s := into if into != null else Node3D.new()
	var uni := ModelParts.faction_material(faction, &"uniform")
	var vest := ModelParts.faction_material(faction, &"vest")
	var skin := ModelParts.pbr(ModelParts.SKIN)
	var dark := ModelParts.pbr(ModelParts.GUN)
	var lh := 0.05 if kneel else 0.085
	ModelParts.box(s, Vector3(0.024, lh, 0.026), uni, 0.02 if kneel else 0.0, lh / 2.0, -0.017)
	ModelParts.box(s, Vector3(0.024, lh, 0.026), uni, -0.015 if kneel else 0.0, lh / 2.0, 0.017)
	ModelParts.box(s, Vector3(0.045, 0.078, 0.064), vest, 0.0, lh + 0.04, 0.0)
	ModelParts.box(s, Vector3(0.032, 0.055, 0.05), uni, -0.038, lh + 0.05, 0.0)
	ModelParts.add(
		s, ModelParts.sphere_mesh(0.02, false, 10, 8), skin, Vector3(0.004, lh + 0.1, 0.0)
	)
	ModelParts.add(
		s, ModelParts.sphere_mesh(0.027, true, 12, 6), uni, Vector3(0.0, lh + 0.102, 0.0)
	)
	ModelParts.box(s, Vector3(0.06, 0.016, 0.016), uni, 0.03, lh + 0.06, 0.03)
	ModelParts.box(s, Vector3(0.06, 0.016, 0.016), uni, 0.035, lh + 0.06, -0.025)
	var rifle := Vector3(0.15, 0.022, 0.022) if gun else Vector3(0.12, 0.012, 0.012)
	ModelParts.box(s, rifle, dark, 0.06, lh + 0.07, 0.01).rotation.z = 0.12
	return s
