class_name VisualScale
extends RefCounted
## Visual scale of units relative to trees, bushes and rocks (TASK-059). One place for the
## constants: UnitModels reads `unit_model_scale`, MapView's scatter reads the others. The active
## preset is `balanced` (the human's choice, 2026-10-22; `current` is the pre-TASK-059 look). It
## is global presentation state: switch it before the
## battle is built (today only tools/screenshot.gd does, from SCREENSHOT_SCALE_PRESET).

const DEFAULT_PRESET := &"balanced"
const PRESETS := {
	&"current": {"unit_model_scale": 1.3, "tree_scale": 1.0, "bush_scale": 1.0, "rock_scale": 1.0},
	&"balanced": {"unit_model_scale": 1.1, "tree_scale": 1.8, "bush_scale": 1.4, "rock_scale": 1.0},
	&"realistic":
	{"unit_model_scale": 0.9, "tree_scale": 2.6, "bush_scale": 1.8, "rock_scale": 1.0},
}

static var _active: Dictionary = PRESETS[DEFAULT_PRESET]


## The values of a preset (a copy); an unknown name warns and returns the default.
static func preset(preset_name: StringName) -> Dictionary:
	if not PRESETS.has(preset_name):
		push_warning("VisualScale: unknown preset '%s', using '%s'" % [preset_name, DEFAULT_PRESET])
		return (PRESETS[DEFAULT_PRESET] as Dictionary).duplicate()
	return (PRESETS[preset_name] as Dictionary).duplicate()


## Makes a preset the active one (unknown name -> the default).
static func apply(preset_name: StringName) -> void:
	_active = preset(preset_name)


## Back to the default preset.
static func reset() -> void:
	apply(DEFAULT_PRESET)


## Overrides single values of the active preset (tests, experiments).
static func apply_values(values: Dictionary) -> void:
	var merged := _active.duplicate()
	merged.merge(values, true)
	_active = merged


static func unit_model_scale() -> float:
	return _active["unit_model_scale"]


static func tree_scale() -> float:
	return _active["tree_scale"]


static func bush_scale() -> float:
	return _active["bush_scale"]


static func rock_scale() -> float:
	return _active["rock_scale"]
