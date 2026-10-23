class_name FramePacing
extends RefCounted
## Frame-rate caps (TASK-073). A turn-based game must not burn the GPU/CPU: the focused window is
## capped even where vsync is ignored (WSLg, some drivers), an unfocused or minimised one drops to a
## trickle so a game left running in the background stays quiet.

const FOCUSED_FPS := 60
const BACKGROUND_FPS := 5


## Engine.max_fps for the current window state.
static func max_fps(focused: bool) -> int:
	return FOCUSED_FPS if focused else BACKGROUND_FPS


## Applies the cap for a window focus notification, ignores any other notification.
static func apply_notification(what: int) -> void:
	match what:
		Node.NOTIFICATION_APPLICATION_FOCUS_IN, Node.NOTIFICATION_WM_WINDOW_FOCUS_IN:
			Engine.max_fps = max_fps(true)
		Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			Engine.max_fps = max_fps(false)
