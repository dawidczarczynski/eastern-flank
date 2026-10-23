extends TestCase


func test_background_is_much_slower_than_focused() -> void:
	assert_true(FramePacing.max_fps(false) > 0)
	assert_true(FramePacing.max_fps(false) < FramePacing.max_fps(true))


func test_focused_is_capped() -> void:
	assert_true(FramePacing.max_fps(true) > 0)


func test_focus_notifications_set_engine_cap() -> void:
	var previous := Engine.max_fps
	FramePacing.apply_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_eq(Engine.max_fps, FramePacing.BACKGROUND_FPS)
	FramePacing.apply_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_eq(Engine.max_fps, FramePacing.FOCUSED_FPS)
	FramePacing.apply_notification(Node.NOTIFICATION_PREDELETE)
	assert_eq(Engine.max_fps, FramePacing.FOCUSED_FPS)
	Engine.max_fps = previous
