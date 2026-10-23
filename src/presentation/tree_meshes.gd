class_name TreeMeshes
extends RefCounted
## Pure procedural tree geometry (TASK-060). Every species (TreeSpecies: pine, spruce, birch,
## oak, alder) has VARIANTS detailed LOD0 meshes and one simple LOD1 mesh, cached like
## FoliageMeshes and fully deterministic from (species, variant) (a seeded generator, never
## GameState.rng). Base at y = 0, model space as the old foliage (crown top ~0.25-0.33 before the
## instance scale, VisualScale.tree_scale()).
##
## Both LODs are one ArrayMesh with two surfaces, so one MultiMesh draws a whole tree:
## - surface 0 (SURFACE_BARK): the trunk, a tapered lathe closed by a cap inside the crown, plus
##   tapered branch rods (deciduous: into the crown lobes, pine: short upper branches). UV: u
##   around, v along the height.
## - surface 1 (SURFACE_LEAVES): LOD0 = alpha-scissor leaf / needle cards (4 vertices per card in
##   corner order, 2 triangles), LOD1 = the lobed crown / cone stack as a closed solid.
## Normals of the crown are bent: from the crown centre outwards, so crowns light as volumes.
## Vertex colours: r = ambient occlusion (darker inside and lower), g = per-card flutter phase in
## [0, 1), b = 1 on leaves and 0 on bark (foliage.gdshader reads all three).

const VARIANTS := 3
const SURFACE_BARK := 0
const SURFACE_LEAVES := 1
## Reference height for the wind (foliage.gdshader: h = vertex y / TREE_HEIGHT).
const TREE_HEIGHT := 0.3
const TRUNK_SIDES := 7
const TRUNK_SEGMENTS := 3
const BRANCH_SIDES := 4
const LOD1_TRUNK_SIDES := 5
const LOD1_LOBE_SUBDIVISIONS := 1
const LOD1_JITTER := 0.25
const LOD1_CONE_SIDES := 8
const SEED_BASE := 6007

## Deciduous species: trunk, branches, crown lobes at the branch tips and leaf cards.
## trunk: [top height, base radius, top radius, lean]; branches: [count, start min, start max
## (share of the trunk height), elevation min, max (radians), length min, max]; lobes: [radius
## min, max, scale]; top lobe: [lift above the trunk top, radius]; cards: [count, size min, max];
## droop: how much the cards hang (0 = facing outwards, 1 = vertical).
const DECIDUOUS := {
	&"birch":
	{
		"trunk": [0.235, 0.0095, 0.0035, 0.012],
		"branches": [4, 0.5, 0.8, 0.85, 1.2, 0.045, 0.06],
		"lobes": [0.03, 0.036, Vector3(1.0, 1.45, 1.0)],
		"top": [0.02, 0.032],
		"cards": [84, 0.042, 0.054],
		"droop": 0.55,
	},
	&"oak":
	{
		"trunk": [0.175, 0.015, 0.0075, 0.008],
		"branches": [6, 0.55, 0.85, 0.3, 0.65, 0.065, 0.085],
		"lobes": [0.042, 0.05, Vector3(1.1, 0.8, 1.1)],
		"top": [0.035, 0.048],
		"cards": [110, 0.055, 0.067],
		"droop": 0.0,
	},
	&"alder":
	{
		"trunk": [0.21, 0.0115, 0.0055, 0.01],
		"branches": [5, 0.5, 0.82, 0.6, 1.0, 0.05, 0.065],
		"lobes": [0.037, 0.044, Vector3(1.0, 1.2, 1.0)],
		"top": [0.025, 0.042],
		"cards": [96, 0.05, 0.061],
		"droop": 0.15,
	},
}
## Scrub (TASK-061), same layout as DECIDUOUS but a short trunk fanning into many low lobes:
## shrubs ~0.1 tall, undergrowth (ferns, herbs) ~0.045 tall and wide.
const SCRUB := {
	&"shrub":
	{
		"trunk": [0.035, 0.004, 0.002, 0.006],
		"branches": [6, 0.1, 0.8, 0.45, 1.1, 0.03, 0.05],
		"lobes": [0.022, 0.03, Vector3(1.0, 0.8, 1.0)],
		"top": [0.012, 0.024],
		"cards": [26, 0.046, 0.06],
		"droop": 0.1,
	},
	&"undergrowth":
	{
		"trunk": [0.012, 0.003, 0.002, 0.003],
		"branches": [7, 0.1, 0.5, 0.12, 0.45, 0.03, 0.05],
		"lobes": [0.02, 0.026, Vector3(1.25, 0.45, 1.25)],
		"top": [0.004, 0.02],
		"cards": [10, 0.046, 0.06],
		"droop": 0.3,
	},
}
## Spruce: conical whorls of drooping needle cards from SKIRT_BOTTOM up to the top.
const SPRUCE := {
	"height": 0.31,
	"trunk": [0.265, 0.011, 0.003, 0.004],
	"skirt_bottom": 0.045,
	"radius": [0.08, 0.092],
	"whorls": 9,
	"droop": [0.35, 0.6],
	"size": [0.044, 0.066],
}
## Pine: bare trunk, a flat-topped crown of needle tufts on short branches in the upper third.
const PINE := {
	"trunk": [0.255, 0.0105, 0.004, 0.016],
	"branches": [4, 0.66, 0.92, 0.2, 0.55, 0.038, 0.055],
	"tufts": [0.036, 0.044, Vector3(1.0, 0.42, 1.0)],
	"top": [0.012, 0.04],
	"cards": [64, 0.048, 0.06],
}

