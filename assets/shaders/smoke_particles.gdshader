// Smoke, dust and fire puffs (salvo TASK-075, vehicle dust and exhaust). A puff is either added
// with GPUParticles3D.emit_particle() – position, velocity, COLOR (tint, alpha = opacity) and
// CUSTOM = (rotation, age 0..1, size multiplier, lifetime fraction of LIFETIME) given – or emitted
// by the node itself (`emitting`), then the emit_* uniforms pick those values at random. Air drag
// pulls the velocity towards the drift (wind + a slow rise), so a fast puff billows out, stops and
// then drifts; debris adds gravity. The puff grows fast first and slower later (ease-out).
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
// Self-emitted puffs only: direction (emitter space), cone half angle (degrees), speed range,
// position jitter (world units), colour, size multiplier and lifetime fraction ranges.
uniform vec3 emit_direction = vec3(0.0, 1.0, 0.0);
uniform float emit_spread = 20.0;
uniform vec2 emit_speed = vec2(0.0, 0.0);
uniform float emit_jitter = 0.0;
uniform vec4 emit_tint : source_color = vec4(1.0);
uniform vec2 emit_size = vec2(1.0, 1.0);
uniform vec2 emit_life = vec2(1.0, 1.0);

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	return (x >> uint(16)) ^ x;
}

float rand(inout uint seed) {
	seed = hash(seed);
	return float(seed % uint(1000003)) / 1000003.0;
}

void start() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(
			rand(seed) * TAU,
			0.0,
			mix(emit_size.x, emit_size.y, rand(seed)),
			mix(emit_life.x, emit_life.y, rand(seed))
		);
	}
	if (RESTART_COLOR) {
		COLOR = emit_tint;
	}
	mat3 emitter = mat3(
		normalize(EMISSION_TRANSFORM[0].xyz),
		normalize(EMISSION_TRANSFORM[1].xyz),
		normalize(EMISSION_TRANSFORM[2].xyz)
	);
	if (RESTART_VELOCITY) {
		vec3 axis = normalize(emit_direction);
		vec3 helper = abs(axis.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 u = normalize(cross(axis, helper));
		vec3 v = cross(axis, u);
		float angle = radians(emit_spread) * sqrt(rand(seed));
		float around = rand(seed) * TAU;
		vec3 dir = axis * cos(angle) + (u * cos(around) + v * sin(around)) * sin(angle);
		VELOCITY = emitter * dir * mix(emit_speed.x, emit_speed.y, rand(seed));
	}
	vec3 pos = TRANSFORM[3].xyz;
	if (RESTART_POSITION) {
		vec3 jitter = (vec3(rand(seed), rand(seed), rand(seed)) * 2.0 - 1.0) * emit_jitter;
		pos = EMISSION_TRANSFORM[3].xyz + jitter;
	}
	CUSTOM.y = 0.0;
	float size = CUSTOM.z * size_start;
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
