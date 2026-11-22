class_name TreeImpostors
extends RefCounted
## Impostors of real-scale trees and scrub (TASK-135, ADR 0026): one camera-facing quad per tree
## (2 triangles instead of 230-340) showing a **baked picture of the real tree model**. Every
## species x variant (TreeMeshes.lod0 with its own material) is rendered once, at start, from
## VIEWS directions around it into one atlas; assets/shaders/tree_impostor.gdshader picks the two
## views nearest to the camera's direction (relative to the tree's own random yaw) and blends
## them, so the impostor looks like the full tree it replaces – same leaf texture, same colours.
## One MultiMesh holds every species (the atlas row travels per instance), so a chunk costs one
## draw.
##
## Lit by the scene (TASK-191): the bake renders every view twice with the unlit bake shader
## (assets/shaders/foliage_bake.gdshader) – the unlit albedo (atlas()) and the view-space normal of
## the cards (normal_atlas(), same layout) – and the impostor shader turns the baked normal to
## the view, so the scene's sun and ambient light the impostors as they light the full trees.
##
## Where nothing can be rendered (headless tests, the dummy renderer) the atlas is a flat
## silhouette per cell; the data paths are the same.
##
## Per instance: TRANSFORM_3D = base position and scale (x: quad width, y: tree height, world
## units; see quad_width()), COLOR = tint relative to the baked species colour (rgb ~ 1),
## CUSTOM = (r: centre of the full-tree range – the impostor starts there, 0 = always; g: centre
## of the impostor range – it ends there; b: atlas row; a: the tree's hand-over phase, the same as
## its full tree's INSTANCE_CUSTOM.a). Ranges are camera distances (world units); the band around
## each is VegetationRanges.band.

const SHADER := preload("res://assets/shaders/tree_impostor.gdshader")
## The unlit bake pass of the LOD0 card shader (albedo or encoded view-space normal).
const BAKE_SHADER := preload("res://assets/shaders/foliage_bake.gdshader")
## The GPU-placed dense forest (TASK-189, ForestField): same picture, trees from their cells.
const FOREST_SHADER := preload("res://assets/shaders/forest_impostor.gdshader")
## Floats per instance: TRANSFORM_3D (12), colour (4), custom (4).
const STRIDE := 20
## Species with an atlas row per variant, in row order.
const SPECIES: Array[StringName] = [
	&"pine", &"spruce", &"birch", &"oak", &"alder", &"shrub", &"undergrowth"
]
## Views around the tree (the atlas columns).
const VIEWS := 16
## Views rendered per draw (D3D12 runs out of descriptors with all at once).
const BAKE_BATCH := 8
## Atlas cell in pixels (a tree is rendered at twice this and scaled down).
const CELL := Vector2i(96, 128)
const SUPERSAMPLE := 2
## The picture covers this multiple of the tree height (vertical) from this much below its base
## to this much above its top, and CELL.x / CELL.y of that wide.
const VERTICAL_SPAN := 1.25
const BELOW_BASE := 0.12
## Share of the picture's width a tree may fill (wider models are squashed and stretched back by
## quad_width()).
const FILL_WIDTH := 0.85
## Camera elevation of the pictures (degrees): a little from above, as the game camera looks.
const ELEVATION := 15.0
## Encoded normal of the flat silhouette cells (no renderer): towards the camera, a little up.
const FLAT_NORMAL := Color(0.5, 0.75, 0.93, 1.0)

static var _atlas: ImageTexture
static var _normal_atlas: ImageTexture
static var _atlas_key := ""
## Species -> linear leaf colour of the active look (what the per-tree tint is relative to).
static var _leaf: Dictionary = {}
## Species -> Vector3(hue, saturation, value) of `_leaf` (tint() runs per tree).
static var _leaf_hsv: Dictionary = {}
## Species -> mean sRGB colour of its unlit baked albedo (the canopy shell paints it too).
static var _mean: Dictionary = {}
## Species -> per variant [atlas row, quad width per unit of crown width].
static var _rows: Dictionary = {}
static var _mesh: ArrayMesh


