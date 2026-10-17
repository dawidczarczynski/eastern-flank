class_name TerrainField
extends RefCounted
## Continuous height and moisture of the landscape at any world point (XZ plane).
## Formulas follow the visual design's `terr` (docs/design/game_screen.scene.js) without
## the coast mask and rivers; water comes from a separate "lake" noise instead.
## The map seed enters only as a world-space `offset`; the noise itself is fixed.

## Hex size (centre to corner) the terrain is generated with; matches MapView.
const HEX_SIZE := 1.0

var settings: TerrainGenerationSettings
var offset: Vector2


func _init(p_settings: TerrainGenerationSettings, p_offset: Vector2) -> void:
	settings = p_settings
	offset = p_offset


func height(x: float, z: float) -> float:
	var s := settings
	var px := x + offset.x
	var pz := z + offset.y
	var hf := s.hills_frequency
	var hills := (
		maxf(0.0, TerrainNoise.fbm(px * hf + 11.0, pz * hf - 4.0, 5.0) - 0.5) * s.hills_gain
	)
	var mmf := s.mountain_mask_frequency
	var mask := TerrainNoise.smooth(
		s.mountain_mask_from, s.mountain_mask_to, TerrainNoise.fbm(px * mmf, pz * mmf, 9.0)
	)
	var mf := s.mountain_frequency
	var mount := mask * (0.35 + TerrainNoise.ridged(px * mf, pz * mf, 21.0)) * s.mountain_gain
	var lf := s.lake_frequency
	var lake := (
		TerrainNoise.smooth(s.lake_from, s.lake_to, TerrainNoise.fbm(px * lf + 40.0, pz * lf, 3.0))
		* s.lake_depth
	)
	var df := s.detail_frequency
	var detail := (TerrainNoise.fbm(px * df, pz * df, 33.0, 3) - 0.5) * s.detail_amplitude
	return s.base_height + hills * s.hills_weight + mount + detail - lake


func moisture(x: float, z: float) -> float:
	var f := settings.moisture_frequency
	return TerrainNoise.fbm((x + offset.x) * f + 50.0, (z + offset.y) * f + 20.0, 77.0)
