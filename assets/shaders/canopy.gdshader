shader_type spatial;
render_mode specular_disabled;
// Distant forest (backdrop canopy): a thin shell over the backdrop ground, drawn instead of
// individual trees. Vertex colour r = forest cover (0 open ground .. 1 forest, already faded in
// with the distance from the playable map). The fragment shader paints closed crowns as a
// jittered Voronoi pattern in world space: each crown is a dome in a species leaf colour, and a
// crown is dropped when its hash exceeds the cover, so forest edges and the fade-in towards the
// real trees are ragged instead of hard.

uniform vec3 pine_color : source_color = vec3(0.25, 0.38, 0.25);
uniform vec3 spruce_color : source_color = vec3(0.19, 0.31, 0.23);
uniform vec3 birch_color : source_color = vec3(0.56, 0.66, 0.31);
uniform vec3 oak_color : source_color = vec3(0.38, 0.52, 0.22);
uniform vec3 alder_color : source_color = vec3(0.33, 0.49, 0.21);
// Species shares (pine, spruce, birch, oak; the rest is alder).
uniform vec4 shares = vec4(0.35, 0.25, 0.1, 0.15);
// Crown spacing in world units.
uniform float crown_cell = 0.34;

varying vec2 world_xz;
varying float cover;

vec2 hash22(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	cover = COLOR.r;
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + NORMAL * 0.4);
}

void fragment() {
	vec2 p = world_xz / crown_cell;
	vec2 base = floor(p);
	float best = 8.0;
	vec2 best_id = base;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = base + vec2(float(i), float(j));
			vec2 centre = id + 0.15 + 0.7 * hash22(id);
			float d = distance(p, centre);
			if (d < best) {
				best = d;
				best_id = id;
			}
		}
	}
	vec2 h = hash22(best_id + 17.0);
	if (h.x > smoothstep(0.05, 0.95, cover)) {
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
	// Dome shading: bright crown top, dark gaps between crowns.
	float dome = clamp(1.0 - best / 0.8, 0.0, 1.0);
	float shade = mix(0.4, 0.85, sqrt(dome)) * (0.92 + 0.16 * h.x);
	ALBEDO = color * shade;
	ROUGHNESS = 0.9;
}
