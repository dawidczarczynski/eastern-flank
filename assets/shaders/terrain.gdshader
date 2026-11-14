// Terrain ground (TASK-055, farmland parcels TASK-108f): seven CC0 PBR layers (TerrainTextures, TerrainSplat order: grass,
// dry_grass, dirt, mud, gravel, rock, soil) blended by per-vertex weights – layers 0-3 in COLOR,
// 4-6 in CUSTOM0.xyz (CUSTOM0.w is free for TASK-035). Layers are sampled in world space
// (x, z) / layer_repeat; with anti_tiling a second, larger and rotated sample is mixed in by a
// low-frequency noise; weights are sharpened by the layer heights (height blending); with
// triplanar the rock layer is projected on three axes on steep slopes. UV2 carries the
// per-vertex value / saturation factors (darkened off-map margin, muted backdrop).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

const int LAYER_COUNT = 7;
const int ROCK = 5;
// Farmland parcels (TASK-108f): kinds of FieldParcels.Kind, 9 entries (none, 7 crops, balk).
const int PARCEL_KINDS = 9;
// Layers below this weight are not sampled.
const float WEIGHT_EPSILON = 0.004;

uniform sampler2DArray albedo_height : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Normal x, y (OpenGL, z is rebuilt) in RG, roughness in B, ambient occlusion in A. Trilinear:
// anisotropic filtering only pays on the albedo (~0.35 ms on the target GPU for no visible gain).
uniform sampler2DArray normal_rough_ao : hint_default_white, filter_linear_mipmap, repeat_enable;
// World units per texture repeat, and a linear albedo tint, per layer.
uniform float layer_repeat[7];
uniform vec3 layer_tint[7];
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

// Farmland parcel map (FieldParcels.bake, RG8): kind in red, parcel id * 2 + row orientation
// (1 = rows run along x) in green. parcel_rect = (x, z, 1 / width, 1 / height) in world units.
// Off (the default battle) when the map has no fields.
uniform bool parcels_on = false;
uniform sampler2D parcel_map : filter_nearest, repeat_disable, hint_default_black;
uniform vec4 parcel_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float metres_per_unit = 144.34;
// Per kind: plant and furrow colour (linear) and (row spacing in m, plant width fraction).
uniform vec3 crop_plant[9];
uniform vec3 crop_furrow[9];
uniform vec2 crop_row[9];
uniform float parcel_brightness = 0.12;
uniform float parcel_hue = 0.07;
// Rows fade to the average colour as one row spans this many pixels (from .. to).
uniform vec2 row_fade = vec2(0.3, 0.8);
// Parcels fade out on ground steeper than this slope (1 - normal.y), from .. to.
uniform vec2 parcel_slope = vec2(0.08, 0.14);

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 weights_a;
varying vec3 weights_b;
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
	weights_b = CUSTOM0.xyz;
	vertex_tint = UV2;
}

// Planar texture coordinates of one sample: the near scale, and with anti-tiling the larger,
// rotated second one (far_rot rotates world (x, z) into its frame).
struct Planar {
	vec3 near;
	vec2 near_dx;
	vec2 near_dy;
	vec3 far;
	vec2 far_dx;
	vec2 far_dy;
};

Planar planar_coords(int layer, vec2 xz, vec2 dx, vec2 dy, mat2 far_rot) {
	float inv = 1.0 / layer_repeat[layer];
	float far_inv = inv / far_scale;
	Planar c;
	c.near = vec3(xz * inv, float(layer));
	c.near_dx = dx * inv;
	c.near_dy = dy * inv;
	c.far = vec3(far_rot * xz * far_inv, float(layer));
	c.far_dx = far_rot * dx * far_inv;
	c.far_dy = far_rot * dy * far_inv;
	return c;
}

