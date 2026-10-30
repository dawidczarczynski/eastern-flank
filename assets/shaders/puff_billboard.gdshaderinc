// Shared billboard of the smoke / fire puffs (TASK-075): a camera-facing quad of the particle's size,
// turned by INSTANCE_CUSTOM.x, its colour and opacity = particle COLOR x the layer's ramp over the
// particle's life (INSTANCE_CUSTOM.y), faded where it meets the ground (soft particles).

uniform sampler2D puff_texture : filter_linear_mipmap, repeat_disable;
uniform sampler2D ramp : source_color, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// Distance (world units) over which a puff fades in front of the geometry behind it.
uniform float soft_distance = 0.3;

varying vec2 corner;
varying float life_t;

void vertex() {
	float a = INSTANCE_CUSTOM.x;
	vec2 c = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xy;
	corner = c;
	life_t = INSTANCE_CUSTOM.y;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 centre = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	VERTEX = centre + vec3(c * size, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

vec4 puff_color(vec4 vertex_color) {
	return vertex_color * texture(ramp, vec2(life_t, 0.5));
}

float soft_fade(vec2 screen_uv, vec3 view_vertex, mat4 inv_projection) {
	float depth = textureLod(depth_texture, screen_uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(screen_uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
#endif
	vec4 scene = inv_projection * vec4(ndc, 1.0);
	float scene_z = -scene.z / scene.w;
	return clamp((scene_z + view_vertex.z) / soft_distance, 0.0, 1.0);
}