static var _cache: Dictionary = {}
static var _shapes: Dictionary = {}
static var _unit_spheres: Dictionary = {}


static func species() -> Array[StringName]:
	return TreeSpecies.all()


static func scrub_species() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in SCRUB:
		result.append(id)
	return result


## The cached detailed mesh (bark + leaf cards).
static func lod0(species_id: StringName, variant: int) -> ArrayMesh:
	var key := "%s%d" % [species_id, variant]
	if not _cache.has(key):
		_cache[key] = build(species_id, variant)
	return _cache[key]


## The cached simple mesh (bark + solid crown) of a species.
static func lod1(species_id: StringName) -> ArrayMesh:
	var key := "%s_lod1" % species_id
	if not _cache.has(key):
		_cache[key] = build_lod1(species_id)
	return _cache[key]


## {crown_center: Vector3, trunk_top: Vector3 (centre of the trunk cap), cards: int} of a LOD0
## mesh (the values the builder used).
static func shape(species_id: StringName, variant: int) -> Dictionary:
	var key := "%s%d" % [species_id, variant]
	if not _shapes.has(key):
		build(species_id, variant)
	return _shapes[key]


static func triangle_count(mesh: ArrayMesh) -> int:
	var total := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += indices.size() / 3
	return total


## Uncached LOD0 builder.
static func build(species_id: StringName, variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	var index := TreeSpecies.all().find(species_id)
	if index < 0:
		index = TreeSpecies.all().size() + scrub_species().find(species_id)
	rng.seed = SEED_BASE + index * 101 + variant * 7919
	var bark := Surface.new()
	var leaves := Surface.new()
	var result: Dictionary
	if species_id == &"spruce":
		result = _build_spruce(rng, bark, leaves)
	elif species_id == &"pine":
		result = _build_pine(rng, bark, leaves)
	else:
		result = _build_deciduous(
			DECIDUOUS[species_id] if DECIDUOUS.has(species_id) else SCRUB[species_id],
			rng,
			bark,
			leaves
		)
	result["cards"] = leaves.indices.size() / 6
	_shapes["%s%d" % [species_id, variant]] = result
	return _commit(bark, leaves)


## Uncached LOD1 builder: the crown shape of variant 0 as a lobed solid / cone stack.
static func build_lod1(species_id: StringName) -> ArrayMesh:
	var shape0 := shape(species_id, 0)
	var bark := Surface.new()
	var crown := Surface.new()
	var top: Vector3 = shape0["trunk_top"]
	_add_trunk(
		bark,
		top.y * 0.92,
		shape0["trunk_radius"],
		shape0["trunk_radius"] * 0.5,
		Vector3.ZERO,
		LOD1_TRUNK_SIDES,
		1,
		false
	)
	var center: Vector3 = shape0["crown_center"]
	if species_id == &"spruce":
		var bottom: float = SPRUCE["skirt_bottom"]
		var height: float = SPRUCE["height"]
		var radius: float = shape0["skirt_radius"]
		for i in 4:
			var base := lerpf(bottom, height * 0.62, i / 3.0)
			var r := radius * (1.0 - 0.21 * i)
			var apex := base + (height - bottom) * (0.4 - 0.03 * i)
			_add_cone(crown, Vector3(0, base, 0), r, apex - base, center, i)
	elif species_id == &"pine":
		var lo: Vector3 = shape0["crown_min"]
		var hi: Vector3 = shape0["crown_max"]
		var half := (hi - lo) * 0.5
		var r := maxf(half.x, half.z) * 0.95
		_add_cone(crown, Vector3(center.x, lo.y + 0.01, center.z), r, half.y * 1.1, center, 0)
		_add_cone(
			crown,
			Vector3(center.x, lo.y + half.y * 0.9, center.z),
			r * 0.75,
			half.y * 1.0,
			center,
			1
		)
	else:
		var lo: Vector3 = shape0["crown_min"]
		var hi: Vector3 = shape0["crown_max"]
		var e := (hi - lo) * 0.5 * 0.82
		var lobes: Array[Array] = [
			[center + Vector3(0, -0.2 * e.y, 0), Vector3(e.x, 0.7 * e.y, e.z)],
			[center + Vector3(0.28 * e.x, 0.32 * e.y, 0.12 * e.z), e * 0.66],
			[center + Vector3(-0.26 * e.x, 0.36 * e.y, -0.18 * e.z), e * 0.62],
		]
		_add_lobes(crown, lobes, center)
	return _commit(bark, crown)


static func _commit(bark: Surface, leaves: Surface) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bark.arrays())
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaves.arrays())
	return mesh


