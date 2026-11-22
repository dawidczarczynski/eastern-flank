shader_type spatial;
render_mode specular_disabled;
// Distant forest (backdrop canopy): a thin shell over the backdrop ground, drawn instead of
// individual trees. Vertex colour r = forest cover (0 open ground .. 1 forest, already faded in
// with the distance from the playable map). The fragment shader paints closed crowns as a
// jittered Voronoi pattern in world space: each crown is a dome in a species leaf colour, and a
// crown is dropped when its hash exceeds the cover, so forest edges and the fade-in towards the
// real trees are ragged instead of hard.
// The real-scale forest shell (TASK-135, ForestShell) uses it over the map's forest tiles too: it
// fades in crown by crown with the camera distance over `near_fade`, where the tree impostors end.

#include "res://assets/shaders/cloud_shadow.gdshaderinc"

uniform vec3 pine_color : source_color = vec3(0.25, 0.38, 0.25);
uniform vec3 spruce_color : source_color = vec3(0.19, 0.31, 0.23);
uniform vec3 birch_color : source_color = vec3(0.56, 0.66, 0.31);
uniform vec3 oak_color : source_color = vec3(0.38, 0.52, 0.22);
uniform vec3 alder_color : source_color = vec3(0.33, 0.49, 0.21);
// Species shares (pine, spruce, birch, oak; the rest is alder).
uniform vec4 shares = vec4(0.35, 0.25, 0.1, 0.15);
// Crown spacing in world units.
uniform float crown_cell = 0.34;
// Camera distance (from, to; world units) over which the shell fades in crown by crown; the
// default keeps it always on (the backdrop).
uniform vec2 near_fade = vec2(-2.0, -1.0);
// Albedo factor (the real-scale shell meets the tree impostors' tone with it).
uniform float brightness = 1.0;
// 1: the crowns are lit as domes (a normal from the dome's slope, so the sun picks out single
// crowns) and the species mix by stands rather than crown by crown – the real-scale forest shell,
// which is seen from low cameras. 0: the flat painted look of the backdrop. The real-scale shell's
// colours are the impostors' unlit albedo (TASK-191) and the domes stand on the ground's normal
// turned by `slope_share` (as the impostors' pictures), so the same sun lights both.
uniform float lit_domes = 0.0;
uniform float slope_share = 1.0;
// The real-scale shell: how far the crowns' normals lean towards the camera (0..1). The visible
// half of a crown faces the viewer, so the impostors' baked normals do (sunlit crowns with the sun
// behind the camera, shaded ones against it); the shell leans the same way to meet them.
uniform float view_share = 0.0;
// The real-scale shell (ForestField coverage mask): where `coverage` is dark – tree impostors not
// built yet there – the shell ignores `near_fade` and stands in for them.
uniform float use_coverage = 0.0;
uniform sampler2D coverage : filter_nearest, repeat_disable;
uniform vec2 coverage_origin = vec2(0.0);
uniform vec2 coverage_extent = vec2(1.0);

varying vec2 world_xz;
varying vec3 world_position;
varying float cover;
varying vec3 surface_normal;
// The main camera's position: the fade follows it in the shadow pass too (TASK-201a: the
// real-scale shell casts the forest's shadow where it stands in for the trees).
varying vec3 main_camera;

vec2 hash22(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

const mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

// Smooth value noise 0..1.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash22(i).x;
	float b = hash22(i + vec2(1.0, 0.0)).x;
	float c = hash22(i + vec2(0.0, 1.0)).x;
	float d = hash22(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = world_position.xz;
	cover = COLOR.r;
	surface_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	main_camera = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + NORMAL * 0.4);
}

void fragment() {
	vec2 p = world_xz / crown_cell;
	vec2 base = floor(p);
	float best = 8.0;
	vec2 best_id = base;
	vec2 best_centre = base;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = base + vec2(float(i), float(j));
			vec2 centre = id + 0.15 + 0.7 * hash22(id);
			float d = distance(p, centre);
			if (d < best) {
				best = d;
				best_id = id;
				best_centre = centre;
			}
		}
	}
	vec2 h = hash22(best_id + 17.0);
	float fade = smoothstep(near_fade.x, near_fade.y, distance(world_position, main_camera));
	if (use_coverage > 0.5) {
		vec2 cell = (world_xz - coverage_origin) / coverage_extent;
		if (texture(coverage, cell).r < 0.5) {
			fade = 1.0;
		}
	}
	if (h.x > min(smoothstep(0.05, 0.95, cover), fade)) {
		discard;
	}
	vec3 color = alder_color;
	float t1 = shares.x;
	float t2 = t1 + shares.y;
	float t3 = t2 + shares.z;
	float t4 = t3 + shares.w;
	if (h.y < t1) {
		color = pine_color;
	} else if (h.y < t2) {
		color = spruce_color;
	} else if (h.y < t3) {
		color = birch_color;
	} else if (h.y < t4) {
		color = oak_color;
	}
	// Pulled towards the mean forest colour so the patchwork stays calm from afar.
	vec3 mean_color = (pine_color + spruce_color + birch_color + oak_color + alder_color) / 5.0;
	color = mix(mean_color, color, 0.45);
	if (lit_domes > 0.5) {
		// Stands of one dominant species a few crowns wide: smooth noise (two rotated octaves, no
		// square grid to show from afar) picks the species by the shares.
		vec2 sp = world_xz / (crown_cell * 7.0);
		float stand_n = 0.65 * value_noise(rot * sp) + 0.35 * value_noise(rot * sp * 2.3 + 11.0);
		float stand_roll = clamp((stand_n - 0.5) * 2.0 + 0.5, 0.0, 0.999);
		vec3 stand_color = alder_color;
		if (stand_roll < t1) {
			stand_color = pine_color;
		} else if (stand_roll < t2) {
			stand_color = spruce_color;
		} else if (stand_roll < t3) {
			stand_color = birch_color;
		} else if (stand_roll < t4) {
			stand_color = oak_color;
		}
		color = mix(mean_color, mix(stand_color, color, 0.35), 0.7);
		float slope = clamp(best / 0.8, 0.0, 1.0);
		vec2 outward = (p - best_centre) / max(best, 0.001);
		vec3 ground_n = normalize(mix(vec3(0.0, 1.0, 0.0), surface_normal, slope_share));
		vec3 to_camera = normalize(main_camera - world_position);
		ground_n = normalize(mix(ground_n, to_camera, view_share));
		vec3 n_world = normalize(ground_n + vec3(outward.x, 0.0, outward.y) * slope * 1.3);
		NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	}
	// Dome shading: bright crown top, dark gaps between crowns.
	float dome = clamp(1.0 - best / 0.8, 0.0, 1.0);
	float shade = mix(0.4, 0.85, sqrt(dome)) * (0.92 + 0.16 * h.x);
	ALBEDO = color * shade * brightness * cloud_shadow_factor(world_xz);
	ROUGHNESS = 0.9;
}
