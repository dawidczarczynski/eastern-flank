extends TestCase
## Sound settings (TASK-123): persisted like the language, volume 0 / mute starts no player.

const TEMP := "user://test_sound_settings.cfg"
const BANK_PATH := "res://data/audio/sound_bank.tres"


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


func test_defaults_without_a_file() -> void:
	var sound := GameSettings.load_sound(TEMP)
	assert_eq(sound["master"], GameSettings.DEFAULT_MASTER)
	assert_eq(sound["ambient"], GameSettings.DEFAULT_AMBIENT)
	assert_false(sound["muted"])


func test_sound_round_trips_and_keeps_the_locale() -> void:
	GameSettings.save_locale("pl", TEMP)
	assert_true(GameSettings.save_sound({"master": 0.25, "ambient": 0.5, "muted": true}, TEMP))
	var sound := GameSettings.load_sound(TEMP)
	assert_eq(sound["master"], 0.25)
	assert_eq(sound["ambient"], 0.5)
	assert_true(sound["muted"])
	assert_eq(GameSettings.load_locale(TEMP), "pl")


func test_values_are_clamped() -> void:
	GameSettings.save_sound({"master": 7.0, "ambient": -1.0, "muted": false}, TEMP)
	var sound := GameSettings.load_sound(TEMP)
	assert_eq(sound["master"], 1.0)
	assert_eq(sound["ambient"], 0.0)


func test_silent_when_muted_or_master_is_zero() -> void:
	assert_false(SoundMix.is_silent({"master": 0.5, "ambient": 1.0, "muted": false}))
	assert_true(SoundMix.is_silent({"master": 0.5, "ambient": 1.0, "muted": true}))
	assert_true(SoundMix.is_silent({"master": 0.0, "ambient": 1.0, "muted": false}))


func test_buses_are_created_once() -> void:
	SoundMix.setup_buses()
	var count := AudioServer.bus_count
	SoundMix.setup_buses()
	assert_eq(AudioServer.bus_count, count)
	for bus: StringName in [&"SFX", &"UI", &"Ambient"]:
		assert_true(AudioServer.get_bus_index(bus) >= 0, str(bus))


func _director(sound: Dictionary) -> AudioDirector:
	var director := AudioDirector.new()
	director.setup(load(BANK_PATH) as SoundBank, null, null, 1.0)
	director.settings = sound
	director._ready()  # builds the player pools; not in a tree, so nothing can sound
	return director


func test_director_starts_no_player_when_silent() -> void:
	for sound: Dictionary in [
		{"master": 0.0, "ambient": 1.0, "muted": false},
		{"master": 0.8, "ambient": 1.0, "muted": true},
	]:
		var director := _director(sound)
		assert_false(director.play_at(&"tank_cannon", Vector3.ZERO))
		assert_false(director.play_ui(&"press"))
		var node := Node3D.new()
		director.start_move(1, load("res://data/units/t72b3.tres") as UnitDefinition, node)
		node.free()
		assert_eq(director.playing_count(), 0)
		director.free()


func test_player_pools_follow_the_bank() -> void:
	var director := _director({"master": 0.8, "ambient": 1.0, "muted": false})
	var bank := load(BANK_PATH) as SoundBank
	assert_eq(director.one_shot_pool_size(), bank.max_one_shots)
	director.free()


func test_hook_tree_hooks_buttons_and_sliders_once() -> void:
	var director := _director({"master": 0.8, "ambient": 1.0, "muted": false})
	var root := Control.new()
	var button := Button.new()
	var slider := HSlider.new()
	root.add_child(button)
	root.add_child(slider)
	director.hook_tree(root)
	director.hook_tree(root)
	assert_eq(button.pressed.get_connections().size(), 1)
	assert_eq(slider.value_changed.get_connections().size(), 1)
	root.free()
	director.free()
