// Terrain ground (TASK-055): six CC0 PBR layers (TerrainTextures, TerrainSplat order: grass,
// dry_grass, dirt, mud, gravel, rock) blended by per-vertex weights – layers 0-3 in COLOR,
// 4-5 in CUSTOM0.xy (CUSTOM0.zw are free for TASK-035). Layers are sampled in world space
// (x, z) / layer_repeat; with anti_tiling a second, larger and rotated sample is mixed in by a
// low-frequency noise; weights are sharpened by the layer heights (height blending); with
// triplanar the rock layer is projected on three axes on steep slopes. UV2 carries the
// per-vertex value / saturation factors (darkened off-map margin, muted backdrop).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

const int LAYER_COUNT = 6;
const int ROCK = 5;
// Layers below this weight are not sampled.
const float WEIGHT_EPSILON = 0.004;

uniform sampler2DArray albedo_height : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_maps : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray roughness_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// World units per texture repeat, and a linear albedo tint, per layer.
uniform float layer_repeat[6];
uniform vec3 layer_tint[6];
// Second sample: repeat * far_scale, rotated by far_rotation (radians), mixed by a noise of
// this frequency (per world unit).
uniform bool anti_tiling = true;
uniform float far_scale = 3.7;
uniform float far_rotation = 0.6458;
uniform float anti_tiling_frequency = 0.35;
// Height blending: layers within this margin of the strongest weight + height survive.
uniform float height_blend = 0.2;
// Triplanar rock above this slope (1 - normal.y), cross-faded over +-triplanar_band.
uniform bool triplanar = true;
uniform float triplanar_slope = 0.3;
uniform float triplanar_band = 0.06;
uniform float normal_strength = 1.5;
// Source roughness is remapped into [roughness_min, 1] (grass scans are too glossy at this scale).
uniform float roughness_min = 0.7;
// Dielectric specular (0.5 = 4 % reflectance); lower keeps grazing sun glare off dry ground.
uniform float specular = 0.25;
uniform float ao_strength = 0.8;
// Low-frequency world-space brightness variation (+-macro_brightness).
uniform float macro_brightness = 0.08;
uniform float macro_frequency = 0.08;
// Lake and river beds darken with depth below the water level.
uniform float water_level = 0.0;
uniform float bed_darkening = 0.6;
uniform float bed_depth = 0.6;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 weights_a;
varying vec2 weights_b;
varying vec2 vertex_tint;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	weights_a = COLOR;
	weights_b = CUSTOM0.xy;
	vertex_tint = UV2;
}

// One planar sample of `layer` at texture coordinate `uv` with gradients dx / dy.
void sample_at(int layer, vec2 uv, vec2 dx, vec2 dy, out vec4 ah, out vec3 n, out vec2 ra) {
	vec3 p = vec3(uv, float(layer));
	ah = textureGrad(albedo_height, p, dx, dy);
	n = textureGrad(normal_maps, p, dx, dy).xyz * 2.0 - 1.0;
	ra = textureGrad(roughness_ao, p, dx, dy).rg;
}

// Planar (x, z) sample of `layer`, with the anti-tiling second scale mixed in by far_mix.
void sample_planar(int layer, vec2 xz, vec2 dx, vec2 dy, float far_mix, out vec4 ah, out vec3 n, out vec2 ra) {
	float inv = 1.0 / layer_repeat[layer];
	sample_at(layer, xz * inv, dx * inv, dy * inv, ah, n, ra);
	if (anti_tiling && far_mix > 0.0) {
		float c = cos(far_rotation);
		float s = sin(far_rotation);
		mat2 rot = mat2(vec2(c, s), vec2(-s, c));
		float far_inv = inv / far_scale;
		vec4 ah2;
		vec3 n2;
		vec2 ra2;
		sample_at(layer, rot * xz * far_inv, rot * dx * far_inv, rot * dy * far_inv, ah2, n2, ra2);
		// The far sample's tangent frame is rotated by far_rotation: rotate its normal back into
		// the planar frame (x, -z). Undoing rot in world (x, z) is transpose(rot); with green
		// along -v on both sides (F = diag(1, -1)) that becomes F * transpose(rot) * F = rot.
		n2.xy = rot * n2.xy;
		ah = mix(ah, ah2, far_mix);
		n = mix(n, n2, far_mix);
		ra = mix(ra, ra2, far_mix);
	}
}

