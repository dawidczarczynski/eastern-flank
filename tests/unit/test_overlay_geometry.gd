extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const TOL := 0.001


func _corner(c: Vector2, s: float, i: int) -> Vector2:
	var a := deg_to_rad(60.0 * i - 30.0)
	return c + s * Vector2(cos(a), sin(a))


func _has_point(points: PackedVector2Array, p: Vector2) -> bool:
	for q in points:
		if q.distance_to(p) < TOL:
			return true
	return false


## Distance of p from the centre measured along the hexagon "radius" (pointy-top).
func _hex_radius(p: Vector2, c: Vector2) -> float:
	var d := p - c
	var r := 0.0
	for i in 6:
		var a := deg_to_rad(60.0 * i)  # edge normals of the pointy-top hexagon
		r = maxf(r, d.dot(Vector2(cos(a), sin(a))))
	return r / cos(deg_to_rad(30.0))


func test_hex_patch_vertex_count_and_extent() -> void:
	var c := Vector2(1.5, -2.0)
	var points := OverlayGeometry.hex_patch(c, 0.9, 4)
	assert_eq(points.size(), 288)
	for p in points:
		assert_true(p.distance_to(c) <= 0.9 + TOL)
	for i in 6:
		assert_true(_has_point(points, _corner(c, 0.9, i)), "corner %d" % i)


func test_hex_ring_vertices_lie_on_the_outlines() -> void:
	var c := Vector2(0.5, 1.0)
	var points := OverlayGeometry.hex_ring(c, 0.86, 0.92, 5)
	assert_eq(points.size(), 180)
	for p in points:
		var r := _hex_radius(p, c)
		assert_true(absf(r - 0.86) < TOL or absf(r - 0.92) < TOL, "radius %f" % r)


func test_drape_puts_points_on_the_surface_plus_lift() -> void:
	var surface := TerrainSurface.new(Fixtures.plains_grid(2))
	var flat := OverlayGeometry.hex_patch(Vector2.ZERO, 0.9, 4)
	var draped := OverlayGeometry.drape(flat, surface, 0.03)
	assert_eq(draped.size(), flat.size())
	for v in draped:
		assert_true(absf(v.y - 0.23) < TOL, "y %f" % v.y)


func test_drape_with_uses_the_given_height_function() -> void:
	var flat := PackedVector2Array([Vector2(1, 2), Vector2(-3, 0.5)])
	var draped := OverlayGeometry.drape_with(
		flat, func(x: float, z: float) -> float: return x + z, 0.05
	)
	assert_eq(draped.size(), 2)
	assert_true(draped[0].distance_to(Vector3(1, 3.05, 2)) < TOL, "got %s" % draped[0])
	assert_true(draped[1].distance_to(Vector3(-3, -2.45, 0.5)) < TOL, "got %s" % draped[1])


func test_curve_points_are_equally_spaced() -> void:
	var centers := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(4, 0)])
	var pts := OverlayGeometry.curve_points(centers, 10)
	assert_eq(pts.size(), 11)
	assert_true(pts[0].distance_to(Vector2(0, 0)) < TOL)
	assert_true(pts[10].distance_to(Vector2(4, 0)) < TOL)
	for i in pts.size():
		assert_true(absf(pts[i].y) < TOL)
		if i > 0:
			assert_true(absf(pts[i].distance_to(pts[i - 1]) - 0.4) < 0.01, "step %d" % i)


func test_path_dot_count() -> void:
	assert_eq(OverlayGeometry.path_dot_count(3), 9)
	assert_eq(OverlayGeometry.path_dot_count(1), 0)
	assert_eq(OverlayGeometry.path_dot_count(20), 79)


func test_hover_alpha_range() -> void:
	assert_true(absf(OverlayGeometry.hover_alpha(0.0) - 0.6) < TOL)
	var lo := 1.0
	var hi := 0.0
	for ms in range(0, 2000, 5):
		var a := OverlayGeometry.hover_alpha(float(ms))
		lo = minf(lo, a)
		hi = maxf(hi, a)
	assert_true(hi <= 0.85 + TOL and lo >= 0.35 - TOL)


func test_boundary_edges_of_one_hex_is_its_outline() -> void:
	var coords: Array[Vector2i] = [Vector2i(0, 0)]
	assert_eq(OverlayGeometry.boundary_edges(coords, 1.0).size(), 12)


func test_boundary_edges_skip_shared_edges() -> void:
	var pair: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	assert_eq(OverlayGeometry.boundary_edges(pair, 1.0).size(), 20, "2 hexes: 10 edges")
	var flower: Array[Vector2i] = [Vector2i(0, 0)]
	flower.append_array(Hex.neighbors(Vector2i(0, 0)))
	assert_eq(OverlayGeometry.boundary_edges(flower, 1.0).size(), 36, "7 hexes: 18 edges")


func test_boundary_edges_lie_on_hex_corners_facing_outwards() -> void:
	var coords: Array[Vector2i] = [Vector2i(0, 0)]
	var edges := OverlayGeometry.boundary_edges(coords, 2.0)
	for p in edges:
		assert_true(absf(p.length() - 2.0) < 0.0001, "corner at distance size")
	# Neighbour (1, 0) lies to the east: with a single hex all edges exist, so check the edge
	# facing east is the one between corners at -30° and +30°.
	var east := Vector2(2.0 * cos(deg_to_rad(-30.0)), 2.0 * sin(deg_to_rad(-30.0)))
	var found := false
	for i in edges.size() / 2:
		if edges[i * 2].distance_to(east) < 0.0001:
			found = absf(edges[i * 2 + 1].y - 1.0) < 0.0001
	assert_true(found, "east edge runs from -30° to +30°")


func test_edge_ribbons_triangle_count() -> void:
	var coords: Array[Vector2i] = [Vector2i(0, 0)]
	var edges := OverlayGeometry.boundary_edges(coords, 1.0)
	assert_eq(OverlayGeometry.edge_ribbons(edges, 0.1, 3).size(), 6 * 3 * 6)


func test_grid_alpha_fades_with_distance() -> void:
	assert_true(absf(OverlayGeometry.grid_alpha(7.0, false) - 0.16) < TOL)
	assert_true(absf(OverlayGeometry.grid_alpha(46.0, false) - 0.05) < TOL)
	assert_true(absf(OverlayGeometry.grid_alpha(26.5, false) - 0.105) < TOL)
	assert_true(absf(OverlayGeometry.grid_alpha(100.0, false) - 0.05) < TOL)
	assert_true(absf(OverlayGeometry.grid_alpha(3.0, false) - 0.16) < TOL)


func test_grid_alpha_is_stronger_while_selected() -> void:
	assert_true(absf(OverlayGeometry.grid_alpha(7.0, true) - 0.24) < TOL)
