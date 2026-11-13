extends TestCase


func _feed(warm_up: WarmUp, frames: Array[float]) -> void:
	for delta in frames:
		warm_up.add_frame(delta)


func test_not_settled_before_any_frame() -> void:
	assert_false(WarmUp.new().is_settled())


func test_fast_frames_settle_after_the_calm_run() -> void:
	var warm_up := WarmUp.new()
	for i in WarmUp.CALM_FRAMES - 1:
		warm_up.add_frame(0.016)
	assert_false(warm_up.is_settled())
	warm_up.add_frame(0.016)
	assert_true(warm_up.is_settled())


## A scene that renders slower than the absolute threshold (27 ms at 1080p on the target GPU)
## still settles once its frame time stops changing, instead of waiting for the time limit.
func test_steady_slow_frames_settle() -> void:
	var warm_up := WarmUp.new()
	var frames: Array[float] = []
	for i in WarmUp.CALM_FRAMES + 1:
		frames.append(0.027 + 0.0005 * (i % 2))
	_feed(warm_up, frames)
	assert_true(warm_up.is_settled())


func test_frames_still_getting_faster_do_not_settle() -> void:
	var warm_up := WarmUp.new()
	var delta := 0.9
	for i in WarmUp.CALM_FRAMES + 2:
		warm_up.add_frame(delta)
		delta *= 0.7
	assert_false(warm_up.is_settled())


func test_a_hitch_restarts_the_calm_run() -> void:
	var warm_up := WarmUp.new()
	for i in WarmUp.CALM_FRAMES - 1:
		warm_up.add_frame(0.027)
	warm_up.add_frame(0.120)  # a shader pipeline compiles
	warm_up.add_frame(0.027)
	assert_false(warm_up.is_settled())
	for i in WarmUp.CALM_FRAMES:
		warm_up.add_frame(0.027)
	assert_true(warm_up.is_settled())
