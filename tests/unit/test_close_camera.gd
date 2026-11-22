extends TestCase

## The close camera range (TASK-111): down to CameraMath.MIN_DISTANCE (~26 m) the camera stays at
## least 2 m above the drawn ground everywhere on the Suwalki map, the near plane shrinks and the
## pan speed scales with the distance.

const EPS := 0.001

const DISTANCES: Array[float] = [0.18, 0.25, 0.5, 1.0, 3.0, 7.0, 10.0, 24.0]
const YAWS: Array[float] = [0.0, 1.3, 2.6, 3.9, 5.2]
## Every SAMPLE_STEP-th tile of the map is a camera target (with an off-centre jitter).
const SAMPLE_STEP := 7

static var _view: MapView
static var _grid: HexGrid

var _rig: CameraRig
var _camera: Camera3D


func _near(actual: float, expected: float) -> void:
	assert_true(absf(actual - expected) < EPS, "expected %s, got %s" % [expected, actual])


func before_all() -> void:
	_grid = ImportedMap.find(Scenario.SUWALKI_MAP_ID).to_grid()
	MapScale.apply_map_id(Scenario.SUWALKI_MAP_ID)
	_view = MapView.new()
	_view._ready()
	_view.quality = GraphicsQuality.features(GraphicsQuality.Level.HIGH)
	_view.build(_grid)


func after_all() -> void:
	_view.free()
	_view = null
	_grid = null
	MapScale.reset()


func before_each() -> void:
	_rig = CameraRig.new()
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_rig.add_child(_camera)
	_rig._camera = _camera  # outside a scene tree @onready does not run


func after_each() -> void:
	_rig.free()


func _camera_world() -> Vector3:
	return _rig.position + _camera.position


func test_camera_stays_two_metres_above_the_ground_on_the_suwalki_map() -> void:
	assert_true(_view.terrain_near() != null, "HIGH builds the near terrain")
	_rig.set_ground_query(_view.camera_ground_height)
	var two_m := MapScale.to_units(CameraMath.MIN_HEIGHT_METRES)
	var lowest := INF
	var samples := 0
	var coords := _grid.coords()
	for i in range(0, coords.size(), SAMPLE_STEP):
		var w := Hex.to_world(coords[i], _view.hex_size)
		var target := Vector2(w.x + 0.21 * (i % 3), w.z - 0.17 * (i % 4))
		for yaw in YAWS:
			for d in DISTANCES:
				_rig.set_view(target, yaw, d)
				var cam := _camera_world()
				var above := cam.y - _view.camera_ground_height(cam.x, cam.z)
				lowest = minf(lowest, above)
				samples += 1
				if above < two_m - 0.0001:
					assert_true(
						false,
						(
							"%.1f m above the ground at %s d %s"
							% [above * MapScale.metres_per_unit, target, d]
						)
					)
					return
	assert_true(samples > 500, "%d samples" % samples)
	print("  lowest camera: %.2f m above the ground" % (lowest * MapScale.metres_per_unit))


func test_camera_ground_is_at_least_the_visible_ground_and_the_water() -> void:
	# camera_ground_height takes the near surface and the water plane into account.
	var c := _view.center()
	var h := _view.camera_ground_height(c.x, c.z)
	assert_true(h >= _view.visible_ground_height(c.x, c.z))
	assert_true(h >= TerrainSurface.WATER_SURFACE)


func test_near_plane_follows_the_zoom() -> void:
	_rig.set_view(Vector2.ZERO, 0.0, CameraMath.MIN_DISTANCE)
	assert_true(_camera.near <= 0.01, "near %s at the minimum" % _camera.near)
	_rig.set_view(Vector2.ZERO, 0.0, CameraRig.DEFAULT_DISTANCE)
	assert_true(is_equal_approx(_camera.near, 0.1))


