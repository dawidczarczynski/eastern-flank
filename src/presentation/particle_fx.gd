class_name ParticleFx
extends RefCounted
## Shared setup of soft smoke / dust puffs (TASK-064; TASK-065 and TASK-048 reuse it): a
## procedural soft-noise texture, a billboard material tinted per particle and a GPUParticles3D
## factory. View-only: the particles use their own random seeds, never GameState.rng.

const TEXTURE_SIZE := 64
const NOISE_SEED := 6407
## Particles may drift this far from the emitter before the node is culled (world units).
const CULL_EXTENT := 6.0
const PUFF_PROCESS_SHADER := preload("res://assets/shaders/smoke_particles.gdshader")
const SMOKE_SHADER := preload("res://assets/shaders/smoke_puff.gdshader")
const FIRE_SHADER := preload("res://assets/shaders/fire_puff.gdshader")

static var _texture: ImageTexture
static var _material: StandardMaterial3D
static var _mesh: QuadMesh
static var _billow: ImageTexture
static var _puff_draws: Dictionary = {}  # look name -> QuadMesh shared by puff emitters


## Round puff with a noisy, soft edge (white, alpha from the noise and a radial falloff).
static func smoke_texture() -> ImageTexture:
	if _texture == null:
		var noise := FastNoiseLite.new()
		noise.seed = NOISE_SEED
		noise.frequency = 0.05
		noise.fractal_octaves = 3
		var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
		var half := TEXTURE_SIZE / 2.0
		for y in TEXTURE_SIZE:
			for x in TEXTURE_SIZE:
				var radial := clampf(1.0 - Vector2(x - half, y - half).length() / half, 0.0, 1.0)
				var grain := noise.get_noise_2d(x, y) * 0.5 + 0.5
				var alpha := smoothstep(0.0, 0.4, radial) * lerpf(0.55, 1.0, grain)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
		_texture = ImageTexture.create_from_image(image)
	return _texture


## Camera-facing quad lit by nothing: the colour and alpha come from the particle.
static func puff_mesh() -> QuadMesh:
	if _mesh == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_material.vertex_color_use_as_albedo = true
		_material.albedo_texture = smoke_texture()
		_material.disable_receive_shadows = true
		_mesh = QuadMesh.new()
		_mesh.size = Vector2.ONE
		_mesh.material = _material
	return _mesh


## Billowy puff for the salvo effects (TASK-075): a lumpy, ragged silhouette (the radius is bent
## by noise) with denser knots inside. Alpha = density; red = the grain the smoke shader uses as
## self-shadowing. Mipmapped, 128 px (puffs get large near the camera).
static func billow_texture() -> ImageTexture:
	if _billow == null:
		var size := 128
		var shape := FastNoiseLite.new()
		shape.seed = NOISE_SEED + 1
		shape.frequency = 0.035
		shape.fractal_octaves = 2
		var grain := FastNoiseLite.new()
		grain.seed = NOISE_SEED + 2
		grain.frequency = 0.06
		grain.fractal_octaves = 4
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var half := size / 2.0
		for y in size:
			for x in size:
				var offset := Vector2(x + 0.5 - half, y + 0.5 - half) / half
				var lump := shape.get_noise_2d(x, y) * 0.5 + 0.5
				var r := offset.length() * lerpf(0.8, 1.35, lump)
				var detail := grain.get_noise_2d(x, y) * 0.5 + 0.5
				var density := (1.0 - smoothstep(0.35, 0.95, r)) * lerpf(0.55, 1.0, detail)
				image.set_pixel(x, y, Color(detail, detail, detail, clampf(density, 0.0, 1.0)))
		image.generate_mipmaps()
		_billow = ImageTexture.create_from_image(image)
	return _billow


