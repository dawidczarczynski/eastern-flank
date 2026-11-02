class_name SoundMix
extends RefCounted
## Audio buses and volume settings (TASK-123): Master -> SFX, UI, Ambient. Buses are created in
## code once (AudioServer survives scene changes); `apply` sets them from the stored settings.

const BUSES: Array[StringName] = [&"SFX", &"UI", &"Ambient"]


## True when nothing may be played: muted, or the master volume is zero.
static func is_silent(sound: Dictionary) -> bool:
	return bool(sound.get("muted", false)) or float(sound.get("master", 1.0)) <= 0.001


static func setup_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")


## Master volume / mute on the Master bus, the ambient volume on the Ambient bus.
static func apply(sound: Dictionary) -> void:
	setup_buses()
	var master := AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(master, _db(float(sound.get("master", 1.0))))
	AudioServer.set_bus_mute(master, bool(sound.get("muted", false)))
	var ambient := AudioServer.get_bus_index(&"Ambient")
	AudioServer.set_bus_volume_db(ambient, _db(float(sound.get("ambient", 1.0))))


static func _db(linear: float) -> float:
	return -80.0 if linear <= 0.001 else linear_to_db(linear)
