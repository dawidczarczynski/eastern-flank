extends TestCase
## Real-scale vegetation on the Suwalki map (TASK-135, follow-up of TASK-134 / ADR 0025): the
## grass, the ground cover and the full trees within the near-terrain reach (3 units) stand on the
## drawn near surface (TerrainNear.drawn_height_at), not on the 36 m lattice – mean and max offset
## at most 0.1 m.

const TENTH_M := 0.1 / MapScale.DEFAULT_METRES_PER_UNIT
const NEAR_REACH := 3.0

static var _view: MapView
static var _target := Vector2.ZERO


func before_all() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var grid := ImportedMap.find(Scenario.SUWALKI_MAP_ID).to_grid()
	_view = MapView.new()
	_view._ready()
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	_view.build(grid)
	# The forest tile nearest the map centre with forest all around it.
	var centre := _view.center()
	var best := INF
	for c in grid.coords():
		if grid.get_terrain(c) != Terrain.Type.FOREST:
			continue
		var w := Hex.to_world(c, _view.hex_size)
		var d := Vector2(w.x - centre.x, w.z - centre.z).length()
		if d < best:
			best = d
			_target = Vector2(w.x + 0.4, w.z - 0.3)
	var ground := _view.vegetation_ground_height(_target.x, _target.y)
	_view.set_camera_distance(1.2)
	_view.set_camera_position(
		Vector3(_target.x, ground, _target.y) + CameraMath.camera_offset(0.7, 1.2)
	)
	_view.finish_chunks(_target)


func after_all() -> void:
	_view.free()
	_view = null
	VisualScale.reset()


## Offsets (world units) of base points within the near reach to the drawn near surface.
func _offsets(points: PackedVector3Array, lift: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for p in points:
		if Vector2(p.x, p.z).distance_to(_target) > NEAR_REACH:
			continue
		var drawn := _view.terrain_near().drawn_height_at(p.x, p.z)
		if is_nan(drawn):
			continue
		result.append(absf(p.y + lift - drawn))
	return result


func _assert_on_surface(offsets: PackedFloat32Array, label: String, at_least: int) -> void:
	assert_true(offsets.size() >= at_least, "%s: %d checked" % [label, offsets.size()])
	var total := 0.0
	var worst := 0.0
	for o in offsets:
		total += o
		worst = maxf(worst, o)
	var mean := total / maxi(offsets.size(), 1)
	var scale := MapScale.DEFAULT_METRES_PER_UNIT
	assert_true(
		mean <= TENTH_M and worst <= TENTH_M,
		"%s: mean %.3f m, max %.3f m" % [label, mean * scale, worst * scale]
	)


func test_full_dense_trees_stand_on_the_near_surface() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var forest := _view.vegetation().forest
	var points := PackedVector3Array()
	for node in forest.full_nodes():
		points.append_array(forest.instance_positions(node))
	var sink := TreeField.sink(&"pine", LookPreset.vegetation())
	_assert_on_surface(_offsets(points, sink), "dense trees", 500)


func test_planned_trees_and_ground_cover_stand_on_the_near_surface() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var trees := _view.trees()
	var values := LookPreset.vegetation()
	var offsets := PackedFloat32Array()
	for node in trees.lod0_nodes():
		if node.get_meta(&"backdrop", false):
			continue
		var points := PackedVector3Array()
		for t in trees.instance_transforms(node):
			points.append(node.position + t.origin)
		offsets.append_array(_offsets(points, TreeField.sink(node.get_meta(&"species"), values)))
	_assert_on_surface(offsets, "planned trees and ground cover", 30)


func test_grass_stands_on_the_near_surface() -> void:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	var near := _view.vegetation().grass_near
	var points := PackedVector3Array()
	for node in near.nodes():
		points.append_array(near.instance_positions(node))
	_assert_on_surface(_offsets(points, 0.0), "near grass", 1000)
	# The far grass layer stands on the same surface (its plans, within the near reach).
	var far := PackedVector3Array()
	var rect := Rect2(_target - Vector2.ONE * NEAR_REACH, Vector2.ONE * 2.0 * NEAR_REACH)
	for chunk in GrassPlanner.chunks_covering(rect):
		var plan := _view.grass().plan_chunk(chunk)
		for kind: String in ["grass", "reeds"]:
			for item: Dictionary in plan[kind]["items"]:
				far.append(item["position"])
	_assert_on_surface(_offsets(far, 0.0), "grass", 20)
