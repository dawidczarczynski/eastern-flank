class_name SalvoEffects
extends RefCounted
## Effect hooks of a rocket salvo (TASK-074): RocketVolley calls them from update(t) at the
## moments listed below. The base class does nothing; TASK-075 fills them (backblast, plume, trail,
## fireball, smoke) with a pooled implementation on HIGH. Purely visual.


## Once at the start of the salvo phase, after aiming, before any other hook. `context` keys:
## `volley` (the RocketVolley node; per-volley effect nodes are parented to it and freed with it),
## `shooter` (UnitView, may be null), `target_centre` (Vector3), `launcher_terrain` and
## `target_terrain` (StringName, e.g. &"plains"), `count` (int), `interval` and `flight` (float).
func begin(_context: Dictionary) -> void:
	pass


## Rocket `index` leaves its tube at `mouth` (world) along `tube_dir` (normalised).
func on_launch(_index: int, _mouth: Vector3, _tube_dir: Vector3) -> void:
	pass


## Rocket `index` flew from `from` to `to` (world) since the previous update; consecutive segments
## of one rocket are contiguous, the first starts at its mouth, the last ends at its landing point.
## `s` = flight-time fraction 0..1 at `to`, `motor` = s < SalvoTiming.MOTOR_BURN.
func on_flight(_index: int, _from: Vector3, _to: Vector3, _s: float, _motor: bool) -> void:
	pass


## Rocket `index` landed at `point`; `first` / `last` mark the salvo's first and last impact.
func on_impact(_index: int, _point: Vector3, _first: bool, _last: bool) -> void:
	pass


## Once when the volley node leaves the tree (end of the event). Lingering effects after this are
## the implementation's business.
func end(_target_centre: Vector3) -> void:
	pass