// Triplanar rock: albedo/height and roughness/AO blended over the three projections, and the
// world-space normal (whiteout blend per projection).
void sample_triplanar(vec3 pos, vec3 dpx, vec3 dpy, vec3 wn, out vec4 ah, out vec3 world_n, out vec2 ra) {
	float inv = 1.0 / layer_repeat[ROCK];
	vec3 blend = pow(abs(wn), vec3(4.0));
	blend /= blend.x + blend.y + blend.z;
	vec4 ahx;
	vec4 ahy;
	vec4 ahz;
	vec3 nx;
	vec3 ny;
	vec3 nz;
	vec2 rax;
	vec2 ray;
	vec2 raz;
	sample_at(ROCK, pos.zy * inv, dpx.zy * inv, dpy.zy * inv, ahx, nx, rax);
	sample_at(ROCK, pos.xz * inv, dpx.xz * inv, dpy.xz * inv, ahy, ny, ray);
	sample_at(ROCK, pos.xy * inv, dpx.xy * inv, dpy.xy * inv, ahz, nz, raz);
	// OpenGL green points to -v. The planar (x, z) frame has its binormal along -z, so green
	// must point to -z on the y projection; on the x (zy) and z (xy) projections v runs along
	// world +y, so green must point to +y: flip it there.
	// Simplification: the projections ignore the face sign (no mirroring for faces pointing to
	// -x / -z); the rock detail is irregular enough that the mirrored relief does not show.
	ny.y = -ny.y;
	nx.y = -nx.y;
	nz.y = -nz.y;
	nx = vec3(nx.xy + wn.zy, abs(nx.z) * wn.x);
	ny = vec3(ny.xy + wn.xz, abs(ny.z) * wn.y);
	nz = vec3(nz.xy + wn.xy, abs(nz.z) * wn.z);
	world_n = normalize(nx.zyx * blend.x + ny.xzy * blend.y + nz.xyz * blend.z);
	ah = ahx * blend.x + ahy * blend.y + ahz * blend.z;
	ra = rax * blend.x + ray * blend.y + raz * blend.z;
}

void fragment() {
	vec2 xz = world_pos.xz;
	vec3 dpx = dFdx(world_pos);
	vec3 dpy = dFdy(world_pos);
	vec3 wn = normalize(world_normal);
	float w[6] = float[6](weights_a.r, weights_a.g, weights_a.b, weights_a.a, weights_b.x, weights_b.y);
	float far_mix = 0.0;
	if (anti_tiling) {
		far_mix = smoothstep(0.3, 0.7, value_noise(xz * anti_tiling_frequency));
	}
	float tri = 0.0;
	if (triplanar) {
		tri = smoothstep(triplanar_slope - triplanar_band, triplanar_slope + triplanar_band, 1.0 - wn.y);
	}

	vec4 ah[6];
	vec3 nt[6];
	vec2 ra[6];
	float best = -1.0;
	for (int i = 0; i < LAYER_COUNT; i++) {
		ah[i] = vec4(0.0);
		nt[i] = vec3(0.0, 0.0, 1.0);
		ra[i] = vec2(1.0);
		if (w[i] > WEIGHT_EPSILON) {
			if (i != ROCK || tri < 1.0) {
				sample_planar(i, xz, dpx.xz, dpy.xz, far_mix, ah[i], nt[i], ra[i]);
			}
			if (i == ROCK && tri > 0.0) {
				vec4 tah;
				vec3 twn;
				vec2 tra;
				sample_triplanar(world_pos, dpx, dpy, wn, tah, twn, tra);
				// World normal -> tangent space of this fragment (view-space TBN).
				vec3 v = (VIEW_MATRIX * vec4(twn, 0.0)).xyz;
				vec3 tn = vec3(dot(v, TANGENT), dot(v, BINORMAL), dot(v, NORMAL));
				ah[i] = mix(ah[i], tah, tri);
				nt[i] = mix(nt[i], tn, tri);
				ra[i] = mix(ra[i], tra, tri);
			}
			best = max(best, w[i] + ah[i].a);
		}
	}

	// Height blending: sharp edges where the higher material pokes through.
	vec3 albedo = vec3(0.0);
	vec3 n = vec3(0.0);
	vec2 rough_ao = vec2(0.0);
	float total = 0.0;
	for (int i = 0; i < LAYER_COUNT; i++) {
		if (w[i] > WEIGHT_EPSILON) {
			float hw = max(0.0, w[i] + ah[i].a - best + height_blend);
			albedo += ah[i].rgb * layer_tint[i] * hw;
			n += nt[i] * hw;
			rough_ao += ra[i] * hw;
			total += hw;
		}
	}
	total = max(total, 1e-5);
	albedo /= total;
	rough_ao /= total;
	n = normalize(vec3(n.xy * normal_strength, max(n.z, 1e-3)));

	// Macro brightness, then the per-vertex value / saturation (off-map margin, backdrop).
	float macro = value_noise(xz * macro_frequency) * 0.65 + value_noise(xz * macro_frequency * 2.7 + 17.0) * 0.35;
	albedo *= 1.0 + macro_brightness * (2.0 * macro - 1.0);
	float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = mix(vec3(lum), albedo, vertex_tint.y) * vertex_tint.x;
	albedo *= mix(1.0, 1.0 - bed_darkening, smoothstep(0.0, bed_depth, water_level - world_pos.y));

	ALBEDO = albedo;
	ROUGHNESS = mix(roughness_min, 1.0, rough_ao.x);
	SPECULAR = specular;
	AO = mix(1.0, rough_ao.y, ao_strength);
	NORMAL = normalize(TANGENT * n.x + BINORMAL * n.y + NORMAL * n.z);
}
