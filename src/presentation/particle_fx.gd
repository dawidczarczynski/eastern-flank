class_name ParticleFx
extends RefCounted
## Shared setup of soft smoke / dust puffs (TASK-064; TASK-065 and TASK-048 reuse it): a
## procedural soft-noise texture, a billboard material tinted per particle and a GPUParticles3D
## factory. View-only: the particles use their own random seeds, never GameState.rng.

const TEXTURE_SIZE := 64
const NOISE_SEED := 6407
## Particles may drift this far from the emitter before the node is culled (world units).
const CULL_EXTENT := 6.0

static var _texture: ImageTexture
static var _material: StandardMaterial3D
static var _mesh: QuadMesh


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


## White with alpha fading in quickly and out slowly.
static func _alpha_ramp(peak: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, peak), Color(1, 1, 1, 0)])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
