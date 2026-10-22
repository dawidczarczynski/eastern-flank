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
