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


func test_two_paths_are_too_many() -> void:
	_assert_error(["/tmp/a.png", "/tmp/b.png"], "too_many_arguments")


func _assert_error(args: Array, expected: String) -> void:
	var options := ScreenshotOptions.parse(PackedStringArray(args))
	assert_eq(options["error"], expected, str(args))
