class_name AudioDirector
extends Node
## Plays the battle sound (TASK-123). Presentation only: BattleController calls it at the same
## playback moments as the animations (it never listens to GameSimulation and never changes
## state); SoundPlanner decides *what* plays, this node only owns the pooled players, the
## movement loops and the forest ambience. One-shots use a fixed pool (the oldest is stolen),
## nothing is allocated per shot. Randomness is the view's own (never GameState.rng).

const BANK_PATH := "res://data/audio/sound_bank.tres"
const UI_POOL := 4
const HOOK_META := &"audio_hooked"
const SLIDER_TICK_MS := 70
## Seconds from the shot to the impact sound (the shell's flight).
const IMPACT_DELAY := 0.15
## Attenuation of in-world sounds, tuned to the camera distance (7-46 world units).
const UNIT_SIZE := 30.0
const MAX_DISTANCE := 160.0
## The camera counts as stopped after this many seconds without a change.
const CAMERA_SETTLE := 0.25
const BIRD_HEIGHT := 1.5
const BIRD_SPREAD := 6.0
const SILENT_DB := -80.0

## {"master", "ambient", "muted"}; loaded from the settings file in _ready when left empty.
var settings: Dictionary = {}

var _bank: SoundBank
var _planner: SoundPlanner
var _camera_rig: CameraRig
var _grid: HexGrid
var _hex_size := 1.0
var _streams: Dictionary = {}  # sound id -> AudioStream (or null when not loadable)
var _shots: Array[AudioStreamPlayer3D] = []
var _shot_serial: PackedInt32Array = PackedInt32Array()
var _serial := 0
var _ui: Array[AudioStreamPlayer] = []
var _ui_next := 0
var _last_slider_tick := 0
var _loops: Array[LoopSlot] = []
var _ambient: AudioStreamPlayer
var _ambient_level := 0.0  # 0..1, follows _ambient_target over `ambient_fade`
var _ambient_target := 0.0
var _bird_timer := 0.0
var _last_target := Vector2(INF, INF)
var _last_distance := -1.0
var _camera_stable := 0.0
var _camera_dirty := true
var _rng := RandomNumberGenerator.new()


## One running (or fading) movement loop of one unit.
class LoopSlot:
	extends RefCounted
	var player: AudioStreamPlayer3D
	var unit_id := -1
	var node: Node3D
	var active := false
	var starting := true
	var age := 0.0
	var base_pitch := 1.0
	var base_db := 0.0


## Builds the director under `parent` with the project's sound bank.
static func create(
	parent: Node, camera_rig: CameraRig, grid: HexGrid, hex_size: float
) -> AudioDirector:
	var director := AudioDirector.new()
	director.setup(load(BANK_PATH) as SoundBank, camera_rig, grid, hex_size)
	parent.add_child(director)
	return director


## Click and hover sounds of a HUD button.
func hook_button(button: BaseButton) -> void:
	if button.has_meta(HOOK_META):
		return
	button.set_meta(HOOK_META, true)
	button.pressed.connect(play_ui.bind(&"press"))
	button.mouse_entered.connect(play_ui.bind(&"hover"))


## Click + hover ticks for every button / toggle and a tick for every slider change under `root`,
## including controls added to it later (menus, dialogs, the unit catalog).
func hook_tree(root: Node) -> void:
	_hook_node(root, root)
	if is_inside_tree() and not get_tree().node_added.is_connected(_hook_node.bind(root)):
		get_tree().node_added.connect(_hook_node.bind(root))


func _hook_node(node: Node, root: Node) -> void:
	if node is BaseButton:
		hook_button(node)
	elif node is Range and not node.has_meta(HOOK_META):
		node.set_meta(HOOK_META, true)
		node.value_changed.connect(_on_slider_changed)
		node.mouse_entered.connect(play_ui.bind(&"hover"))
	if node == root or root.is_ancestor_of(node):
		for child in node.get_children():
			_hook_node(child, root)