## Bakes the atlas for the active look if it is not (main thread; the planners read the caches it
## fills).
static func prime() -> void:
	var key := ""
	for species in SPECIES:
		key += str(LookPreset.leaf_color(species, TreeField.LEAF_COLORS[species]))
	if _atlas != null and _atlas_key == key:
		return
	_atlas_key = key
	_leaf.clear()
	_leaf_hsv.clear()
	_mean.clear()
	_rows.clear()
	for species in SPECIES:
		TreeField.leaf_texture(TreeSpecies.is_conifer(species))
		_leaf[species] = LookPreset.leaf_color(species, TreeField.LEAF_COLORS[species])
		_leaf[species] = (_leaf[species] as Color).srgb_to_linear()
		var leaf: Color = _leaf[species]
		_leaf_hsv[species] = Vector3(leaf.h, leaf.s, leaf.v)
	var row_count := SPECIES.size() * TreeMeshes.VARIANTS
	var albedo_images := _bake_images(false)
	var normal_images: Array[Image] = []
	if albedo_images.size() == row_count * VIEWS:
		normal_images = _bake_images(true)
	var baked := normal_images.size() == row_count * VIEWS
	var size := Vector2i(CELL.x * VIEWS, CELL.y * row_count)
	var atlas := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var normals := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for r in row_count:
		var species: StringName = SPECIES[r / TreeMeshes.VARIANTS]
		var variant := r % TreeMeshes.VARIANTS
		var model := TreeField.model_size(species, variant)
		(_rows.get_or_add(species, []) as Array).append([r, _width_factor(model)])
		var flat: Image = null if baked else _flat_cell(species)
		var flat_normal: Image = null if baked else _flat_normal_cell(flat)
		for v in VIEWS:
			var at := Vector2i(v * CELL.x, r * CELL.y)
			var cell: Image = albedo_images[r * VIEWS + v] if baked else flat
			var normal: Image = normal_images[r * VIEWS + v] if baked else flat_normal
			atlas.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL), at)
			normals.blit_rect(normal, Rect2i(Vector2i.ZERO, CELL), at)
	for species in SPECIES:
		_mean[species] = _mean_color(atlas, SPECIES.find(species) * TreeMeshes.VARIANTS)
	atlas.generate_mipmaps()
	normals.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(atlas)
	_normal_atlas = ImageTexture.create_from_image(normals)


## The baked cells of one pass (`normal`: the encoded view-space normals, else the unlit albedo),
## row-major (species, variant) x view, or [] when nothing could be rendered.
static func _bake_images(normal: bool) -> Array[Image]:
	var result: Array[Image] = []
	var loop := Engine.get_main_loop()
	if not loop is SceneTree or DisplayServer.get_name() == "headless":
		return result
	# The foliage shaders read the wind globals (MapView sets them later): register them, still.
	Wind.setup(false)
	var root := (loop as SceneTree).root
	var holder := Node.new()
	holder.name = "TreeImpostorBake"
	root.add_child(holder)
	for species in SPECIES:
		for variant in TreeMeshes.VARIANTS:
			for first in range(0, VIEWS, BAKE_BATCH):
				if not _bake_batch(holder, species, variant, first, normal, result):
					root.remove_child(holder)
					holder.free()
					return []
	root.remove_child(holder)
	holder.free()
	return result


## Renders the views first .. first + BAKE_BATCH - 1 of a model (one draw) and appends their cells;
## false when the renderer gives nothing back.
static func _bake_batch(
	holder: Node, species: StringName, variant: int, first: int, normal: bool, result: Array[Image]
) -> bool:
	var viewports: Array[SubViewport] = []
	for view in range(first, first + BAKE_BATCH):
		var viewport := _bake_viewport(species, variant, view, normal)
		holder.add_child(viewport)
		_push_poses(viewport)
		viewports.append(viewport)
	RenderingServer.force_draw(false)
	var ok := true
	for viewport in viewports:
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			ok = false
		else:
			image.convert(Image.FORMAT_RGBA8)
			image.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
			result.append(image)
		holder.remove_child(viewport)
		viewport.free()
	return ok


## Sends the poses of a bake viewport's camera and tree to the renderer.
static func _push_poses(viewport: SubViewport) -> void:
	var poses: Array = viewport.get_meta(&"poses")
	var camera: Camera3D = poses[0]
	var tree: MultiMeshInstance3D = poses[1]
	RenderingServer.camera_set_transform(camera.get_camera_rid(), camera.global_transform)
	RenderingServer.instance_set_transform(tree.get_instance(), tree.global_transform)


