class_name SoundBank
extends Resource
## Sound id -> audio files table and the sound tuning numbers (TASK-123, rule 5), kept in
## data/audio/sound_bank.tres. Pure data: it never loads or plays a stream; the AudioDirector
## (presentation) does.

## id -> { "streams": PackedStringArray (res:// paths, 2-4 variants for one-shots), "pitch": float
## (base pitch scale, e.g. 0.55 to turn a car engine into a diesel), "gain_db": float,
## "loop": bool (the first stream loops) }. Missing keys mean pitch 1, gain 0, no loop.
@export var entries: Dictionary = {}

## Ambient forest loop: the camera must be closer than `ambient_max_distance` (camera distance in
## world units) and at least `ambient_min_forest` of the tiles around its focus must be forest;
## the loop fades in and out over `ambient_fade` seconds.
@export var ambient_max_distance := 14.0
@export var ambient_min_forest := 0.3
@export var ambient_fade := 1.5
## Radius (hexes) of the tile disc around the camera focus that counts as "under the camera".
@export var ambient_radius := 3
## Random bird chirps on top of the loop: pause between two of them (seconds).
@export var bird_interval_min := 5.0
@export var bird_interval_max := 14.0
## Polyphony of one-shot sounds (the oldest one is stolen) and of movement loops.
@export var max_one_shots := 16
@export var max_loops := 8


func has_id(id: StringName) -> bool:
	return entries.has(String(id))


func ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: Variant in entries:
		result.append(StringName(key))
	return result


func streams_of(id: StringName) -> PackedStringArray:
	return _entry(id).get("streams", PackedStringArray())


func pitch_of(id: StringName) -> float:
	return _entry(id).get("pitch", 1.0)


func gain_db_of(id: StringName) -> float:
	return _entry(id).get("gain_db", 0.0)


func is_loop(id: StringName) -> bool:
	return _entry(id).get("loop", false)


func _entry(id: StringName) -> Dictionary:
	return entries.get(String(id), {})