func _on_slider_changed(_value: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_slider_tick >= SLIDER_TICK_MS:
		_last_slider_tick = now
		play_ui(&"hover")


## Effects of a rocket salvo: `inner` plus a launch sound per rocket and the impacts.
func salvo_effects(inner: SalvoEffects, shooter: UnitDefinition, damage: int) -> SalvoEffects:
	return AudioSalvoEffects.new(inner, self, shooter, damage)


## A shot of `definition` from `shooter`, and the impact at `target` a moment later (either view
## may be gone).
func play_attack(definition: UnitDefinition, shooter: Node3D, target: Node3D, damage: int) -> void:
	if shooter != null and is_instance_valid(shooter):
		play_fire(definition, shooter.global_position + Vector3.UP * 0.5)
	if target != null and is_instance_valid(target):
		play_impact(damage, false, false, target.global_position, IMPACT_DELAY)


## Engine and running-gear loops of `unit` for the length of the move tween.
func follow_move(move: Tween, unit: Unit, node: Node3D) -> void:
	start_move(unit.id, unit.definition, node)
	move.finished.connect(stop_move.bind(unit.id), CONNECT_ONE_SHOT)


## `camera_rig` and `grid` may be null (no ambient then); `hex_size` converts the camera focus to
## a tile.
func setup(bank: SoundBank, camera_rig: CameraRig, grid: HexGrid, hex_size: float) -> void:
	_bank = bank
	_planner = SoundPlanner.new(bank)
	_camera_rig = camera_rig
	_grid = grid
	_hex_size = hex_size


func _ready() -> void:
	name = "AudioDirector"
	_rng.randomize()
	if settings.is_empty():
		settings = GameSettings.load_sound()
	SoundMix.apply(settings)
	for i in _bank.max_one_shots:
		_shots.append(_new_player(&"SFX"))
		_shot_serial.append(0)
	for i in UI_POOL:
		var ui := AudioStreamPlayer.new()
		ui.bus = &"UI"
		add_child(ui)
		_ui.append(ui)
	for i in _bank.max_loops:
		var slot := LoopSlot.new()
		slot.player = _new_player(&"SFX")
		_loops.append(slot)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = &"Ambient"
	add_child(_ambient)


## Number of one-shots and loops sounding now.
func playing_count() -> int:
	var count := 0
	for player in _shots:
		count += int(player.playing)
	for slot in _loops:
		count += int(slot.active)
	for player in _ui:
		count += int(player.playing)
	return count


## Size of the pooled one-shot players (the polyphony limit).
func one_shot_pool_size() -> int:
	return _shots.size()


## A UI cue (SoundPlanner.ui_sound); false when nothing was started.
func play_ui(action: StringName) -> bool:
	var id := SoundPlanner.ui_sound(action)
	if id == &"" or SoundMix.is_silent(settings) or _ui.is_empty():
		return false
	var stream := _stream_for(id)
	if stream == null:
		return false
	var player := _ui[0]
	for candidate in _ui:  # a free one, else the next in turn
		if not candidate.playing:
			player = candidate
			break
	if player.playing:
		player = _ui[_ui_next]
		_ui_next = (_ui_next + 1) % _ui.size()
	player.stream = stream
	player.volume_db = _bank.gain_db_of(id)
	player.pitch_scale = _bank.pitch_of(id)
	player.play()
	return true


## A one-shot at a world position on `bus`; steals the oldest player when all are busy. False when
## silent (muted / volume 0), the id has no loadable stream or the director is not in the tree.
func play_at(id: StringName, position: Vector3, gain_db := 0.0, bus := &"SFX") -> bool:
	if SoundMix.is_silent(settings) or not is_inside_tree() or _shots.is_empty():
		return false
	var stream := _stream_for(id)
	if stream == null:
		return false
	var index := _free_shot()
	var player := _shots[index]
	player.stream = stream
	player.bus = bus
	player.volume_db = _bank.gain_db_of(id) + gain_db
	player.pitch_scale = _bank.pitch_of(id)
	player.global_position = position
	_serial += 1
	_shot_serial[index] = _serial
	var clip := _bank.clip_of(id)
	if clip <= 0.0:
		player.play()
		return true
	var length := _source_length(stream)
	player.play(randf() * maxf(length - clip, 0.0))
	var serial := _serial
	get_tree().create_timer(clip).timeout.connect(
		func() -> void:
			if _shot_serial[index] == serial:
				player.stop(),
		CONNECT_ONE_SHOT
	)
	return true


## `play_at` after `delay` seconds.
func play_at_later(id: StringName, position: Vector3, delay: float, gain_db := 0.0) -> void:
	if delay <= 0.0 or not is_inside_tree():
		play_at(id, position, gain_db)
		return
	get_tree().create_timer(delay).timeout.connect(
		func() -> void: play_at(id, position, gain_db), CONNECT_ONE_SHOT
	)


## The shot of `definition` at `position`.
func play_fire(definition: UnitDefinition, position: Vector3, gain_db := 0.0, delay := 0.0) -> void:
	play_at_later(SoundPlanner.fire_sound(definition), position, delay, gain_db)


## The impact at `position` (SoundPlanner.impact_sound), `delay` seconds from now (shell flight).
func play_impact(damage: int, died: bool, indirect: bool, position: Vector3, delay := 0.0) -> void:
	var id := SoundPlanner.impact_sound(damage, died, indirect)
	if id == &"":
		return
	var gain := SoundPlanner.impact_gain_db(damage, indirect)
	if delay <= 0.0 or not is_inside_tree():
		play_at(id, position, gain)
		return
	get_tree().create_timer(delay).timeout.connect(
		func() -> void: play_at(id, position, gain), CONNECT_ONE_SHOT
	)


## Starts the engine / running-gear loops of a moving unit; they follow `node` and ramp up.
func start_move(unit_id: int, definition: UnitDefinition, node: Node3D) -> void:
	stop_move(unit_id, true)
	if SoundMix.is_silent(settings) or not is_inside_tree():
		return
	for id in SoundPlanner.move_loops(definition):
		var stream := _stream_for(id)
		var slot := _free_loop()
		if stream == null or slot == null:
			continue
		slot.unit_id = unit_id
		slot.node = node
		slot.active = true
		slot.starting = true
		slot.age = 0.0
		slot.base_pitch = _bank.pitch_of(id)
		slot.base_db = _bank.gain_db_of(id)
		slot.player.stream = stream
		slot.player.global_position = node.global_position
		slot.player.pitch_scale = slot.base_pitch * SoundPlanner.START_PITCH
		slot.player.volume_db = SILENT_DB
		slot.player.play()


## The unit stopped: its loops fall in pitch and fade out; `immediately` cuts them.
func stop_move(unit_id: int, immediately := false) -> void:
	for slot in _loops:
		if not slot.active or slot.unit_id != unit_id:
			continue
		if immediately:
			slot.player.stop()
			slot.active = false
		elif slot.starting:
			slot.starting = false
			slot.age = 0.0


func _process(delta: float) -> void:
	if _loops.is_empty():
		return  # not built (outside the tree)
	for slot in _loops:
		if slot.active:
			_update_loop(slot, delta)
	_poll_camera(delta)
	_update_ambient(delta)


func _update_loop(slot: LoopSlot, delta: float) -> void:
	slot.age += delta
	var envelope := SoundPlanner.loop_envelope(slot.starting, slot.age)
	if not slot.starting and envelope.y <= 0.0:
		slot.player.stop()
		slot.active = false
		return
	slot.player.pitch_scale = maxf(slot.base_pitch * envelope.x, 0.01)
	slot.player.volume_db = slot.base_db + _db(envelope.y)
	if is_instance_valid(slot.node):
		slot.player.global_position = slot.node.global_position


## Recomputes the ambient target once the camera has stopped (not every frame).
func _poll_camera(delta: float) -> void:
	if _camera_rig == null:
		return
	var focus := _camera_rig.target()
	var distance := _camera_rig.distance()
	if focus != _last_target or not is_equal_approx(distance, _last_distance):
		_last_target = focus
		_last_distance = distance
		_camera_stable = 0.0
		_camera_dirty = true
		return
	if not _camera_dirty:
		return
	_camera_stable += delta
	if _camera_stable < CAMERA_SETTLE:
		return
	_camera_dirty = false
	var fraction := 0.0
	if _grid != null:
		var tile := Hex.from_world(Vector3(focus.x, 0.0, focus.y), _hex_size)
		fraction = SoundPlanner.forest_fraction(_grid, tile, _bank.ambient_radius)
	_ambient_target = _planner.ambient_for(distance, fraction)["volume"]


func _update_ambient(delta: float) -> void:
	var target := 0.0 if SoundMix.is_silent(settings) else _ambient_target
	_ambient_level = move_toward(_ambient_level, target, delta / maxf(_bank.ambient_fade, 0.01))
	if _ambient_level <= 0.001:
		if _ambient.playing:
			_ambient.stop()
		return
	if not _ambient.playing:
		var stream := _stream_for(SoundPlanner.AMBIENT_LOOP)
		if stream == null:
			return
		_ambient.stream = stream
		_ambient.play()
	_ambient.volume_db = _bank.gain_db_of(SoundPlanner.AMBIENT_LOOP) + _db(_ambient_level)
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = _rng.randf_range(_bank.bird_interval_min, _bank.bird_interval_max)
		if _ambient_level > 0.5 and _camera_rig != null:
			var focus := _camera_rig.target()
			var at := Vector3(
				focus.x + _rng.randf_range(-BIRD_SPREAD, BIRD_SPREAD),
				BIRD_HEIGHT,
				focus.y + _rng.randf_range(-BIRD_SPREAD, BIRD_SPREAD)
			)
			play_at(SoundPlanner.AMBIENT_BIRDS, at, 0.0, &"Ambient")


func _new_player(bus: StringName) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.bus = bus
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player)
	return player