static func _bake_viewport(
	species: StringName, variant: int, view: int, normal: bool
) -> SubViewport:
	var model := TreeField.model_size(species, variant)
	var height := model.y
	var viewport := SubViewport.new()
	viewport.size = CELL * SUPERSAMPLE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Unlit, linear tone mapping at exposure 1: the target holds linear_to_srgb(ALBEDO).
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var material := bake_material(species, normal)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = TreeMeshes.lod0(species, variant)
	multi.instance_count = 1
	multi.buffer = TreeField.instance_buffer([Transform3D.IDENTITY], [Color(0.0, 1.0, 1.0, 0.5)])
	var tree := MultiMeshInstance3D.new()
	tree.multimesh = multi
	tree.material_override = material
	var squash := _squash(model)
	tree.basis = (
		Basis(Vector3.UP, TAU * view / VIEWS) * Basis.from_scale(Vector3(squash, 1.0, squash))
	)
	viewport.add_child(tree)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	# The camera looks down by ELEVATION, so a vertical metre spans cos(ELEVATION) of the picture;
	# the quad maps the picture to world height 1:1, so the span shrinks by that to keep the
	# impostor as tall as the full tree.
	camera.size = VERTICAL_SPAN * height * cos(deg_to_rad(ELEVATION))
	camera.near = 0.01
	camera.far = 20.0
	viewport.add_child(camera)
	var elevation := deg_to_rad(ELEVATION)
	var centre := Vector3(0.0, (VERTICAL_SPAN * 0.5 - BELOW_BASE) * height, 0.0)
	var eye := centre + Vector3(0.0, sin(elevation), cos(elevation)) * 5.0
	camera.transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)
	# Node3D transforms reach the renderer only on the next frame; the bake draws at once.
	viewport.set_meta(&"poses", [camera, tree])
	return viewport


## The LOD0 material of a species on the unlit bake shader (`normal`: the normal pass), all
## distances drawn.
static func bake_material(species: StringName, normal: bool) -> ShaderMaterial:
	var source := TreeField.new_material(species, TreeField.Lod.NEAR)
	var material := ShaderMaterial.new()
	material.shader = BAKE_SHADER
	for info in source.shader.get_shader_uniform_list():
		var parameter: StringName = info["name"]
		material.set_shader_parameter(parameter, source.get_shader_parameter(parameter))
	material.set_shader_parameter(&"lod_in", TreeField.NO_LOD_IN)
	material.set_shader_parameter(&"lod_out", TreeField.NO_LOD_OUT)
	material.set_shader_parameter(&"bake_normal", normal)
	return material


## World width of the baked picture in model units.
static func _picture_width(model: Vector3) -> float:
	return VERTICAL_SPAN * model.y * float(CELL.x) / float(CELL.y)


## Horizontal squash of a model in its picture (wide crowns are squeezed to fit).
static func _squash(model: Vector3) -> float:
	return minf(1.0, FILL_WIDTH * _picture_width(model) / maxf(maxf(model.x, model.z), 1.0e-6))


## Quad width per unit of tree crown width: the picture's width over the squashed model's.
static func _width_factor(model: Vector3) -> float:
	return _picture_width(model) / (maxf(maxf(model.x, model.z), 1.0e-6) * _squash(model))


## A flat silhouette cell (no renderer): a crown block on a trunk in the species colour.
static func _flat_cell(species: StringName) -> Image:
	var image := Image.create(CELL.x, CELL.y, false, Image.FORMAT_RGBA8)
	var color := (_leaf[species] as Color).linear_to_srgb() * 1.4
	color.a = 1.0
	var conifer := TreeSpecies.is_conifer(species)
	var top := int(CELL.y * 0.1)
	var bottom := int(CELL.y * (0.82 if conifer else 0.6))
	var half := int(CELL.x * (0.2 if conifer else 0.3))
	image.fill_rect(Rect2i(CELL.x / 2 - half, top, half * 2, bottom - top), color)
	image.fill_rect(
		Rect2i(CELL.x / 2 - 2, bottom, 4, int(CELL.y * 0.9) - bottom), Color(0.3, 0.24, 0.17, 1.0)
	)
	return image


## The flat normal cells: FLAT_NORMAL where `albedo` (a flat cell) is opaque.
static func _flat_normal_cell(albedo: Image) -> Image:
	var image := Image.create(CELL.x, CELL.y, false, Image.FORMAT_RGBA8)
	for y in CELL.y:
		for x in CELL.x:
			if albedo.get_pixel(x, y).a > 0.5:
				image.set_pixel(x, y, FLAT_NORMAL)
	return image


## Mean sRGB colour of the opaque pixels of the views of one atlas row.
static func _mean_color(atlas: Image, row: int) -> Color:
	var total := Color(0, 0, 0, 0)
	var count := 0
	for v in VIEWS:
		for sy in range(4, CELL.y, 8):
			for sx in range(4, CELL.x, 8):
				var c := atlas.get_pixel(v * CELL.x + sx, row * CELL.y + sy)
				if c.a > 0.5:
					total += Color(c.r / c.a, c.g / c.a, c.b / c.a, 1.0)
					count += 1
	if count == 0:
		return Color(0.25, 0.35, 0.2)
	return Color(total.r / count, total.g / count, total.b / count, 1.0)