## Growing vertex / index arrays of one surface.
class Surface:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func add(p: Vector3, n: Vector3, c: Color, uv: Vector2) -> int:
		vertices.append(p)
		normals.append(n.normalized())
		colors.append(c)
		uvs.append(uv)
		return vertices.size() - 1

	## A triangle wound front-facing (clockwise seen from `outward`, Godot's convention).
	func tri(a: int, b: int, c: int, outward: Vector3) -> void:
		var n := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		if n.dot(outward) > 0.0:
			indices.append_array([a, c, b])
		else:
			indices.append_array([a, b, c])

	func arrays() -> Array:
		var result := []
		result.resize(Mesh.ARRAY_MAX)
		result[Mesh.ARRAY_VERTEX] = vertices
		result[Mesh.ARRAY_NORMAL] = normals
		result[Mesh.ARRAY_COLOR] = colors
		result[Mesh.ARRAY_TEX_UV] = uvs
		result[Mesh.ARRAY_INDEX] = indices
		return result


static func _smooth(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Unit vector, uniform on the sphere.
static func _random_direction(rng: RandomNumberGenerator) -> Vector3:
	var y := rng.randf() * 2.0 - 1.0
	var a := rng.randf() * TAU
	var r := sqrt(1.0 - y * y)
	return Vector3(cos(a) * r, y, sin(a) * r)


## Trunk axis offset at height y (a slight lean that grows towards the top).
static func _lean(lean: Vector3, y: float, top: float) -> Vector3:
	var t := y / top
	return lean * t * t


## Tapered lathe trunk from y = 0 to `top`; `capped` closes the top ring with a centre vertex.
static func _add_trunk(
	s: Surface,
	top: float,
	r0: float,
	r1: float,
	lean: Vector3,
	sides: int,
	segments: int,
	capped: bool
) -> void:
	var rings: Array[int] = []
	for seg in segments + 1:
		var t := float(seg) / segments
		var y := top * t
		var c := _lean(lean, y, top) + Vector3(0, y, 0)
		var r := lerpf(r0, r1, t)
		rings.append(s.vertices.size())
		for side in sides + 1:
			var a := TAU * side / sides
			var d := Vector3(cos(a), 0.0, sin(a))
			var ao := 0.55 + 0.45 * _smooth(0.0, 0.08, y)
			s.add(c + d * r, d, Color(ao, 0.0, 0.0), Vector2(float(side) / sides, y * 12.0))
	for seg in segments:
		for side in sides:
			var a := rings[seg] + side
			var b := rings[seg + 1] + side
			var out := (
				s.vertices[a] - (_lean(lean, s.vertices[a].y, top) + Vector3(0, s.vertices[a].y, 0))
			)
			s.tri(a, b, b + 1, out)
			s.tri(a, b + 1, a + 1, out)
	if capped:
		var c := _lean(lean, top, top) + Vector3(0, top, 0)
		var center := s.add(c, Vector3.UP, Color(0.6, 0.0, 0.0), Vector2(0.5, top * 12.0))
		var ring := rings[segments]
		for side in sides:
			s.tri(center, ring + side, ring + side + 1, Vector3.UP)


## Tapered branch rod from `from` to `to` closed with a tip vertex.
static func _add_branch(s: Surface, from: Vector3, to: Vector3, r0: float, ao: float) -> void:
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var other := axis.cross(side).normalized()
	var length := from.distance_to(to)
	var rings: Array[int] = []
	for k in 2:
		var center := from.lerp(to, 0.0 if k == 0 else 0.8)
		var r := r0 if k == 0 else r0 * 0.45
		rings.append(s.vertices.size())
		for i in BRANCH_SIDES + 1:
			var a := TAU * i / BRANCH_SIDES
			var d := side * cos(a) + other * sin(a)
			s.add(
				center + d * r,
				d,
				Color(ao, 0.0, 0.0),
				Vector2(float(i) / BRANCH_SIDES, k * length * 12.0)
			)
	var tip := s.add(to, axis, Color(ao, 0.0, 0.0), Vector2(0.5, length * 12.0))
	for i in BRANCH_SIDES:
		var a := rings[0] + i
		var b := rings[1] + i
		var out := s.normals[a]
		s.tri(a, b, b + 1, out)
		s.tri(a, b + 1, a + 1, out)
		s.tri(b, tip, b + 1, s.normals[b])


## One leaf card: centre, the card's outward face normal, the axis the texture's v runs against
## (from v = 1 to v = 0), size and the bent-normal source. Vertices in corner order.
static func _add_card(
	s: Surface,
	center: Vector3,
	face: Vector3,
	up_axis: Vector3,
	size: float,
	crown_center: Vector3,
	normal_y_scale: float,
	ao_of: Callable,
	phase: float
) -> void:
	var n := face.normalized()
	var u := (up_axis - n * up_axis.dot(n)).normalized()
	var w := n.cross(u).normalized()
	var h := size * 0.5
	var corners := [
		[center - u * h - w * h, Vector2(0, 1)],
		[center - u * h + w * h, Vector2(1, 1)],
		[center + u * h + w * h, Vector2(1, 0)],
		[center + u * h - w * h, Vector2(0, 0)],
	]
	var first := s.vertices.size()
	for corner: Array in corners:
		var p: Vector3 = corner[0]
		var d := p - crown_center
		var bent := Vector3(d.x, d.y * normal_y_scale, d.z).normalized() * 0.8 + n * 0.2
		if bent.dot(d) <= 0.05 * d.length():
			bent = d
		s.add(p, bent, Color(ao_of.call(p), phase, 1.0), corner[1])
	s.tri(first, first + 1, first + 2, n)
	s.tri(first, first + 2, first + 3, n)


## Deciduous: lathe trunk, branches into lobes, leaf cards on the lobes.
static func _build_deciduous(
	p: Dictionary, rng: RandomNumberGenerator, bark: Surface, leaves: Surface
) -> Dictionary:
	var trunk: Array = p["trunk"]
	var top: float = trunk[0] * (0.95 + 0.1 * rng.randf())
	var lean_angle := rng.randf() * TAU
	var lean := Vector3(cos(lean_angle), 0.0, sin(lean_angle)) * float(trunk[3]) * rng.randf()
	_add_trunk(bark, top, trunk[1], trunk[2], lean, TRUNK_SIDES, TRUNK_SEGMENTS, true)
	var br: Array = p["branches"]
	var lb: Array = p["lobes"]
	var scale: Vector3 = lb[2]
	# Lobes as [centre, radius]: one per branch tip plus the top lobe.
	var lobes: Array[Array] = []
	var count: int = br[0]
	var start_angle := rng.randf() * TAU
	for i in count:
		var y := top * lerpf(br[1], br[2], (i + rng.randf() * 0.6) / count)
		var from := _lean(lean, y, top) + Vector3(0, y, 0)
		var heading := start_angle + TAU * (i * 0.618034 + rng.randf() * 0.15)
		var elevation := lerpf(br[3], br[4], rng.randf())
		var length := lerpf(br[5], br[6], rng.randf())
		var dir := Vector3(
			cos(heading) * cos(elevation), sin(elevation), sin(heading) * cos(elevation)
		)
		var tip := from + dir * length
		var radius := lerpf(lb[0], lb[1], rng.randf())
		_add_branch(bark, from, tip, float(trunk[1]) * 0.42, 0.55)
		lobes.append([tip + dir * radius * 0.25, radius])
	var top_lobe: Array = p["top"]
	var top_center := _lean(lean, top, top) + Vector3(0, top + float(top_lobe[0]), 0)
	lobes.append([top_center, float(top_lobe[1])])
	# Crown centre: lobe centres weighted by the lobe area.
	var crown_center := Vector3.ZERO
	var weight := 0.0
	var crown_radius := 0.0
	for lobe in lobes:
		var r: float = lobe[1]
		crown_center += (lobe[0] as Vector3) * r * r
		weight += r * r
	crown_center /= weight
	for lobe in lobes:
		var c: Vector3 = lobe[0]
		crown_radius = maxf(crown_radius, (c - crown_center).length() + float(lobe[1]))
	var cards: Array = p["cards"]
	var total: int = cards[0]
	var droop: float = p["droop"]
	var crown_bottom := INF
	for lobe in lobes:
		crown_bottom = minf(crown_bottom, (lobe[0] as Vector3).y - float(lobe[1]) * scale.y)
	var ao_of := func(v: Vector3) -> float:
		var depth := (v - crown_center).length() / crown_radius
		var height := clampf((v.y - crown_bottom) / (crown_radius * 2.0), 0.0, 1.0)
		return clampf(
			lerpf(0.5, 1.0, _smooth(0.15, 0.95, depth)) * lerpf(0.72, 1.0, height), 0.0, 1.0
		)
	var placed := 0
	for li in lobes.size():
		var lobe: Array = lobes[li]
		var r: float = lobe[1]
		var c: Vector3 = lobe[0]
		var n_cards := (
			int(round(total * r * r / weight)) if li < lobes.size() - 1 else total - placed
		)
		for k in n_cards:
			var d := _random_direction(rng)
			if d.y < -0.45 and rng.randf() < 0.6:
				d = _random_direction(rng)
			var f := lerpf(0.55, 1.0, sqrt(rng.randf()))
			var pos := c + Vector3(d.x * scale.x, d.y * scale.y, d.z * scale.z) * r * f
			var face := (d + _random_direction(rng) * 0.55).normalized()
			face = Vector3(face.x, face.y * (1.0 - droop), face.z).normalized()
			var up_axis := Vector3.UP.lerp(_random_direction(rng), 0.8)
			if droop > 0.0:
				up_axis = Vector3.UP.lerp(up_axis, 1.0 - droop * 0.6)
			var size := lerpf(cards[1], cards[2], rng.randf())
			_add_card(leaves, pos, face, up_axis, size, crown_center, 0.85, ao_of, rng.randf())
		placed += n_cards
	var bounds := _bounds(leaves.vertices)
	return {
		"crown_center": crown_center,
		"trunk_top": _lean(lean, top, top) + Vector3(0, top, 0),
		"trunk_radius": float(trunk[1]),
		"crown_min": bounds[0],
		"crown_max": bounds[1],
	}


## Spruce: lathe trunk to near the top, drooping needle-card whorls, a crossed leader on top.
static func _build_spruce(rng: RandomNumberGenerator, bark: Surface, leaves: Surface) -> Dictionary:
	var trunk: Array = SPRUCE["trunk"]
	var height: float = SPRUCE["height"] * (0.95 + 0.08 * rng.randf())
	var top := height * float(trunk[0]) / float(SPRUCE["height"])
	_add_trunk(bark, top, trunk[1], trunk[2], Vector3.ZERO, TRUNK_SIDES - 1, TRUNK_SEGMENTS, true)
	var bottom: float = SPRUCE["skirt_bottom"]
	var radii: Array = SPRUCE["radius"]
	var base_radius := lerpf(radii[0], radii[1], rng.randf())
	var droops: Array = SPRUCE["droop"]
	var sizes: Array = SPRUCE["size"]
	var whorls: int = SPRUCE["whorls"]
	var crown_center := Vector3(0, lerpf(bottom, height, 0.38), 0)
	var ao_of := func(v: Vector3) -> float:
		var rel := clampf((v.y - bottom) / (height - bottom), 0.0, 1.0)
		var radius_here := maxf(base_radius * (1.0 - rel), 0.01)
		var out := clampf(Vector2(v.x, v.z).length() / radius_here, 0.0, 1.0)
		return clampf(lerpf(0.45, 1.0, out) * lerpf(0.7, 1.0, rel), 0.0, 1.0)
	var spin := rng.randf() * TAU
	for wi in whorls:
		var rel := (wi + rng.randf() * 0.3) / whorls
		var y := lerpf(bottom, height * 0.9, rel)
		var radius := base_radius * pow(1.0 - (y - bottom) / (height - bottom), 0.95) + 0.012
		var size := clampf(radius * 0.72, sizes[0], sizes[1])
		var count := maxi(3, int(round(radius / base_radius * 8.0)))
		var layers := 2 if radius > size * 1.3 else 1
		spin += 0.9
		for i in count:
			var heading := spin + TAU * (i + rng.randf() * 0.3) / count
			var radial := Vector3(cos(heading), 0.0, sin(heading))
			var droop := lerpf(droops[0], droops[1], rng.randf())
			var out := (radial * cos(droop) - Vector3.UP * sin(droop)).normalized()
			var face := (radial * sin(droop) + Vector3.UP * cos(droop)).normalized()
			var tangent := radial.cross(Vector3.UP)
			face = face.rotated(out, (rng.randf() * 2.0 - 1.0) * 0.3)
			for layer in layers:
				var reach := size * 0.5 + (radius - size) * (0.0 if layers == 1 else float(layer))
				reach = maxf(reach, size * 0.5 + 0.004)
				var center := Vector3(0, y, 0) + out * reach + tangent * (rng.randf() - 0.5) * 0.01
				_add_card(leaves, center, face, out, size, crown_center, 0.4, ao_of, rng.randf())
	# Leader: two crossed vertical cards on top.
	for k in 2:
		var a := spin + PI * 0.5 * k
		var face := Vector3(cos(a), 0.0, sin(a))
		var center := Vector3(0, height - sizes[0] * 0.5, 0)
		_add_card(
			leaves,
			center,
			face,
			Vector3.UP,
			sizes[0],
			crown_center + Vector3(0, -0.2, 0),
			0.4,
			ao_of,
			rng.randf()
		)
	var bounds := _bounds(leaves.vertices)
	return {
		"crown_center": crown_center,
		"trunk_top": Vector3(0, top, 0),
		"trunk_radius": float(trunk[1]),
		"skirt_radius": base_radius + 0.012,
		"crown_min": bounds[0],
		"crown_max": bounds[1],
	}


## Pine: bare leaning trunk, short upper branches, flat needle tufts (cards facing mostly up).
static func _build_pine(rng: RandomNumberGenerator, bark: Surface, leaves: Surface) -> Dictionary:
	var trunk: Array = PINE["trunk"]
	var top: float = trunk[0] * (0.95 + 0.08 * rng.randf())
	var lean_angle := rng.randf() * TAU
	var lean := (
		Vector3(cos(lean_angle), 0.0, sin(lean_angle)) * float(trunk[3]) * (0.4 + 0.6 * rng.randf())
	)
	_add_trunk(bark, top, trunk[1], trunk[2], lean, TRUNK_SIDES - 1, TRUNK_SEGMENTS + 1, true)
	var br: Array = PINE["branches"]
	var tf: Array = PINE["tufts"]
	var scale: Vector3 = tf[2]
	var tufts: Array[Array] = []
	var count: int = br[0]
	var start_angle := rng.randf() * TAU
	for i in count:
		var y := top * lerpf(br[1], br[2], (i + rng.randf() * 0.5) / count)
		var from := _lean(lean, y, top) + Vector3(0, y, 0)
		var heading := start_angle + TAU * (i * 0.618034 + rng.randf() * 0.15)
		var elevation := lerpf(br[3], br[4], rng.randf())
		var length := lerpf(br[5], br[6], rng.randf())
		var dir := Vector3(
			cos(heading) * cos(elevation), sin(elevation), sin(heading) * cos(elevation)
		)
		var tip := from + dir * length
		_add_branch(bark, from, tip, float(trunk[1]) * 0.45, 0.6)
		tufts.append([tip, lerpf(tf[0], tf[1], rng.randf())])
	var top_tuft: Array = PINE["top"]
	tufts.append(
		[_lean(lean, top, top) + Vector3(0, top + float(top_tuft[0]), 0), float(top_tuft[1])]
	)
	var crown_center := Vector3.ZERO
	var weight := 0.0
	for tuft in tufts:
		var r: float = tuft[1]
		crown_center += (tuft[0] as Vector3) * r * r
		weight += r * r
	crown_center /= weight
	crown_center.y -= 0.02
	var cards: Array = PINE["cards"]
	var total: int = cards[0]
	var low := top * float(br[1])
	var ao_of := func(v: Vector3) -> float:
		var rel := clampf((v.y - low) / (top + 0.04 - low), 0.0, 1.0)
		var out := clampf((v - crown_center).length() / 0.08, 0.0, 1.0)
		return clampf(lerpf(0.5, 1.0, out) * lerpf(0.7, 1.0, rel), 0.0, 1.0)
	var placed := 0
	for ti in tufts.size():
		var tuft: Array = tufts[ti]
		var r: float = tuft[1]
		var c: Vector3 = tuft[0]
		var n_cards := (
			int(round(total * r * r / weight)) if ti < tufts.size() - 1 else total - placed
		)
		for k in n_cards:
			var d := _random_direction(rng)
			var f := lerpf(0.5, 1.0, sqrt(rng.randf()))
			var pos := c + Vector3(d.x * scale.x, d.y * scale.y, d.z * scale.z) * r * f
			var face := (d * 0.6 + Vector3.UP * 0.9 + _random_direction(rng) * 0.35).normalized()
			var out := Vector3(d.x, 0.0, d.z)
			if out.length() < 0.1:
				out = Vector3(cos(k), 0.0, sin(k))
			var size := lerpf(cards[1], cards[2], rng.randf())
			_add_card(
				leaves, pos, face, out.normalized(), size, crown_center, 0.5, ao_of, rng.randf()
			)
		placed += n_cards
	var bounds := _bounds(leaves.vertices)
	return {
		"crown_center": crown_center,
		"trunk_top": _lean(lean, top, top) + Vector3(0, top, 0),
		"trunk_radius": float(trunk[1]),
		"crown_min": bounds[0],
		"crown_max": bounds[1],
	}


static func _bounds(points: PackedVector3Array) -> Array[Vector3]:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	return [lo, hi]


## LOD1: closed cone (side triangles only, the base is never seen from the camera).
static func _add_cone(
	s: Surface, base: Vector3, radius: float, height: float, crown_center: Vector3, salt: int
) -> void:
	var apex_p := base + Vector3(0, height, 0)
	var ring: Array[int] = []
	for i in LOD1_CONE_SIDES:
		var a := TAU * (i + 0.5 * salt) / LOD1_CONE_SIDES
		var f := 1.0 + (FoliageMeshes.hash3(i, salt, 3.0) - 0.5) * 0.3
		var p := base + Vector3(cos(a), 0.0, sin(a)) * radius * f
		ring.append(_crown_vertex(s, p, crown_center, 0.4))
	var apex := _crown_vertex(s, apex_p, crown_center, 0.4)
	for i in LOD1_CONE_SIDES:
		var a := ring[i]
		var b := ring[(i + 1) % LOD1_CONE_SIDES]
		var mid := (s.vertices[a] + s.vertices[b]) * 0.5 - base
		s.tri(a, b, apex, Vector3(mid.x, radius * 0.5, mid.z))


## LOD1: jittered icosphere lobes; triangles inside another lobe are dropped (never visible).
static func _add_lobes(s: Surface, lobes: Array[Array], crown_center: Vector3) -> void:
	var sphere := _unit_sphere(LOD1_LOBE_SUBDIVISIONS)
	for li in lobes.size():
		var c: Vector3 = lobes[li][0]
		var e: Vector3 = lobes[li][1]
		for i in range(0, sphere.size(), 3):
			var pts: Array[Vector3] = []
			for k in 3:
				var u := sphere[i + k]
				var f := (
					1.0
					+ (
						(FoliageMeshes.hash3(u.x * 9.0 + li, u.y * 9.0, u.z * 9.0) - 0.5)
						* LOD1_JITTER
					)
				)
				pts.append(c + Vector3(u.x * e.x, u.y * e.y, u.z * e.z) * f)
			var mid := (pts[0] + pts[1] + pts[2]) / 3.0
			if _inside_other(mid, lobes, li):
				continue
			var ids: Array[int] = []
			for p in pts:
				ids.append(_crown_vertex(s, p, crown_center, 0.85))
			s.tri(ids[0], ids[1], ids[2], mid - c)


static func _inside_other(p: Vector3, lobes: Array[Array], skip: int) -> bool:
	for li in lobes.size():
		if li == skip:
			continue
		var c: Vector3 = lobes[li][0]
		var e: Vector3 = lobes[li][1]
		var d := p - c
		var q := Vector3(d.x / e.x, d.y / e.y, d.z / e.z)
		if q.length() < 0.9:
			return true
	return false


static func _crown_vertex(s: Surface, p: Vector3, crown_center: Vector3, y_scale: float) -> int:
	var d := p - crown_center
	var n := Vector3(d.x, d.y * y_scale + 0.01, d.z)
	var ao := 0.5 + 0.5 * _smooth(0.05, 0.28, p.y)
	return s.add(p, n, Color(ao, 0.0, 1.0), Vector2(0.5, 0.5))


## Unit icosphere as a flat list of triangle vertices (shared with FoliageMeshes' construction).
static func _unit_sphere(subdivisions: int) -> PackedVector3Array:
	if not _unit_spheres.has(subdivisions):
		_unit_spheres[subdivisions] = FoliageMeshes._unit_sphere(subdivisions)
	return _unit_spheres[subdivisions]
