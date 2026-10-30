// Rocket smoke trail (TASK-075): a camera-facing ribbon through the points a rocket passed while
// its motor burned. Per vertex: VERTEX = the trail point (world), NORMAL = the trail direction,
// UV = (side -1 / 1, distance along the trail), UV2.x = when the point was laid (the trail's clock).
// Each point widens, thins out, rises and drifts with the wind as it ages.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;

instance uniform float now = 0.0;
uniform float life = 4.0;
uniform float width_start = 0.03;
uniform float width_end = 0.3;
uniform vec3 wind = vec3(0.0);
uniform float rise = 0.08;
uniform vec4 color : source_color = vec4(0.27, 0.26, 0.25, 0.75);
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

varying float age_t;
varying float side;
varying float along;

void vertex() {
	float age = max(now - UV2.x, 0.0);
	age_t = clamp(age / life, 0.0, 1.0);
	vec3 world = VERTEX + (wind + vec3(0.0, rise, 0.0)) * age;
	vec3 view_pos = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	vec3 tangent = normalize((VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 across = cross(tangent, normalize(view_pos));
	across = length(across) > 0.0001 ? normalize(across) : vec3(1.0, 0.0, 0.0);
	float width = mix(width_start, width_end, sqrt(age_t));
	VERTEX = view_pos + across * UV.x * width * 0.5;
	side = UV.x;
	along = UV.y;
}

void fragment() {
	float edge = 1.0 - abs(side);
	float n = texture(noise, vec2(along * 0.8 - age_t * 0.3, side * 0.35 + age_t * 0.5)).r;
	float body = smoothstep(0.0, 0.7, edge) * mix(0.45, 1.0, n);
	float thin = (1.0 - age_t) * mix(1.0, 0.35, sqrt(age_t));
	float start = smoothstep(0.0, 0.15, along);
	ALBEDO = color.rgb * mix(0.85, 1.1, n);
	ALPHA = clamp(color.a * body * thin * start, 0.0, 1.0);
}
