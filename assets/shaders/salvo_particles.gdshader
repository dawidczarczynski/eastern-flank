// Pooled salvo puffs (TASK-075): simulation of particles added with GPUParticles3D.emit_particle().
// Per particle (emitted): position, velocity, COLOR (tint, alpha = opacity), CUSTOM = (rotation,
// age 0..1, size multiplier, lifetime fraction of LIFETIME). Air drag pulls the velocity towards
// the drift (wind + a slow rise), so a fast puff billows out, stops and then drifts; debris layers
// add gravity. The puff grows fast first and slower later (ease-out).
shader_type particles;
render_mode disable_force;

uniform float drag = 2.0;
uniform float rise = 0.2;
uniform float gravity = 0.0;
uniform vec3 wind = vec3(0.0);
uniform float size_start = 0.1;
uniform float size_end = 1.0;
uniform float grow = 3.0;
uniform float spin = 0.4;

void start() {
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0, 0.0, 1.0, 1.0);
	}
	if (RESTART_COLOR) {
		COLOR = vec4(1.0);
	}
	CUSTOM.y = 0.0;
	float size = CUSTOM.z * size_start;
	vec3 pos = TRANSFORM[3].xyz;
	TRANSFORM = mat4(
		vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(pos, 1.0)
	);
}

void process() {
	float life = max(LIFETIME * CUSTOM.w, 0.001);
	CUSTOM.y += DELTA / life;
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	float t = clamp(CUSTOM.y, 0.0, 1.0);
	VELOCITY.y -= gravity * DELTA;
	vec3 drift = wind + vec3(0.0, rise, 0.0);
	VELOCITY = mix(VELOCITY, drift, 1.0 - exp(-drag * DELTA));
	float turn = fract(float(INDEX) * 0.618034) * 2.0 - 1.0;
	CUSTOM.x += spin * turn * DELTA / (1.0 + 3.0 * t);
	float size = CUSTOM.z * mix(size_start, size_end, 1.0 - pow(1.0 - t, grow));
	vec3 pos = TRANSFORM[3].xyz;
	TRANSFORM = mat4(
		vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0), vec4(pos, 1.0)
	);
}
