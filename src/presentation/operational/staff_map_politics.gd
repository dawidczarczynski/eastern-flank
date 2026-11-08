class_name StaffMapPolitics
extends RefCounted
## The political tint of the staff map (TASK-114): feeds the terrain shader the country coverage
## raster (StaffMapCountryMask) once and, on every stance or viewer change, the tint of each
## country seen from the viewer (StanceTint.for_viewer). Closed countries are hatched. Only
## reads the state; the P key toggles `set_enabled`.

var _material: ShaderMaterial
var _palette: StaffMapPalette
## Country id per channel of the mask (ImportedMap.countries order), &"" for an unknown code.
var _channel_ids: Array[StringName] = []
var _enabled := true
var _tints := PackedVector4Array([Vector4(), Vector4(), Vector4(), Vector4()])
var _closed := Vector4()


## Null when the terrain is not layered or the map has no countries (nothing to tint).
static func create(
	terrain: StaffMapTerrain, map: ImportedMap, palette: StaffMapPalette
) -> StaffMapPolitics:
	if terrain == null or map == null:
		return null
	var mask := StaffMapCountryMask.build(
		map, terrain.layer_rect, map.layer_image(ImportedMap.LAYER_WATER)
	)
	if mask == null:
		return null
	var politics := StaffMapPolitics.new()
	politics._material = terrain.material
	politics._palette = palette
	for iso in map.countries:
		var definition := CountryDefinition.find_by_iso(iso)
		politics._channel_ids.append(definition.id if definition != null else &"")
	var texture := ImageTexture.create_from_image(mask.image)
	politics._material.set_shader_parameter(&"country_tex", texture)
	return politics


## Tints for `viewer` from `state` (call on stance change and viewer change).
func apply(state: OperationalState, viewer: int) -> void:
	var entries := StanceTint.for_viewer(state, viewer)
	_tints = PackedVector4Array([Vector4(), Vector4(), Vector4(), Vector4()])
	_closed = Vector4()
	for channel in mini(_channel_ids.size(), StaffMapCountryMask.MAX_COUNTRIES):
		var entry: Dictionary = entries.get(_channel_ids[channel], {})
		if entry.is_empty():
			continue
		var colour := StanceTint.colour(_palette, entry)
		_tints[channel] = Vector4(colour.r, colour.g, colour.b, colour.a)
		_closed[channel] = 1.0 if entry["closed"] else 0.0
	_material.set_shader_parameter(&"country_tint", _tints)
	_material.set_shader_parameter(&"country_closed", _closed)
	_material.set_shader_parameter(&"politics_on", 1.0 if _enabled else 0.0)


func set_enabled(value: bool) -> void:
	_enabled = value
	_material.set_shader_parameter(&"politics_on", 1.0 if value else 0.0)


func enabled() -> bool:
	return _enabled


## The tint of mask channel `channel` as last applied (tests).
func tint(channel: int) -> Color:
	var v := _tints[channel]
	return Color(v.x, v.y, v.z, v.w)


func is_closed(channel: int) -> bool:
	return _closed[channel] > 0.5