// Tangent-space normal (xyz) and roughness / AO (out) of one fetch of normal_rough_ao.
vec3 unpack_normal(vec4 texel, out vec2 ra) {
	vec2 xy = texel.rg * 2.0 - 1.0;
	ra = texel.ba;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// Albedo / height of a planar sample; far_mix 0 = only the near scale, 1 = only the far one
// (the scale that does not show is not fetched).
vec4 planar_albedo(Planar c, float far_mix) {
	vec4 ah = vec4(0.0);
	if (far_mix < 1.0) {
		ah = textureGrad(albedo_height, c.near, c.near_dx, c.near_dy);
	}
	if (far_mix > 0.0) {
		ah = mix(ah, textureGrad(albedo_height, c.far, c.far_dx, c.far_dy), far_mix);
	}
	return ah;
}

// Normal and roughness / AO of a planar sample, as planar_albedo.
vec3 planar_detail(Planar c, float far_mix, mat2 far_rot, out vec2 ra) {
	vec3 n = vec3(0.0);
	ra = vec2(0.0);
	if (far_mix < 1.0) {
		n = unpack_normal(textureGrad(normal_rough_ao, c.near, c.near_dx, c.near_dy), ra);
	}
	if (far_mix > 0.0) {
		vec2 ra2;
		vec3 n2 = unpack_normal(textureGrad(normal_rough_ao, c.far, c.far_dx, c.far_dy), ra2);
		// The far sample's tangent frame is rotated by far_rotation: rotate its normal back into
		// the planar frame (x, -z). Undoing rot in world (x, z) is transpose(rot); with green
		// along -v on both sides (F = diag(1, -1)) that becomes F * transpose(rot) * F = rot.
		n2.xy = far_rot * n2.xy;
		n = mix(n, n2, far_mix);
		ra = mix(ra, ra2, far_mix);
	}
	return n;
}

// Triplanar blend weights of the three projections (x, y, z) for the world normal `wn`.
vec3 triplanar_blend(vec3 wn) {
	vec3 blend = pow(abs(wn), vec3(4.0));
	return blend / (blend.x + blend.y + blend.z);
}

// Triplanar rock: albedo / height blended over the three projections.
vec4 triplanar_albedo(vec3 pos, vec3 dpx, vec3 dpy, vec3 wn) {
	float inv = 1.0 / layer_repeat[ROCK];
	vec3 blend = triplanar_blend(wn);
	float l = float(ROCK);
	return textureGrad(albedo_height, vec3(pos.zy * inv, l), dpx.zy * inv, dpy.zy * inv) * blend.x
		+ textureGrad(albedo_height, vec3(pos.xz * inv, l), dpx.xz * inv, dpy.xz * inv) * blend.y
		+ textureGrad(albedo_height, vec3(pos.xy * inv, l), dpx.xy * inv, dpy.xy * inv) * blend.z;
}

// Triplanar rock: the world-space normal (whiteout blend per projection) and roughness / AO.
vec3 triplanar_detail(vec3 pos, vec3 dpx, vec3 dpy, vec3 wn, out vec2 ra) {
	float inv = 1.0 / layer_repeat[ROCK];
	vec3 blend = triplanar_blend(wn);
	float l = float(ROCK);
	vec2 rax;
	vec2 ray;
	vec2 raz;
	vec3 nx = unpack_normal(textureGrad(normal_rough_ao, vec3(pos.zy * inv, l), dpx.zy * inv, dpy.zy * inv), rax);
	vec3 ny = unpack_normal(textureGrad(normal_rough_ao, vec3(pos.xz * inv, l), dpx.xz * inv, dpy.xz * inv), ray);
	vec3 nz = unpack_normal(textureGrad(normal_rough_ao, vec3(pos.xy * inv, l), dpx.xy * inv, dpy.xy * inv), raz);
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
	ra = rax * blend.x + ray * blend.y + raz * blend.z;
	return normalize(nx.zyx * blend.x + ny.xzy * blend.y + nz.xyz * blend.z);
}

void fragment() {
	vec2 xz = world_pos.xz;
	vec3 dpx = dFdx(world_pos);
	vec3 dpy = dFdy(world_pos);
	vec3 wn = normalize(world_normal);
	float w[7] = float[7](weights_a.r, weights_a.g, weights_a.b, weights_a.a, weights_b.x, weights_b.y, weights_b.z);
	float far_mix = 0.0;
	if (anti_tiling) {
		far_mix = smoothstep(0.3, 0.7, value_noise(xz * anti_tiling_frequency));
	}
	float far_c = cos(far_rotation);
	float far_s = sin(far_rotation);
	mat2 far_rot = mat2(vec2(far_c, far_s), vec2(-far_s, far_c));
	float tri = 0.0;
	if (triplanar) {
		tri = smoothstep(triplanar_slope - triplanar_band, triplanar_slope + triplanar_band, 1.0 - wn.y);
	}

	// First the albedo / height of every layer with a weight: the heights decide which layers
	// survive the height blending.
	vec4 ah[7];
	float best = -1.0;
	for (int i = 0; i < LAYER_COUNT; i++) {
		ah[i] = vec4(0.0);
		if (w[i] > WEIGHT_EPSILON) {
			if (i != ROCK || tri < 1.0) {
				ah[i] = planar_albedo(planar_coords(i, xz, dpx.xz, dpy.xz, far_rot), far_mix);
			}
			if (i == ROCK && tri > 0.0) {
				ah[i] = mix(ah[i], triplanar_albedo(world_pos, dpx, dpy, wn), tri);
			}
			best = max(best, w[i] + ah[i].a);
		}
	}

	// Height blending: sharp edges where the higher material pokes through. Only the surviving
	// layers (most pixels: one) fetch their normal and roughness / AO.
	vec3 albedo = vec3(0.0);
	vec3 n = vec3(0.0);
	vec2 rough_ao = vec2(0.0);
	float total = 0.0;
	for (int i = 0; i < LAYER_COUNT; i++) {
		if (w[i] > WEIGHT_EPSILON) {
			float hw = max(0.0, w[i] + ah[i].a - best + height_blend);
			if (hw > 0.0) {
				vec3 nt = vec3(0.0, 0.0, 1.0);
				vec2 ra = vec2(1.0);
				if (i != ROCK || tri < 1.0) {
					nt = planar_detail(planar_coords(i, xz, dpx.xz, dpy.xz, far_rot), far_mix, far_rot, ra);
				}
				if (i == ROCK && tri > 0.0) {
					vec2 tra;
					vec3 twn = triplanar_detail(world_pos, dpx, dpy, wn, tra);
					// World normal -> tangent space of this fragment (view-space TBN).
					vec3 v = (VIEW_MATRIX * vec4(twn, 0.0)).xyz;
					nt = mix(nt, vec3(dot(v, TANGENT), dot(v, BINORMAL), dot(v, NORMAL)), tri);
					ra = mix(ra, tra, tri);
				}
				albedo += ah[i].rgb * layer_tint[i] * hw;
				n += nt * hw;
				rough_ao += ra * hw;
				total += hw;
			}
		}
	}
	total = max(total, 1e-5);
	albedo /= total;
	rough_ao /= total;
	n = normalize(vec3(n.xy * normal_strength, max(n.z, 1e-3)));

	if (parcels_on) {
		// World-space derivatives before any divergent branch.
		vec2 xz_m = xz * metres_per_unit;
		vec2 fw_m = fwidth(xz_m);
		vec2 puv = (xz - parcel_rect.xy) * parcel_rect.zw;
		vec4 pm = textureLod(parcel_map, clamp(puv, vec2(0.0), vec2(0.9999)), 0.0);
		int kind = int(pm.r * 255.0 + 0.5);
		if (kind > 0 && kind < PARCEL_KINDS && puv.x >= 0.0 && puv.y >= 0.0 && puv.x < 1.0 && puv.y < 1.0) {
			float g = pm.g * 255.0 + 0.5;
			float rows_along_x = mod(floor(g), 2.0);
			float pid = floor(g * 0.5) / 127.0;
			float across = mix(xz_m.x, xz_m.y, rows_along_x);
			float across_px = mix(fw_m.x, fw_m.y, rows_along_x);
			vec2 row = crop_row[kind];
			float t = across / row.x;
			float ft = across_px / row.x;
			float dist = abs(fract(t) - 0.5) * 2.0;
			float edge = clamp(ft * 2.0, 0.03, 0.5);
			float plant = 1.0 - smoothstep(row.y - edge, row.y + edge, dist);
			plant = mix(plant, row.y, smoothstep(row_fade.x, row_fade.y, ft));
			vec3 crop = mix(crop_furrow[kind], crop_plant[kind], plant);
			// Per-parcel brightness / hue variation and a soft patchiness inside the parcel.
			float hue = (fract(pid * 7.31 + 0.17) * 2.0 - 1.0) * parcel_hue;
			crop *= (1.0 + (pid * 2.0 - 1.0) * parcel_brightness) * vec3(1.0 + hue, 1.0, 1.0 - hue);
			crop *= 1.0 + 0.12 * (value_noise(xz * 9.0) - 0.5);
			// Not on steep, rocky or muddy ground.
			float cover = 1.0 - smoothstep(parcel_slope.x, parcel_slope.y, 1.0 - wn.y);
			cover *= 1.0 - smoothstep(0.2, 0.6, w[3]);
			cover *= 1.0 - smoothstep(0.1, 0.4, w[ROCK]);
			albedo = mix(albedo, crop, cover);
		}
	}

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