func test_close_up_looks_towards_the_horizon_at_the_ground() -> void:
	_rig.set_ground_query(_view.camera_ground_height)
	var c := _view.center()
	_rig.set_view(Vector2(c.x, c.z), 0.0, CameraMath.MIN_DISTANCE)
	var cam := _camera_world()
	var look := -_camera.transform.basis.z
	var pitch := asin(-look.y)
	assert_true(pitch < deg_to_rad(25.0), "pitch %s deg" % rad_to_deg(pitch))
	# The look-at point is a hair above the ground under the target, not 0.4 units (58 m) up.
	var ground := _view.camera_ground_height(c.x, c.z)
	var aim := cam + look * CameraMath.MIN_DISTANCE
	assert_true(absf(aim.y - ground) < 0.03, "aim %s, ground %s" % [aim.y, ground])


func test_pan_speed_scales_with_the_distance() -> void:
	var drag := Vector2(100, 0)
	var far := CameraMath.pan_delta(drag, 0.0, 24.0).length()
	var close := CameraMath.pan_delta(drag, 0.0, CameraMath.MIN_DISTANCE).length()
	assert_true(absf(close / far - CameraMath.MIN_DISTANCE / 24.0) < 0.0001)
	# 100 px of drag at the minimum moves the target a few metres, not a hex.
	var metres := close * MapScale.metres_per_unit
	assert_true(metres > 1.0 and metres < 10.0, "%.1f m" % metres)


func test_zoom_steps_are_geometric_and_reach_the_minimum_in_25_notches() -> void:
	var d := CameraMath.MAX_DISTANCE
	var steps := 0
	while d > CameraMath.MIN_DISTANCE and steps < 100:
		var next := CameraMath.zoom(d, -1.0)
		if next > CameraMath.MIN_DISTANCE:
			var ratio := d / next
			assert_true(absf(ratio / CameraMath.ZOOM_STEP_FACTOR - 1.0) <= 0.01, "ratio %s" % ratio)
		d = next
		steps += 1
	_near(d, CameraMath.MIN_DISTANCE)
	assert_true(steps <= 25, "%d notches from 46 to the minimum" % steps)
	# Zooming out mirrors zooming in.
	_near(CameraMath.zoom(CameraMath.zoom(10.0, -1.0), 1.0), 10.0)
	# From the default too.
	_near(CameraMath.zoom(24.0, -100.0), CameraMath.MIN_DISTANCE)


func test_near_plane_is_small_at_the_closest_zoom() -> void:
	assert_true(CameraMath.near_plane(CameraMath.MIN_DISTANCE) <= 0.01)
	assert_true(CameraMath.near_plane(CameraMath.MIN_DISTANCE) > 0.0)
	_near(CameraMath.near_plane(24.0), 0.1)
	_near(CameraMath.near_plane(46.0), 0.1)
	# Never past the look-at point's ground at any zoom (the camera is at least this far away).
	var d := CameraMath.MIN_DISTANCE
	while d <= CameraMath.MAX_DISTANCE:
		assert_true(CameraMath.near_plane(d) < d * sin(CameraMath.PITCH_MIN), "d %s" % d)
		d *= 1.1


func test_clearance_is_at_least_two_metres() -> void:
	var two_m := MapScale.to_units(2.0)
	_near(CameraMath.clearance(CameraMath.CLOSE_RANGE_DISTANCE), CameraMath.GROUND_CLEARANCE)
	_near(CameraMath.clearance(46.0), CameraMath.GROUND_CLEARANCE)
	_near(CameraMath.clearance(CameraMath.MIN_DISTANCE), two_m)
	_near(CameraMath.clearance(3.5), CameraMath.GROUND_CLEARANCE * 0.25)
	var d := CameraMath.MIN_DISTANCE
	while d <= CameraMath.MAX_DISTANCE:
		assert_true(CameraMath.clearance(d) >= two_m - EPS * 0.01, "d %s" % d)
		d *= 1.1
