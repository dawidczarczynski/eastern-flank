// Rocket motor flame at launch (TASK-075): an additive cone from the rocket's tail backwards, a
// white-hot core fading to an orange, ragged tip, soft at the silhouette (view-facing falloff).
// `intensity` (per instance) fades the whole flame out after the launch.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.95, 0.78);
uniform vec3 edge_color : source_color = vec3(1.0, 0.42, 0.08);
uniform float energy = 4.0;
instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;

varying float along;

void vertex() {
	along = VERTEX.y + 0.5;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float base = 1.0 - along;
	float flicker = 0.75 + 0.25 * sin(TIME * 70.0 + seed + along * 18.0) * sin(TIME * 41.0 + seed);
	vec3 col = mix(edge_color, core_color, smoothstep(0.35, 1.0, facing * base));
	float a = pow(facing, 1.5) * pow(base, 0.7) * flicker * intensity;
	ALBEDO = col * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
