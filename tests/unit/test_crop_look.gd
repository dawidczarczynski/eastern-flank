extends TestCase
## The farmland crops of the `true` look (TASK-200): the CropCatalog data, the neighbour-aware crop
## assignment, the satellite tint, row strength by distance, headland and balk, the meadow keeping
## the grass look, and that `balanced` stays as it was.

const Fixtures := preload("res://tests/fixtures.gd")

const CROP_NAMES: Array[StringName] = [
	&"wheat", &"green", &"rape", &"stubble", &"ploughed", &"meadow"
]
## FieldParcels.kind() of the default (balanced) look before TASK-200, at fixed points.
const BALANCED_KINDS: Array[int] = [7, 5, 5, 1, 6, 3, 5, 1, 8, 4, 1, 5]


func after_each() -> void:
	VisualScale.reset()
	LookPreset.reset()
	MapScale.reset()


func _true_look() -> Dictionary:
	VisualScale.apply(VisualScale.TRUE_PRESET)
	return LookPreset.fields()


func _shares() -> Dictionary:
	return FieldParcels.shares_of(_true_look())


func _fields_map() -> ParcelMap:
	var grid := Fixtures.plains_grid(4)
	for c in grid.coords():
		grid.set_terrain(c, Terrain.Type.FIELDS)
	return FieldParcels.bake(grid, 1.0, Rect2(-2.0, -2.0, 4.0, 4.0))


func test_catalog_has_the_six_crop_kinds_with_their_data() -> void:
	var catalog := CropCatalog.load_default()
	assert_eq(catalog.kinds.size(), 6)
	for n in CROP_NAMES:
		var kind := catalog.get_kind(n)
		assert_true(kind != null, "catalog has %s" % n)
		assert_true(kind.weight > 0.0 and kind.colour != kind.harvest_tone)
		assert_true(kind.row_spacing_m >= 0.3 and kind.row_spacing_m <= 0.75, "%s spacing" % n)
	assert_true(catalog.get_kind(&"meadow").ground_look)


func test_assignment_is_deterministic() -> void:
	var shares := _shares()
	assert_eq(FieldParcels.block_crops(3, -2, shares), FieldParcels.block_crops(3, -2, shares))
	for i in 40:
		var x := i * 137.3 - 2000.0
		var z := i * 211.9 + 50.0
		assert_eq(FieldParcels.kind(x, z), FieldParcels.kind(x, z))


func test_neighbouring_parcels_differ_in_crop() -> void:
	var shares := _shares()
	var checked := 0
	for bx in range(-3, 3):
		for bz in range(-3, 3):
			var crops := FieldParcels.block_crops(bx, bz, shares)
			var parcels := FieldParcels.parcels_of_block(bx, bz)
			for a: Dictionary in parcels:
				for b: Dictionary in parcels:
					if a["strip"] * 2 + a["part"] >= b["strip"] * 2 + b["part"]:
						continue
					var ra: Rect2 = a["rect"]
					var rb: Rect2 = b["rect"]
					# Sharing an edge: the rects touch and overlap along the other axis.
					var touch := ra.grow(0.01).intersects(rb) and not ra.grow(-0.01).intersects(rb)
					if not touch:
						continue
					var ca: int = crops[a["strip"]][a["part"]]
					var cb: int = crops[b["strip"]][b["part"]]
					assert_true(ca != cb, "block %d,%d neighbours share crop %d" % [bx, bz, ca])
					checked += 1
	assert_true(checked > 100, "pairs checked: %d" % checked)


func test_region_mix_follows_the_weights() -> void:
	var shares := _shares()
	var areas := {}
	var total := 0.0
	for bx in range(-20, 20):
		for bz in range(-20, 20):
			var crops := FieldParcels.block_crops(bx, bz, shares)
			for p: Dictionary in FieldParcels.parcels_of_block(bx, bz):
				var area: float = (p["rect"] as Rect2).get_area()
				var k: int = crops[p["strip"]][p["part"]]
				areas[k] = areas.get(k, 0.0) + area
				total += area
	for k in FieldParcels.CROP_KINDS:
		var share: float = areas.get(k, 0.0) / total
		var wanted: float = shares.get(FieldParcels.CROPS[k], 0.0)
		assert_true(
			absf(share - wanted) <= 0.10,
			"%s: %.2f vs %.2f" % [FieldParcels.CROPS[k], share, wanted]
		)
	assert_eq(areas.get(FieldParcels.Kind.MAIZE, 0.0), 0.0)


func test_satellite_tint_shifts_the_hue_towards_the_layer() -> void:
	var crop := Color(0.30, 0.34, 0.10)
	var red := Color(0.8, 0.02, 0.02)
	var strength: float = _true_look()["tint"]
	assert_true(strength > 0.0 and strength <= 1.0)
	var tinted := CropLook.tinted(crop, red, strength)
	var base_red := crop.r / (crop.r + crop.g + crop.b)
	var new_red := tinted.r / (tinted.r + tinted.g + tinted.b)
	assert_true(new_red > base_red + 0.05, "red share %.2f -> %.2f" % [base_red, new_red])
	assert_true(absf(SatelliteColour.luma(tinted) - SatelliteColour.luma(crop)) < 0.01)
	var none := CropLook.tinted(crop, red, 0.0)
	assert_true(absf(none.r - crop.r) < 1e-6)


