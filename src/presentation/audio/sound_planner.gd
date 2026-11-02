class_name SoundPlanner
extends RefCounted
## Pure rules of the battle sound (TASK-123): which sound id plays for which UI action, shot,
## impact, moving unit and camera state. Knows no player and no node; the AudioDirector plays what
## it decides. Ids are keys of data/audio/sound_bank.tres.

const RAMP_TIME := 0.4  ## engine pitch / volume ramp at the start and the end of a move (s)
const START_PITCH := 0.94  ## pitch factor at the very start of a move (1 once running)
const STOP_PITCH := 0.9  ## pitch factor when the stop ramp is over
const MISS_GAIN_DB := -7.0  ## a salvo rocket that hurt nobody lands quieter
const UI_SOUNDS := {
	&"press": &"ui_click",
	&"hover": &"ui_hover",
	&"select_unit": &"ui_select",
	&"move_order": &"ui_move",
	&"attack_order": &"ui_attack",
	&"rejected": &"ui_error",
	&"toggle": &"ui_toggle",
}
const EXPLOSION_SMALL := &"explosion_small"
const EXPLOSION_LARGE := &"explosion_large"
const EXPLOSION_ROCKET := &"explosion_rocket"  ## short excerpt: every rocket of a salvo sounds
const AMBIENT_LOOP := &"forest_ambience"
const AMBIENT_BIRDS := &"forest_birds"

var _bank: SoundBank


func _init(bank: SoundBank = null) -> void:
	_bank = bank


## Sound id of a UI action (`press`, `hover`, `select_unit`, ...), &"" for an unknown one.
static func ui_sound(action: StringName) -> StringName:
	return UI_SOUNDS.get(action, &"")


## The shot of a unit: its definition's `fire_sound`.
static func fire_sound(definition: UnitDefinition) -> StringName:
	return definition.fire_sound


## Impact at the target: a death is large, a hit small, a complete miss of direct fire silent;
## `indirect` (rockets, shells) still lands with a (quieter) small explosion.
static func impact_sound(damage: int, died: bool, indirect: bool) -> StringName:
	if died:
		return EXPLOSION_LARGE
	if damage > 0 or indirect:
		return EXPLOSION_SMALL
	return &""


static func impact_gain_db(damage: int, _indirect: bool) -> float:
	return 0.0 if damage > 0 else MISS_GAIN_DB


## Loop ids a moving unit plays: the engine, then the running gear (`engine_<engine_sound>`,
## `move_<move_sound>`); `none` and `footsteps` (no recording) add nothing.
static func move_loops(definition: UnitDefinition) -> Array[StringName]:
	var result: Array[StringName] = []
	if definition.engine_sound != &"none":
		result.append(StringName("engine_" + definition.engine_sound))
	if definition.move_sound in [&"tracks", &"wheels"]:
		result.append(StringName("move_" + definition.move_sound))
	return result


## (pitch factor, volume factor 0..1) of a movement loop `age` seconds after it started (`starting`)
## or stopped. The start rises slightly in pitch, the stop falls and fades out.
static func loop_envelope(starting: bool, age: float) -> Vector2:
	var k := clampf(age / RAMP_TIME, 0.0, 1.0)
	if starting:
		return Vector2(lerpf(START_PITCH, 1.0, k), k)
	return Vector2(lerpf(1.0, STOP_PITCH, k), 1.0 - k)


## Every id the planner can return, so the bank test can check them all.
static func all_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in UI_SOUNDS.values():
		result.append(id)
	(
		result
		. append_array(
			[
				EXPLOSION_SMALL,
				EXPLOSION_LARGE,
				EXPLOSION_ROCKET,
				AMBIENT_LOOP,
				AMBIENT_BIRDS,
				&"engine_diesel_heavy",
				&"engine_diesel_light",
				&"move_tracks",
				&"move_wheels",
			]
		)
	)
	return result


## The forest loop for the camera: {"id", "volume"}; volume is 0 when the camera is too far away
## or too little forest is under it (both limits are data in the bank).
func ambient_for(camera_distance: float, forest_fraction: float) -> Dictionary:
	var close := camera_distance < _bank.ambient_max_distance
	var forest := forest_fraction >= _bank.ambient_min_forest
	return {"id": AMBIENT_LOOP, "volume": 1.0 if close and forest else 0.0}


## Share of the existing tiles within `radius` hexes of `center` that are forest (0 off the map).
static func forest_fraction(grid: HexGrid, center: Vector2i, radius: int) -> float:
	var total := 0
	var forest := 0
	for q in range(-radius, radius + 1):
		for r in range(-radius, radius + 1):
			var offset := Vector2i(q, r)
			if Hex.distance(Vector2i.ZERO, offset) > radius:
				continue
			var c := center + offset
			if not grid.has_tile(c):
				continue
			total += 1
			if grid.get_terrain(c) == Terrain.Type.FOREST:
				forest += 1
	return 0.0 if total == 0 else float(forest) / float(total)