## The shared quad (x -0.5..0.5, y 0..1, UV.y 0 at the top).
static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[
			Vector3(-0.5, 0.0, 0.0),
			Vector3(0.5, 0.0, 0.0),
			Vector3(0.5, 1.0, 0.0),
			Vector3(-0.5, 1.0, 0.0)
		]
	)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(
		[Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK]
	)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader turns the quad about the vertical: cull it as the cylinder it sweeps.
	_mesh.custom_aabb = AABB(Vector3(-1.0, -BELOW_BASE, -1.0), Vector3(2.0, VERTICAL_SPAN, 2.0))
	return _mesh


## A new impostor material (`band_share`: VegetationRanges' hand-over band) of `shader` (SHADER
## or FOREST_SHADER).
static func material(band_share: float, shader: Shader = SHADER) -> ShaderMaterial:
	prime()
	var result := ShaderMaterial.new()
	result.shader = shader
	result.set_shader_parameter(&"band_share", band_share)
	result.set_shader_parameter(&"atlas", _atlas)
	result.set_shader_parameter(&"normal_atlas", _normal_atlas)
	result.set_shader_parameter(&"bake_elevation", deg_to_rad(ELEVATION))
	var values := LookPreset.vegetation()
	result.set_shader_parameter(&"exposure", values["impostor_albedo"])
	result.set_shader_parameter(&"slope_share", values["impostor_slope_share"])
	result.set_shader_parameter(&"rows", float(SPECIES.size() * TreeMeshes.VARIANTS))
	result.set_shader_parameter(&"views", float(VIEWS))
	result.set_shader_parameter(&"below_base", BELOW_BASE)
	result.set_shader_parameter(&"vertical_span", VERTICAL_SPAN)
	return result


## The unlit albedo atlas (prime() first).
static func atlas() -> ImageTexture:
	return _atlas


## The encoded view-space normal atlas, same layout as atlas() (prime() first).
static func normal_atlas() -> ImageTexture:
	return _normal_atlas


## [atlas row, quad width per unit of crown width] of a species' variant (prime() first).
static func row(species: StringName, variant: int) -> Array:
	return (_rows[species] as Array)[variant]


## The linear leaf colour a species' tint is relative to (prime() first).
static func leaf_color(species: StringName) -> Color:
	return _leaf[species]


## Mean sRGB colour of a species' unlit baked albedo (prime() first).
static func base_color(species: StringName) -> Color:
	return _mean[species]


## Tint of one tree relative to its species' baked colour (rgb around 1): the species colour
## shifted by its TreeSpecies variation (`custom`: r hue shift, g value, b saturation – as
## foliage_body.gdshaderinc does it) over the unshifted colour.
static func tint(species: StringName, custom: Color) -> Color:
	var c: Color = _leaf[species]
	var hsv: Vector3 = _leaf_hsv[species]
	var h := fposmod(hsv.x - custom.r, 1.0)
	var s := clampf(hsv.y * custom.b, 0.0, 1.0)
	var v := hsv.z * custom.g
	var shifted := Color.from_hsv(h, s, v)
	return Color(
		clampf(shifted.r / maxf(c.r, 0.02), 0.4, 1.8),
		clampf(shifted.g / maxf(c.g, 0.02), 0.4, 1.8),
		clampf(shifted.b / maxf(c.b, 0.02), 0.4, 1.8)
	)


## One instance: `base` is the tree's base (world), `width` / `height` its crown width and
## height (world units), `full` / `out` the range centres.
static func entry(
	species: StringName,
	variant: int,
	base: Vector3,
	width: float,
	height: float,
	custom: Color,
	full: float,
	out: float
) -> Array:
	var row: Array = (_rows[species] as Array)[variant]
	var color := tint(species, custom)
	color.a = 1.0
	return [base, width * float(row[1]), height, color, Color(full, out, float(row[0]), custom.a)]


## MultiMesh buffer of entry() instances, positions relative to `origin`.
static func buffer(entries: Array, origin: Vector3) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(entries.size() * STRIDE)
	for i in entries.size():
		var e: Array = entries[i]
		var p: Vector3 = (e[0] as Vector3) - origin
		var color: Color = e[3]
		var custom: Color = e[4]
		var k := i * STRIDE
		result[k] = e[1]
		result[k + 3] = p.x
		result[k + 5] = e[2]
		result[k + 7] = p.y
		result[k + 10] = e[1]
		result[k + 11] = p.z
		result[k + 12] = color.r
		result[k + 13] = color.g
		result[k + 14] = color.b
		result[k + 15] = color.a
		result[k + 16] = custom.r
		result[k + 17] = custom.g
		result[k + 18] = custom.b
		result[k + 19] = custom.a
	return result


## A MultiMesh of a buffer() (main thread).
static func multimesh(data: PackedFloat32Array) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = mesh()
	multi.instance_count = data.size() / STRIDE
	multi.buffer = data
	return multi
