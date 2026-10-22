// Shared wind (TASK-057): used by grass, later trees and undergrowth. The global uniforms are
// registered at runtime by Wind.setup() (src/presentation/wind.gd), not in project.godot.
global uniform vec2 wind_direction;
global uniform float wind_strength;
global uniform float wind_speed;

// World-space sway offset of a point at relative height h (0 root .. 1 tip) of a plant at world
// position world_pos; phase desynchronises plants (e.g. from a position hash).
vec3 wind_offset(vec3 world_pos, float h, float phase) {
	vec2 dir = normalize(wind_direction);
	float wave = sin(TIME * wind_speed + dot(world_pos.xz, dir) * 2.3 + phase);
	return vec3(dir.x, 0.0, dir.y) * (wind_strength * 0.012 * wave * h * h);
}

// Leaf flutter (TASK-060): a small fast jitter of a leaf card around its rest position, at most
// 0.005 * wind_strength (0.003 world units at Wind.STRENGTH 0.6); phase per card and tree.
vec3 wind_flutter(vec3 world_pos, float phase) {
	vec2 dir = normalize(wind_direction);
	float t = TIME * wind_speed * 4.7 + phase * 6.2831853 + dot(world_pos.xz, dir) * 5.0;
	vec3 sway = vec3(dir.x, 0.0, dir.y) * sin(t) + vec3(0.0, 0.6, 0.0) * sin(t * 1.37 + 1.1);
	return sway * (wind_strength * 0.005 * 0.85);
}
