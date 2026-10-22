# gdlint: disable=max-public-methods
extends TestCase
## Argument parsing for tools/screenshot.gd (see TASK-006).

const ScreenshotOptions := preload("res://tools/screenshot_options.gd")


func test_no_arguments_gives_defaults() -> void:
	var options := ScreenshotOptions.parse(PackedStringArray())
	assert_eq(options["output"], "")
	assert_eq(options["frames"], 10)
	assert_eq(options["error"], "")


func test_output_and_frames() -> void:
	var options := ScreenshotOptions.parse(PackedStringArray(["/tmp/a.png", "--frames=30"]))
	assert_eq(options["output"], "/tmp/a.png")
	assert_eq(options["frames"], 30)
	assert_eq(options["error"], "")


func test_frames_before_output() -> void:
	var options := ScreenshotOptions.parse(PackedStringArray(["--frames=600", "/tmp/b.png"]))
	assert_eq(options["output"], "/tmp/b.png")
	assert_eq(options["frames"], 600)
	assert_eq(options["error"], "")


func test_frames_lower_bound_is_valid() -> void:
	var options := ScreenshotOptions.parse(PackedStringArray(["--frames=1"]))
	assert_eq(options["frames"], 1)
	assert_eq(options["error"], "")


func test_zero_frames_is_invalid() -> void:
	_assert_error(["--frames=0"], "invalid_frames")


func test_too_many_frames_is_invalid() -> void:
	_assert_error(["--frames=601"], "invalid_frames")


func test_non_numeric_frames_is_invalid() -> void:
	_assert_error(["--frames=abc"], "invalid_frames")


func test_empty_frames_is_invalid() -> void:
	_assert_error(["--frames="], "invalid_frames")


func test_unknown_option() -> void:
	_assert_error(["--zoom=3"], "unknown_option")


func test_quality_option_is_accepted() -> void:
	var options := ScreenshotOptions.parse(PackedStringArray(["--quality=low", "/tmp/a.png"]))
	assert_eq(options["error"], "")
	assert_eq(options["output"], "/tmp/a.png")


func test_two_paths_are_too_many() -> void:
	_assert_error(["/tmp/a.png", "/tmp/b.png"], "too_many_arguments")


func _assert_error(args: Array, expected: String) -> void:
	var options := ScreenshotOptions.parse(PackedStringArray(args))
	assert_eq(options["error"], expected, str(args))


func test_camera_spec_unit_yaw_distance() -> void:
	var camera := ScreenshotOptions.parse_camera("3,-30,12.5")
	assert_eq(camera["unit_id"], 3)
	assert_eq(camera["yaw_degrees"], -30.0)
	assert_eq(camera["distance"], 12.5)
	assert_eq(camera["error"], "")


func test_camera_spec_with_spaces() -> void:
	var camera := ScreenshotOptions.parse_camera(" 1, 45 ,14 ")
	assert_eq(camera["unit_id"], 1)
	assert_eq(camera["yaw_degrees"], 45.0)
	assert_eq(camera["distance"], 14.0)
	assert_eq(camera["error"], "")


func test_empty_camera_spec_means_default_camera() -> void:
	assert_eq(ScreenshotOptions.parse_camera("")["error"], "none")


func test_camera_spec_needs_three_values() -> void:
	assert_eq(ScreenshotOptions.parse_camera("1,30")["error"], "invalid_camera")


func test_camera_spec_unit_must_be_an_integer() -> void:
	assert_eq(ScreenshotOptions.parse_camera("a,30,12")["error"], "invalid_camera")


func test_camera_spec_numbers_must_be_numeric() -> void:
	assert_eq(ScreenshotOptions.parse_camera("1,x,12")["error"], "invalid_camera")
	assert_eq(ScreenshotOptions.parse_camera("1,30,")["error"], "invalid_camera")


func test_camera_spec_distance_must_be_positive() -> void:
	assert_eq(ScreenshotOptions.parse_camera("1,30,0")["error"], "invalid_camera")


func test_focus_spec_point_yaw_distance() -> void:
	var focus := ScreenshotOptions.parse_focus("14.7, 4.5,-30,7")
	assert_eq(focus["target"], Vector2(14.7, 4.5))
	assert_eq(focus["yaw_degrees"], -30.0)
	assert_eq(focus["distance"], 7.0)
	assert_eq(focus["error"], "")


func test_focus_spec_empty_and_invalid() -> void:
	assert_eq(ScreenshotOptions.parse_focus("")["error"], "none")
	assert_eq(ScreenshotOptions.parse_focus("1,2,3")["error"], "invalid_focus")
	assert_eq(ScreenshotOptions.parse_focus("1,a,3,4")["error"], "invalid_focus")
	assert_eq(ScreenshotOptions.parse_focus("1,2,3,0")["error"], "invalid_focus")


func test_measure_frames_spec() -> void:
	assert_eq(ScreenshotOptions.parse_measure_frames(""), 0)
	assert_eq(ScreenshotOptions.parse_measure_frames("120"), 120)
	assert_eq(ScreenshotOptions.parse_measure_frames("x"), 0)
	assert_eq(ScreenshotOptions.parse_measure_frames("-5"), 0)
	assert_eq(ScreenshotOptions.parse_measure_frames("100000"), ScreenshotOptions.MAX_FRAMES)