## Index of a idle one-shot player, else of the one started longest ago.
func _free_shot() -> int:
	var oldest := 0
	for i in _shots.size():
		if not _shots[i].playing:
			return i
		if _shot_serial[i] < _shot_serial[oldest]:
			oldest = i
	return oldest


func _free_loop() -> LoopSlot:
	for slot in _loops:
		if not slot.active:
			return slot
	return null


## The stream of a sound id, built once: a randomizer over the variants (pitch +-5 %, volume
## +-1 dB) for one-shots, the first file with looping switched on for loops. Null when the files
## cannot be loaded.
func _stream_for(id: StringName) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var loaded: Array[AudioStream] = []
	for path in _bank.streams_of(id):
		var stream := load(path) as AudioStream
		if stream != null:
			loaded.append(stream)
	var result: AudioStream = null
	if not loaded.is_empty():
		if _bank.is_loop(id):
			result = loaded[0]
			_enable_loop(result)
		else:
			var randomizer := AudioStreamRandomizer.new()
			randomizer.random_pitch = 1.05
			randomizer.random_volume_offset_db = 1.0
			for stream in loaded:
				randomizer.add_stream(-1, stream)
			result = randomizer
	_streams[id] = result
	return result


static func _source_length(stream: AudioStream) -> float:
	if stream is AudioStreamRandomizer and (stream as AudioStreamRandomizer).streams_count > 0:
		return (stream as AudioStreamRandomizer).get_stream(0).get_length()
	return stream.get_length()


static func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		var bytes := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
		if wav.stereo:
			bytes *= 2
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / bytes


static func _db(linear: float) -> float:
	return SILENT_DB if linear <= 0.001 else linear_to_db(linear)
