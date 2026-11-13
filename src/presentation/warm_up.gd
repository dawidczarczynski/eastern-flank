class_name WarmUp
extends RefCounted
## Decides when the first slow frames of a freshly built scene are over (shader pipelines,
## texture uploads), so the loading screen can go. A frame is calm when it is fast, or when its
## time is close to the previous frame's: a scene that simply renders slower than FAST_FRAME_S
## (a big window on a slow GPU) settles as soon as its frame time stops changing, instead of
## waiting for the caller's time limit. The scene has settled after CALM_FRAMES calm frames in a
## row.
## Usage: var warm_up := WarmUp.new(); each frame: warm_up.add_frame(delta); warm_up.is_settled()

const FAST_FRAME_S := 1.0 / 40.0  ## a frame faster than this is calm whatever came before
const STEADY_SHARE := 0.2  ## ...and so is one within this share of the previous frame's time
const CALM_FRAMES := 8

var _calm := 0
var _previous := -1.0


## `delta`: the frame's duration in seconds.
func add_frame(delta: float) -> void:
	var steady := _previous > 0.0 and absf(delta - _previous) <= STEADY_SHARE * _previous
	_calm = _calm + 1 if delta < FAST_FRAME_S or steady else 0
	_previous = delta


func is_settled() -> bool:
	return _calm >= CALM_FRAMES
