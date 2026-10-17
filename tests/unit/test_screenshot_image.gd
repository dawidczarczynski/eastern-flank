extends TestCase
## Blank-frame detection for tools/screenshot.gd (see TASK-006).

const ScreenshotImage := preload("res://tools/screenshot_image.gd")


func test_single_colour_image_is_blank() -> void:
	var image := Image.create_empty(64, 36, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	assert_true(ScreenshotImage.is_blank(image))


func test_image_with_a_differing_sample_is_not_blank() -> void:
	var image := Image.create_empty(64, 36, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.fill_rect(Rect2i(32, 18, 32, 18), Color.WHITE)
	assert_false(ScreenshotImage.is_blank(image))


func test_difference_between_samples_is_ignored() -> void:
	# Only the 16x16 sample grid counts; a single pixel off the grid doesn't matter.
	var image := Image.create_empty(64, 36, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.set_pixel(0, 0, Color.WHITE)
	assert_true(ScreenshotImage.is_blank(image))


func test_empty_image_is_blank() -> void:
	assert_true(ScreenshotImage.is_blank(Image.new()))
