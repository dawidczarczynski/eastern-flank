extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const EPS := 0.001

var _surface: TerrainSurface
var _inner := Rect2(-10.0, -8.0, 20.0, 16.0)


func before_each() -> void:
	# A hand-built grid with elevations and no TerrainField (no MapGenerator involved).
	var grid := Fixtures.plains_grid(2)
	grid.set_elevation(Vector2i(2, 0), 1.2)
	_surface = TerrainSurface.new(grid)


func test_distance_zero_equals_the_border_height() -> void:
	for p: Vector2 in [
		Vector2(-10, 0), Vector2(10, 3), Vector2(2, -8), Vector2(-4, 8), Vector2(10, 8)
	]:
		var expected := _surface.height_at(p.x, p.y)
		assert_true(absf(BackdropHeights.height_at(_surface, _inner, p.x, p.y) - expected) < EPS)


func test_is_deterministic() -> void:
	var a := BackdropHeights.height_at(_surface, _inner, 18.5, -3.2)
	var b := BackdropHeights.height_at(_surface, _inner, 18.5, -3.2)
	assert_eq(a, b)


func test_varies_with_position_far_from_the_edge() -> void:
	var seen := {}
	for i in 12:
		seen[snappedf(BackdropHeights.height_at(_surface, _inner, 20.0 + i * 1.3, 0.7 * i), 0.001)] = true
	assert_true(seen.size() > 3, "noise should vary the ground")


func test_stays_in_a_gentle_range() -> void:
	for i in 40:
		var h := BackdropHeights.height_at(_surface, _inner, 12.0 + i * 0.7, -20.0 + i)
		assert_true(h > -1.0 and h < 3.0, "height %s" % h)


func test_continuous_along_the_edge_normal() -> void:
	var a := BackdropHeights.height_at(_surface, _inner, 10.0, 1.0)
	var b := BackdropHeights.height_at(_surface, _inner, 10.05, 1.0)
	assert_true(absf(a - b) < 0.1, "no step at the seam")
