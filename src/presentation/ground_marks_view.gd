class_name GroundMarksView
extends Node3D
## The ground decals of TASK-058: one Decal node per GroundMarks mark (tracks, tyre marks,
## craters, scorch). Decals project only onto the terrain and grass visual layers (MapView),
## so units and trees are never covered. At most `max_decals` exist (GraphicsQuality "decals_max");
## GroundMarks.Pool decides which one goes when it is full. New marks fade in over FADE_IN.
## The view holds no game state – BattleController feeds it while the matching animation plays.

## Decals project onto the terrain layer and the grass layer only (the grass would otherwise hide
## the marks on plains: blades are tinted like the ground below them). Units, trees, bushes, rocks
## and overlays stay on layer 1 and are never covered.
const CULL_MASK := MapView.TERRAIN_LAYER_MASK | MapView.GRASS_LAYER_MASK
const FADE_IN := 0.3
## Height of the projection box, centred on the ground height at the mark.
const BOX_HEIGHT := 0.6
## The box edges fade out over this much, so a mark stays solid on slopes within the box.
const EDGE_FADE := 0.08
const TEXTURE_SIZE := 128
const TRACK_ALPHA := 0.85
const CRATER_ALPHA := 1.0
const SCORCH_ALPHA := 1.0

## Reveal steps of a growing track mark (one cached texture per step and kind).
const REVEAL_LEVELS := 32
const _LEVEL_META := &"reveal_level"

static var _textures := {}
static var _reveal_textures := {}

var _pool: GroundMarks.Pool = GroundMarks.Pool.new(0)


## `max_decals` from GraphicsQuality.features (0 = no marks at all).
func setup(max_decals: int) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_pool = GroundMarks.Pool.new(max_decals)


func is_active() -> bool:
	return _pool.max_count > 0


## Number of live decals.
func decal_count() -> int:
	return _pool.size()


func decals() -> Array[Decal]:
	var nodes: Array[Decal] = []
	for child in get_children():
		if child is Decal and not child.is_queued_for_deletion():
			nodes.append(child)
	return nodes


## Adds the decals of `marks` (GroundMarks dictionaries); with `animate` they fade in.
func add_marks(marks: Array[Dictionary], animate := true) -> void:
	if not is_active():
		return
	for mark in marks:
		_add(mark, animate)


## Adds the track or tyre marks of `marks` with nothing revealed yet (invisible) and returns
## their decals in the same order; BattleController grows them with `set_reveal()`.
func add_growing_tracks(marks: Array[Dictionary]) -> Array[Decal]:
	var nodes: Array[Decal] = []
	if not is_active():
		return nodes
	for mark in marks:
		var decal := _add(mark, false)
		decal.set_meta(&"mark_length", mark["length"])
		_set_level(decal, 0)
		nodes.append(decal)
	return nodes


## Reveals `fraction` (0..1) of a track decal from add_growing_tracks(), measured along its
## length from the start. Ignores decals that were evicted or freed meanwhile.
func set_reveal(decal: Decal, fraction: float) -> void:
	if not is_instance_valid(decal) or decal.is_queued_for_deletion():
		return
	var length: float = decal.get_meta(&"mark_length", 0.0)
	var overlap := GroundMarks.TRACK_OVERLAP
	var cut := (overlap * 0.5 + clampf(fraction, 0.0, 1.0) * length) / (length + overlap)
	var level := REVEAL_LEVELS if fraction >= 1.0 else floori(cut * REVEAL_LEVELS)
	_set_level(decal, level)


func _set_level(decal: Decal, level: int) -> void:
	if decal.get_meta(_LEVEL_META, -1) == level:
		return
	decal.set_meta(_LEVEL_META, level)
	decal.visible = level > 0
	if level > 0:
		decal.texture_albedo = _reveal_texture(decal.get_meta(&"mark_kind"), level)


func _add(mark: Dictionary, animate: bool) -> Decal:
	var kind: StringName = mark["kind"]
	var decal := Decal.new()
	decal.name = "Mark_%s" % kind
	decal.set_meta(&"mark_kind", kind)
	decal.cull_mask = CULL_MASK
	decal.texture_albedo = _texture(kind)
	decal.upper_fade = EDGE_FADE
	decal.lower_fade = EDGE_FADE
	var long_side: float = mark["length"]
	if kind == GroundMarks.KIND_TRACK or kind == GroundMarks.KIND_TYRE:
		long_side += GroundMarks.TRACK_OVERLAP
	decal.size = Vector3(long_side, BOX_HEIGHT, mark["width"])
	decal.transform = Transform3D(
		Basis(Vector3.UP, mark["yaw"]) * Basis(Vector3.BACK, mark["pitch"]), mark["center"]
	)
	var alpha := _alpha(kind)
	decal.modulate = Color(1, 1, 1, 0.0 if animate else alpha)
	add_child(decal)
	if animate:
		decal.create_tween().tween_property(decal, "modulate:a", alpha, FADE_IN)
	for evicted: Decal in _pool.add(kind, decal):
		evicted.queue_free()
	return decal


static func _alpha(kind: StringName) -> float:
	match kind:
		GroundMarks.KIND_TRACK, GroundMarks.KIND_TYRE:
			return TRACK_ALPHA
		GroundMarks.KIND_CRATER:
			return CRATER_ALPHA
		_:
			return SCORCH_ALPHA


static func _reveal_texture(kind: StringName, level: int) -> Texture2D:
	if level >= REVEAL_LEVELS:
		return _texture(kind)
	var key := "%s_%d" % [kind, level]
	if not _reveal_textures.has(key):
		var base := DecalTextures.tread(TEXTURE_SIZE)
		if kind == GroundMarks.KIND_TYRE:
			base = DecalTextures.tyre(TEXTURE_SIZE)
		var image := DecalTextures.revealed(base, float(level) / REVEAL_LEVELS)
		_reveal_textures[key] = ImageTexture.create_from_image(image)
	return _reveal_textures[key]


static func _texture(kind: StringName) -> ImageTexture:
	if not _textures.has(kind):
		var image: Image
		match kind:
			GroundMarks.KIND_TRACK:
				image = DecalTextures.tread(TEXTURE_SIZE)
			GroundMarks.KIND_TYRE:
				image = DecalTextures.tyre(TEXTURE_SIZE)
			GroundMarks.KIND_CRATER:
				image = DecalTextures.crater(TEXTURE_SIZE)
			GroundMarks.KIND_BURNT:
				image = DecalTextures.burnt_ground(TEXTURE_SIZE)
			_:
				image = DecalTextures.scorch(TEXTURE_SIZE)
		_textures[kind] = ImageTexture.create_from_image(image)
	return _textures[kind]