func test_balanced_keeps_the_old_look() -> void:
	for i in 12:
		assert_eq(FieldParcels.kind(i * 913.7 - 3000.0, i * 1371.3 + 211.0), BALANCED_KINDS[i])
	var look := LookPreset.fields()
	assert_false(look.has("distinct_neighbours"))
	assert_eq(look["crops"][&"maize"]["share"], 0.10)
	assert_eq(look["crops"][&"rape"]["share"], 0.0)
	var material := ShaderMaterial.new()
	material.shader = TerrainGround.SHADER
	TerrainGround.set_parcels(material, _fields_map())
	assert_false(material.get_shader_parameter(&"crop_true"))


func test_true_look_is_stronger_and_mottled_at_a_large_scale() -> void:
	var look := _true_look()
	assert_true(look["saturation"] > 1.0 and look["mottle"] > 0.0)
	assert_true(look["mottle_period_m"] >= 20.0)
	var material := ShaderMaterial.new()
	material.shader = TerrainGround.SHADER
	TerrainGround.set_parcels(material, _fields_map())
	assert_true(material.get_shader_parameter(&"crop_true"))
	var frequency: float = material.get_shader_parameter(&"crop_mottle_frequency")
	assert_true(MapScale.metres_per_unit / frequency >= 20.0, "noise period in metres")


func test_row_spacing_is_real_and_the_direction_constant_per_parcel() -> void:
	var look := _true_look()
	for n: StringName in look["crops"]:
		var entry: Dictionary = look["crops"][n]
		if entry["share"] > 0.0:
			assert_true(entry["spacing_m"] >= 0.3 and entry["spacing_m"] <= 0.75, "%s spacing" % n)
	var map := _fields_map()
	# Two sample points of the same parcel (inside the first strip's interior).
	var parcel := FieldParcels.parcel_at(0.0, 0.0)
	var other := FieldParcels.parcel_at(0.0, 0.0)
	assert_eq(parcel["along_x"], other["along_x"])
	var p1 := Vector2(map.origin_m.x + 300.0, map.origin_m.y + 300.0)
	var p2 := p1 + (Vector2(40.0, 0.0) if parcel["along_x"] else Vector2(0.0, 40.0))
	var a := FieldParcels.parcel_at(p1.x, p1.y)
	var b := FieldParcels.parcel_at(p2.x, p2.y)
	if a["key"] == b["key"]:
		assert_eq(a["along_x"], b["along_x"])


func test_rows_fade_out_by_150_m() -> void:
	var look := _true_look()
	assert_eq(CropLook.row_strength(0.0, look), 1.0)
	assert_eq(CropLook.row_strength(50.0, look), 1.0)
	var mid := CropLook.row_strength(100.0, look)
	assert_true(mid > 0.0 and mid < 1.0)
	for d in [150.0, 151.0, 400.0, 5000.0]:
		assert_eq(CropLook.row_strength(d, look), 0.0, "strength at %f m" % d)
	var material := ShaderMaterial.new()
	material.shader = TerrainGround.SHADER
	TerrainGround.set_parcels(material, _fields_map())
	assert_eq(
		material.get_shader_parameter(&"row_distance_m"),
		Vector2(look["row_full_m"], look["row_zero_m"])
	)


func test_headland_is_darker_and_the_balk_lighter_than_the_crops() -> void:
	var look := _true_look()
	assert_true(look["headland_m"] > 0.0)
	assert_true(CropLook.headland_factor(0.0, 10.0, look) < 1.0)
	assert_eq(CropLook.headland_factor(look["headland_m"] + 1.0, 10.0, look), 1.0)
	assert_eq(CropLook.headland_factor(0.0, look["headland_fade_m"] + 1.0, look), 1.0)
	var balk := CropLook.luminance(look["balk"]["plant"])
	for n: StringName in CROP_NAMES:
		var crop: Color = look["crops"][n]["plant"]
		assert_true(balk > CropLook.luminance(crop), "balk lighter than %s" % n)


func test_meadow_keeps_the_grass_ground_look() -> void:
	var grass := Color(0.20, 0.30, 0.08)
	var crop := Color(0.7, 0.5, 0.1)
	var meadow := CropLook.parcel_albedo(&"meadow", grass, crop)
	assert_true(absf(meadow.r - grass.r) <= 0.02 and absf(meadow.g - grass.g) <= 0.02)
	assert_true(absf(meadow.b - grass.b) <= 0.02)
	assert_eq(CropLook.parcel_albedo(&"wheat", grass, crop), crop)
	# The terrain shader is told which kinds keep the ground.
	var material := ShaderMaterial.new()
	material.shader = TerrainGround.SHADER
	_true_look()
	TerrainGround.set_parcels(material, _fields_map())
	var ground: PackedFloat32Array = material.get_shader_parameter(&"crop_ground")
	assert_eq(ground[FieldParcels.Kind.MEADOW], 1.0)
	assert_eq(ground[FieldParcels.Kind.WHEAT], 0.0)
