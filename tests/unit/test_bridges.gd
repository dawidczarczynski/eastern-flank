extends TestCase
## Bridges (TASK-108c): the merged bridge mesh over the sites of FeatureRibbonPlanner.bridges.

const Fixtures := preload("res://tests/fixtures.gd")
const RIVER_Y := 0.05
const ROAD_Y := 0.2


func _drape(points: PackedVector2Array, lift: float) -> PackedVector3Array:
	# Flat ground at 0.1; a hill under the road ends is not needed here.
	var result := PackedVector3Array()
	for p in points:
		result.append(Vector3(p.x, 0.1 + lift, p.y))
	return result


func _site(x: float, direction: Vector2) -> Dictionary:
	return {
		"position": Vector2(x, 0.0),
		"direction": direction,
		"span_m": 20.0,
		"water_m": 8.0,
		"width_m": 7.0,
	}


func after_each() -> void:
	MapScale.reset()


func test_no_sites_no_node() -> void:
	assert_true(Bridges.build([], _drape) == null)


func test_one_mesh_for_all_sites_within_the_triangle_budget() -> void:
	var sites: Array[Dictionary] = [_site(0.0, Vector2.RIGHT), _site(3.0, Vector2(0.6, 0.8))]
	var node := Bridges.build(sites, _drape)
	assert_eq(node.name, &"Bridges")
	var mesh := node.mesh as ArrayMesh
	assert_eq(mesh.get_surface_count(), 1, "one draw call")
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(vertices.size() % 3, 0)
	var triangles := vertices.size() / 3
	assert_true(triangles <= Bridges.MAX_TRIANGLES * sites.size(), "%d triangles" % triangles)
	assert_true(triangles > 20 * sites.size(), "a real mesh")
	node.free()


func test_deck_clears_the_water_and_meets_the_road() -> void:
	var site := _site(0.0, Vector2.RIGHT)
	var p := Bridges.profile(site, _drape)
	var road_lift := FeatureRibbonPlanner.lift(FeatureRibbonPlanner.Kind.ROAD)
	var river_lift := FeatureRibbonPlanner.lift(FeatureRibbonPlanner.Kind.RIVER)
	var tolerance := MapScale.to_units(0.3)
	assert_true(absf((p["a"] as Vector3).y - (0.1 + road_lift)) <= tolerance, "end a on the road")
	assert_true(absf((p["b"] as Vector3).y - (0.1 + road_lift)) <= tolerance, "end b on the road")
	var water_y := 0.1 + river_lift
	assert_true((p["mid"] as Vector3).y >= water_y + MapScale.to_units(1.5) - 1e-6, "1.5 m up")
	var half := MapScale.to_units(20.0) / 2.0
	assert_true(
		absf((p["a"] as Vector3).x + half) < 1e-6 and absf((p["b"] as Vector3).x - half) < 1e-6
	)


func test_mesh_stays_within_the_site_footprint() -> void:
	var node := Bridges.build([_site(0.0, Vector2.RIGHT)] as Array[Dictionary], _drape)
	var box := node.mesh.get_aabb()
	var half := MapScale.to_units(20.0) / 2.0
	assert_true(box.size.x <= 2.0 * half + 1e-5, "no longer than its span")
	assert_true(absf(box.size.z - MapScale.to_units(7.0)) < 1e-5, "7 m wide")
	node.free()


func test_shadows_follow_the_flag() -> void:
	var sites: Array[Dictionary] = [_site(0.0, Vector2.RIGHT)]
	var on := Bridges.build(sites, _drape, true)
	var off := Bridges.build(sites, _drape, false)
	assert_eq(on.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_eq(off.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	on.free()
	off.free()