## A resting world-space emitter of sun-lit soft puffs (or additive fire) simulated by
## assets/shaders/smoke_particles.gdshader (TASK-075; vehicle dust and exhaust reuse it).
## `config`: amount, lifetime (s), drag (1/s, towards the drift), rise (drift up, u/s), wind
## (Vector3 drift), size_start / size_end (world units), grow (ease-out exponent), ramp (flat
## [offset, Color, ...] over the puff's life, multiplies its tint); optional gravity, fire (bool),
## look (a name: emitters of the same look share one draw mesh) and, for puffs the node emits
## itself, direction (emitter space), spread (deg), speed / size / life (Vector2 ranges; size
## and life multiply size_* and lifetime), jitter (world units), tint (Color, alpha = opacity).
## The emitter shows `amount_ratio` of amount per lifetime: rate = ratio * amount / lifetime.
static func puff_emitter(config: Dictionary) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = config["amount"]
	particles.lifetime = config["lifetime"]
	particles.local_coords = false
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3.ONE * -CULL_EXTENT, Vector3.ONE * CULL_EXTENT * 2.0)
	var process := ShaderMaterial.new()
	process.shader = PUFF_PROCESS_SHADER
	for key: String in ["drag", "rise", "wind", "size_start", "size_end", "grow"]:
		process.set_shader_parameter(key, config[key])
	process.set_shader_parameter("gravity", config.get("gravity", 0.0))
	process.set_shader_parameter("emit_direction", config.get("direction", Vector3.UP))
	process.set_shader_parameter("emit_spread", config.get("spread", 0.0))
	process.set_shader_parameter("emit_speed", config.get("speed", Vector2.ZERO))
	process.set_shader_parameter("emit_jitter", config.get("jitter", 0.0))
	process.set_shader_parameter("emit_tint", config.get("tint", Color.WHITE))
	process.set_shader_parameter("emit_size", config.get("size", Vector2.ONE))
	process.set_shader_parameter("emit_life", config.get("life", Vector2.ONE))
	particles.process_material = process
	var look: String = config.get("look", "")
	if look != "" and _puff_draws.has(look):
		particles.draw_pass_1 = _puff_draws[look]
		return particles
	var material := ShaderMaterial.new()
	material.shader = FIRE_SHADER if config.get("fire", false) else SMOKE_SHADER
	material.set_shader_parameter("puff_texture", billow_texture())
	material.set_shader_parameter("ramp", color_ramp(config["ramp"]))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	particles.draw_pass_1 = quad
	if look != "":
		_puff_draws[look] = quad
	return particles


## Changes the colour new puffs of a `puff_emitter` get (those in the air keep theirs).
static func set_puff_tint(particles: GPUParticles3D, tint: Color) -> void:
	(particles.process_material as ShaderMaterial).set_shader_parameter("emit_tint", tint)


## A resting (not emitting) emitter of world-space puffs. `config`: lifetime (s), max_particles,
## direction (emitter space), spread (deg), velocity_min / velocity_max, gravity (world, also the
## wind drift), damping, size_start / size_end (world units), alpha (peak), tint (Color).
## The emitter shows `amount_ratio` of max_particles per lifetime, so rate = ratio * max / lifetime.
static func emitter(config: Dictionary) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = config["max_particles"]
	particles.lifetime = config["lifetime"]
	particles.local_coords = false
	particles.emitting = false
	particles.amount_ratio = 0.0
	particles.randomness = 1.0
	particles.draw_pass_1 = puff_mesh()
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3.ONE * -CULL_EXTENT, Vector3.ONE * CULL_EXTENT * 2.0)
	var process := ParticleProcessMaterial.new()
	process.direction = config["direction"]
	process.spread = config["spread"]
	process.initial_velocity_min = config["velocity_min"]
	process.initial_velocity_max = config["velocity_max"]
	process.gravity = config["gravity"]
	process.damping_min = config["damping"]
	process.damping_max = config["damping"]
	process.angle_min = 0.0
	process.angle_max = 360.0
	var size_end: float = config["size_end"]
	process.scale_min = size_end
	process.scale_max = size_end
	process.scale_curve = _curve_texture([0.0, float(config["size_start"]) / size_end, 1.0, 1.0])
	process.color = config["tint"]
	process.color_ramp = _alpha_ramp(config["alpha"])
	particles.process_material = process
	return particles


## Changes the tint of an emitter made by `emitter` (the ground colour changes under a vehicle).
static func set_tint(particles: GPUParticles3D, tint: Color) -> void:
	(particles.process_material as ParticleProcessMaterial).color = tint


## Value curve from flat [x0, y0, x1, y1, ...] pairs.
static func _curve_texture(points: Array) -> CurveTexture:
	var curve := Curve.new()
	for i in range(0, points.size(), 2):
		curve.add_point(Vector2(points[i], points[i + 1]))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## Colour over a particle's life from flat [offset, Color, offset, Color, ...] pairs.
static func color_ramp(stops: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in range(0, stops.size(), 2):
		offsets.append(stops[i])
		colors.append(stops[i + 1])
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## White with alpha fading in quickly and out slowly.
static func _alpha_ramp(peak: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, peak), Color(1, 1, 1, 0)])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
