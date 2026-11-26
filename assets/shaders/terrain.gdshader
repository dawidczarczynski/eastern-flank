// Terrain ground (TASK-055, farmland parcels TASK-108f, real-size repeats and detail TASK-134): seven CC0 PBR layers (TerrainTextures, TerrainSplat order: grass,
// dry_grass, dirt, mud, gravel, rock, soil) blended by per-vertex weights – layers 0-3 in COLOR,
// 4-6 in CUSTOM0.xyz (CUSTOM0.w is free for TASK-035). Layers are sampled in world space
// (x, z) / layer_repeat; with anti_tiling a second, larger and rotated sample is mixed in by a
// low-frequency noise; weights are sharpened by the layer heights (height blending); with
// triplanar the rock layer is projected on three axes on steep slopes. UV2 carries the
// per-vertex value / saturation factors (darkened off-map margin, muted backdrop).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://assets/shaders/forest_hash.gdshaderinc"
#include "res://assets/shaders/cloud_shadow.gdshaderinc"
#include "res://assets/shaders/satellite_colour.gdshaderinc"

const int LAYER_COUNT = 7;
const int ROCK = 5;
// Farmland parcels (TASK-108f): kinds of FieldParcels.Kind, 10 entries (none, 7 crops, balk, rape).
const int PARCEL_KINDS = 10;
// Layers below this weight are not sampled.
const float WEIGHT_EPSILON = 0.004;

uniform sampler2DArray albedo_height : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Normal x, y (OpenGL, z is rebuilt) in RG, roughness in B, ambient occlusion in A. Trilinear:
// anisotropic filtering only pays on the albedo (~0.35 ms on the target GPU for no visible gain).
uniform sampler2DArray normal_rough_ao : hint_default_white, filter_linear_mipmap, repeat_enable;
// World units per texture repeat, and a linear albedo tint, per layer. layer_repeat is the layer's
// real size (TASK-134), shown close up; farther than scale_fade (view distance, world units) it
// cross-fades to layer_repeat_far, the larger pattern that still reads from the default zoom.
uniform float layer_repeat[7];
uniform float layer_repeat_far[7];
uniform vec2 scale_fade = vec2(2.5, 6.0);
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
// Ground detail (TASK-134, TerrainGround.detail_texture): normal (RGB) + height (A), one repeat per
// detail_repeat world units plus a rotated sample at detail_second x that size; faded in by view
// distance: full below detail_fade.x, none beyond detail_fade.y (world units).
uniform bool detail_on = true;
uniform sampler2D detail_map : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float detail_repeat = 0.0624;
uniform float detail_second = 0.27;
uniform vec2 detail_fade = vec2(4.0, 6.0);
// Albedo brightness +- detail_albedo, a drier tint where the second sample is high, and the
// normal tilt of the detail at full strength.
uniform float detail_albedo = 0.3;
uniform vec3 detail_dry = vec3(1.1, 1.0, 0.78);
uniform float detail_normal = 0.7;
// Grass tone (TASK-217b, TerrainGround.set_grass_tone; `true` preset only, off otherwise): on grass
// ground (grass and dry-grass layers, no crop) beyond the GPU grass ring a cheap grass-coloured
// mottle replaces the clumps: it ramps in over grass_tone_ramp (view distance, world units: none
// below x, full beyond y), the mottle pulls the colour towards grass_tone_colour by grass_tone_mix
// and varies the brightness by +-grass_tone_contrast at two scales (grass_tone_cells, metres),
// each faded out once a pixel covers half of its cell.
uniform bool grass_tone_on = false;
uniform vec2 grass_tone_ramp = vec2(10.0, 50.0);
uniform vec3 grass_tone_colour = vec3(0.9, 1.06, 0.86);
uniform float grass_tone_mix = 0.5;
uniform float grass_tone_contrast = 0.18;
uniform vec2 grass_tone_cells = vec2(1.2, 6.0);
// Lake and river beds darken with depth below the water level.
uniform float water_level = 0.0;
uniform float bed_darkening = 0.6;
uniform float bed_depth = 0.6;

// Farmland parcel map (FieldParcels.bake, RG8): kind in red, parcel id * 2 + row orientation
// (1 = rows run along x) in green. With real parcels (TASK-215b, RGB8) blue > 0 marks a real
// parcel: blue - 1 is its row direction (FieldParcels.angle_code) and the land cover masks it by
// COVER_PARCEL_MASK instead of the FIELD outline. parcel_rect = (x, z, 1 / width, 1 / height) in world units.
// Off (the default battle) when the map has no fields.
uniform bool parcels_on = false;
// Real parcels (TASK-215b): the exact edges (RealParcels.edge_image, RGB8 like parcel_map): per
// texel near an edge its line (red: 1 + angle code, green: signed distance of the texel centre,
// +-PARCEL_EDGE_RANGE_M metres over the coarser PARCEL_EDGE_TEXEL texels, blue: 1 + edge kind), so edges are the straight polygon edges at
// every zoom instead of 5 m texel steps; balk half width (metres) per blue code.
uniform bool parcel_edges_on = false;
uniform sampler2D parcel_edges : filter_nearest, repeat_disable, hint_default_black;
uniform vec4 parcel_balk_half_m = vec4(0.0, 0.0, 3.5, 5.0);
// Real parcels (TASK-215b) show: on a real parcel the satellite layer only lends this share of its
// hue (at the crop's own luminance) at every distance instead of taking over far away, so the
// parcels keep their edges and contrast (RealParcelLook.satellite_hue).
uniform bool parcel_real = false;
uniform float parcel_satellite_hue = 0.15;
// Per kind: coarse stripes along the rows (period in m, brightness swing; CropKind.stripe_m).
uniform vec2 crop_stripe[10];
// RealParcels.EDGE_TEXEL / EDGE_RANGE_M.
const float PARCEL_EDGE_TEXEL = 2.0;
const float PARCEL_EDGE_RANGE_M = 15.0;
uniform sampler2D parcel_map : filter_nearest, repeat_disable, hint_default_black;
uniform vec4 parcel_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Metres per parcel map texel.
uniform float parcel_mpp = 5.0;
uniform float metres_per_unit = 144.34;
// Per kind: plant and furrow colour (linear) and (row spacing in m, plant width fraction).
uniform vec3 crop_plant[10];
uniform vec3 crop_furrow[10];
uniform vec2 crop_row[10];
uniform float parcel_brightness = 0.12;
uniform float parcel_hue = 0.07;
// Rows fade to the average colour as one row spans this many pixels (from .. to).
uniform vec2 row_fade = vec2(0.3, 0.8);
// Parcels fade out on ground steeper than this slope (1 - normal.y), from .. to.
uniform vec2 parcel_slope = vec2(0.08, 0.14);
// `true` farmland look (TASK-200, CropLook twins; off for `balanced`: nothing below runs). Per kind
// the harvest-state colour (linear) and whether the parcel keeps the ground (grass) look.
uniform bool crop_true = false;
uniform vec3 crop_harvest[10];
uniform float crop_ground[10];
// Satellite tint share and the mip level that reads the layer over about one parcel.
uniform float crop_tint = 0.5;
uniform float crop_tint_lod = 4.0;
uniform float crop_saturation = 1.2;
// Mottling inside a parcel: strength and noise frequency (per world unit, period >= 20 m).
uniform float crop_mottle = 0.2;
uniform float crop_mottle_frequency = 2.0;
uniform float harvest_share = 0.3;
// Rows full below .x and gone from .y (camera distance in metres).
uniform vec2 row_distance_m = vec2(50.0, 150.0);
// Headland: width in parcel-map uv (x, z), brightness factor, and the camera distance (m) it fades by.
uniform vec2 headland_uv = vec2(0.0);
uniform float headland_dark = 0.78;
// The headland width in metres (real parcels: measured from the exact edge).
uniform float headland_m = 6.0;
uniform float headland_fade_m = 300.0;

// Land-cover raster (TASK-108g, ADR 0028; CoverLook): with cover_on the crops show only inside the
// noisy outline of the FIELD cover, the GLSL twin of CoverLook.has_kind(FIELD) (same integer
// hashes, ScatterPlanner.tile_seed via forest_hash.gdshaderinc). land_cover holds the raw Kind
// codes (R8); cover_frame = (x, z of the centre of cell (0, 0), cell size, unused).
uniform bool cover_on = false;
uniform sampler2D land_cover : filter_nearest, repeat_disable, hint_default_black;
uniform vec4 cover_frame = vec4(0.0, 0.0, 1.0, 0.0);
// CoverLook constants (tests/unit/test_cover_look.gd compares them).
const int COVER_FIELD = 2;
// CoverLook.PARCEL_KINDS_MASK: the kinds a real parcel (TASK-215b) shows on.
const int COVER_PARCEL_MASK = 903;
const float COVER_NOISE_CELLS = 2.5;
const float COVER_NOISE_FINE_CELLS = 0.9;
const float COVER_NOISE_AMPLITUDE = 0.6;
const float COVER_NOISE_FINE_AMPLITUDE = 0.3;
const uint COVER_NOISE_SALT = 4234u; // 0x108A
const uint COVER_FINE_SALT = 4235u; // 0x108B

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

// CoverLook._lattice / _value_noise: integer-hashed lattice values, smoothly interpolated.
float cover_lattice(ivec2 c, uint salt) {
	uint h = forest_tile_seed(salt, c, COVER_NOISE_SALT);
	return float(h & 16777215u) / 16777216.0;
}

float cover_value_noise(vec2 p, float spacing, uint salt) {
	vec2 q = p / spacing;
	vec2 i = floor(q);
	vec2 f = q - i;
	f = f * f * (3.0 - 2.0 * f);
	ivec2 c = ivec2(i);
	float a = mix(cover_lattice(c, salt), cover_lattice(c + ivec2(1, 0), salt), f.x);
	float b = mix(cover_lattice(c + ivec2(0, 1), salt), cover_lattice(c + ivec2(1, 1), salt), f.x);
	return mix(a, b, f.y);
}

// CoverLook.kinds_weight / has_kind for the cover Kinds whose bits (1 << Kind) are set in `mask`:
// inside their noisy outline. Beyond the raster the OPEN bit decides (CoverLook.world_rect).
bool in_cover(vec2 xz, int mask) {
	ivec2 size = textureSize(land_cover, 0);
	float cell = cover_frame.z;
	vec2 raw = (xz - cover_frame.xy) / cell;
	if (any(lessThan(raw, vec2(-0.5))) || any(greaterThanEqual(raw, vec2(size) - 0.5))) {
		return (mask & 1) != 0;
	}
	vec2 uv = clamp(raw, vec2(0.0), vec2(size - 1));
	ivec2 i = min(ivec2(floor(uv)), size - 1);
	vec2 f = uv - vec2(i);
	ivec2 j = min(i + 1, size - 1);
	float w = 0.0;
	w += ((mask >> int(texelFetch(land_cover, i, 0).r * 255.0 + 0.5)) & 1) != 0 ? (1.0 - f.x) * (1.0 - f.y) : 0.0;
	w += ((mask >> int(texelFetch(land_cover, ivec2(j.x, i.y), 0).r * 255.0 + 0.5)) & 1) != 0 ? f.x * (1.0 - f.y) : 0.0;
	w += ((mask >> int(texelFetch(land_cover, ivec2(i.x, j.y), 0).r * 255.0 + 0.5)) & 1) != 0 ? (1.0 - f.x) * f.y : 0.0;
	w += ((mask >> int(texelFetch(land_cover, j, 0).r * 255.0 + 0.5)) & 1) != 0 ? f.x * f.y : 0.0;
	if (w <= 0.0 || w >= 1.0) {
		return w > 0.5;
	}
	float noise = (cover_value_noise(xz, cell * COVER_NOISE_CELLS, COVER_NOISE_SALT) - 0.5) * COVER_NOISE_AMPLITUDE
		+ (cover_value_noise(xz, cell * COVER_NOISE_FINE_CELLS, COVER_FINE_SALT) - 0.5) * COVER_NOISE_FINE_AMPLITUDE;
	return w + noise > 0.5;
}

// CoverLook.has_kind(FIELD, x, z).
bool in_field_cover(vec2 xz) {
	return in_cover(xz, 1 << COVER_FIELD);
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

Planar planar_coords(int layer, float repeat, vec2 xz, vec2 dx, vec2 dy, mat2 far_rot) {
	float inv = 1.0 / repeat;
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
vec4 triplanar_albedo(float repeat, vec3 pos, vec3 dpx, vec3 dpy, vec3 wn) {
	float inv = 1.0 / repeat;
	vec3 blend = triplanar_blend(wn);
	float l = float(ROCK);
	return textureGrad(albedo_height, vec3(pos.zy * inv, l), dpx.zy * inv, dpy.zy * inv) * blend.x
		+ textureGrad(albedo_height, vec3(pos.xz * inv, l), dpx.xz * inv, dpy.xz * inv) * blend.y
		+ textureGrad(albedo_height, vec3(pos.xy * inv, l), dpx.xy * inv, dpy.xy * inv) * blend.z;
}

// Triplanar rock: the world-space normal (whiteout blend per projection) and roughness / AO.
vec3 triplanar_detail(float repeat, vec3 pos, vec3 dpx, vec3 dpy, vec3 wn, out vec2 ra) {
	float inv = 1.0 / repeat;
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

// ParcelMap.label_at_metres: the parcel map's texel at `puv` (`pm`, already sampled), or next to
// a real parcel edge the texel 1.5 texels beyond the exact edge line on the point's side, BALK
// within the balk half width of a track / hedge edge. `edge_m`: metres from the edge (beyond its
// balk), large when no edge is near.
vec4 parcel_label(vec2 puv, vec4 pm, out float edge_m) {
	edge_m = 1e6;
	ivec2 size = textureSize(parcel_map, 0);
	ivec2 e_size = textureSize(parcel_edges, 0);
	vec2 p = clamp(puv, vec2(0.0), vec2(0.9999)) * vec2(size) * parcel_mpp;
	float edge_mpp = parcel_mpp * PARCEL_EDGE_TEXEL;
	ivec2 i = clamp(ivec2(floor(p / edge_mpp)), ivec2(0), e_size - 1);
	vec4 e = texelFetch(parcel_edges, i, 0);
	float code = floor(e.r * 255.0 + 0.5);
	if (code < 0.5) {
		return pm;
	}
	float a = (code - 0.5) / 254.0 * PI;
	vec2 normal_dir = vec2(-sin(a), cos(a));
	float d = dot(p - (vec2(i) + 0.5) * edge_mpp, normal_dir) + (e.g * 2.0 - 1.0) * PARCEL_EDGE_RANGE_M;
	float side = d >= 0.0 ? 1.0 : -1.0;
	vec2 q_m = p - normal_dir * d + normal_dir * side * 1.5 * parcel_mpp;
	ivec2 q = clamp(ivec2(floor(q_m / parcel_mpp)), ivec2(0), size - 1);
	vec4 label = texelFetch(parcel_map, q, 0);
	int kind = int(e.b * 255.0 + 0.5);
	float half_m = parcel_balk_half_m[clamp(kind, 0, 3)];
	edge_m = abs(d) - half_m;
	if (abs(d) < half_m) {
		label = vec4(8.0 / 255.0, label.g, max(label.b, 1.0 / 255.0), label.a);
	}
	return label;
}

// 1 when the parcel map holds a balk (kind 8) at `puv`, else 0 (the headland lies next to it).
float parcel_balk(vec2 puv) {
	float k = textureLod(parcel_map, clamp(puv, vec2(0.0), vec2(0.9999)), 0.0).r * 255.0;
	return step(7.5, k) * step(k, 8.5);
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
	// Real-size texture close up, the far pattern beyond (both only inside the cross-fade band).
	float view_distance = length(world_pos - CAMERA_POSITION_WORLD);
	float scale_far = smoothstep(scale_fade.x, scale_fade.y, view_distance);
	// Satellite colour layer (TASK-192b): sampled here, in uniform control flow.
	vec4 satellite = vec4(0.0);
	if (satellite_on) {
		satellite = satellite_sample(xz);
	}

	// First the albedo / height of every layer with a weight: the heights decide which layers
	// survive the height blending.
	vec4 ah[7];
	float best = -1.0;
	for (int i = 0; i < LAYER_COUNT; i++) {
		ah[i] = vec4(0.0);
		if (w[i] > WEIGHT_EPSILON) {
			for (int s = 0; s < 2; s++) {
				float f = s == 0 ? 1.0 - scale_far : scale_far;
				if (f > 0.0) {
					float repeat = s == 0 ? layer_repeat[i] : layer_repeat_far[i];
					vec4 one = vec4(0.0);
					if (i != ROCK || tri < 1.0) {
						one = planar_albedo(planar_coords(i, repeat, xz, dpx.xz, dpy.xz, far_rot), far_mix);
					}
					if (i == ROCK && tri > 0.0) {
						one = mix(one, triplanar_albedo(repeat, world_pos, dpx, dpy, wn), tri);
					}
					ah[i] += one * f;
				}
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
				vec3 nt = vec3(0.0);
				vec2 ra = vec2(0.0);
				for (int s = 0; s < 2; s++) {
					float f = s == 0 ? 1.0 - scale_far : scale_far;
					if (f > 0.0) {
						float repeat = s == 0 ? layer_repeat[i] : layer_repeat_far[i];
						vec3 one = vec3(0.0, 0.0, 1.0);
						vec2 one_ra = vec2(1.0);
						if (i != ROCK || tri < 1.0) {
							one = planar_detail(planar_coords(i, repeat, xz, dpx.xz, dpy.xz, far_rot), far_mix, far_rot, one_ra);
						}
						if (i == ROCK && tri > 0.0) {
							vec2 tra;
							vec3 twn = triplanar_detail(repeat, world_pos, dpx, dpy, wn, tra);
							// World normal -> tangent space of this fragment (view-space TBN).
							vec3 v = (VIEW_MATRIX * vec4(twn, 0.0)).xyz;
							one = mix(one, vec3(dot(v, TANGENT), dot(v, BINORMAL), dot(v, NORMAL)), tri);
							one_ra = mix(one_ra, tra, tri);
						}
						nt += one * f;
						ra += one_ra * f;
					}
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

	// How much of the colour is a real parcel's own (parcel_satellite_hue applies there).
	float parcel_keep = 0.0;
	// How much a crop parcel covers the grass ground here (the grass tone stays off it).
	float crop_cover = 0.0;
	if (parcels_on) {
		// World-space derivatives before any divergent branch.
		vec2 xz_m = xz * metres_per_unit;
		vec2 fw_m = fwidth(xz_m);
		vec2 puv = (xz - parcel_rect.xy) * parcel_rect.zw;
		vec4 pm = textureLod(parcel_map, clamp(puv, vec2(0.0), vec2(0.9999)), 0.0);
		float edge_m = 1e6;
		if (parcel_edges_on) {
			pm = parcel_label(puv, pm, edge_m);
		}
		int kind = int(pm.r * 255.0 + 0.5);
		float angle_code = floor(pm.b * 255.0 + 0.5);
		bool real_parcel = angle_code > 0.5;
		if (cover_on && kind > 0 && !(real_parcel ? in_cover(xz, COVER_PARCEL_MASK) : in_field_cover(xz))) {
			kind = 0;
		}
		if (kind > 0 && kind < PARCEL_KINDS && puv.x >= 0.0 && puv.y >= 0.0 && puv.x < 1.0 && puv.y < 1.0) {
			float g = pm.g * 255.0 + 0.5;
			float rows_along_x = mod(floor(g), 2.0);
			float pid = floor(g * 0.5) / 127.0;
			float across = mix(xz_m.x, xz_m.y, rows_along_x);
			float across_px = mix(fw_m.x, fw_m.y, rows_along_x);
			if (real_parcel) {
				// FieldParcels.code_angle: rows along (cos a, sin a), measured across them.
				float a = (angle_code - 0.5) / 254.0 * PI;
				vec2 normal_dir = vec2(-sin(a), cos(a));
				across = dot(xz_m, normal_dir);
				across_px = abs(normal_dir.x) * fw_m.x + abs(normal_dir.y) * fw_m.y;
			}
			vec2 row = crop_row[kind];
			float t = across / row.x;
			float ft = across_px / row.x;
			float dist = abs(fract(t) - 0.5) * 2.0;
			float edge = clamp(ft * 2.0, 0.03, 0.5);
			float plant = 1.0 - smoothstep(row.y - edge, row.y + edge, dist);
			plant = mix(plant, row.y, smoothstep(row_fade.x, row_fade.y, ft));
			vec3 plant_colour = crop_plant[kind];
			vec3 furrow_colour = crop_furrow[kind];
			float view_m = view_distance * metres_per_unit;
			bool is_balk = kind == 8;
			if (crop_true) {
				// Rows only up to row_distance_m (no moire), the harvest-state tone on a share of
				// the parcels of each kind.
				plant = mix(row.y, plant, 1.0 - smoothstep(row_distance_m.x, row_distance_m.y, view_m));
				if (!is_balk && fract(pid * 13.7 + 0.31) < harvest_share) {
					plant_colour = mix(plant_colour, crop_harvest[kind], 0.85);
					furrow_colour = mix(furrow_colour, crop_harvest[kind] * 0.85, 0.85);
				}
			}
			vec3 crop = mix(furrow_colour, plant_colour, plant);
			// Per-parcel brightness / hue variation and a soft patchiness inside the parcel.
			float hue = (fract(pid * 7.31 + 0.17) * 2.0 - 1.0) * parcel_hue;
			crop *= (1.0 + (pid * 2.0 - 1.0) * parcel_brightness) * vec3(1.0 + hue, 1.0, 1.0 - hue);
			if (crop_true) {
				// Stronger colour, tinted towards the satellite layer at the parcel's own scale,
				// mottled by a large-scale noise, a darker headland strip next to the balks.
				crop = mix(vec3(dot(crop, vec3(0.2126, 0.7152, 0.0722))), crop, crop_saturation);
				vec2 stripe = crop_stripe[kind];
				float stripe_w = across_px / max(stripe.x, 1e-3);
				if (stripe.x > 0.0 && !is_balk && stripe_w < 0.5) {
					// Coarse stripes along the rows (tramlines, swaths), faded where under ~2 px.
					float wave = abs(fract(across / stripe.x) - 0.5) * 2.0;
					float band = smoothstep(0.55 - stripe_w, 0.55 + stripe_w, wave);
					float keep = 1.0 - smoothstep(0.25, 0.5, stripe_w);
					crop *= 1.0 + stripe.y * (2.0 * band - 1.0) * keep;
				}
				if (satellite_on && !is_balk) {
					vec2 suv = (xz - satellite_rect.xy) * satellite_rect.zw;
					vec3 layer = textureLod(satellite_map, clamp(suv, vec2(0.0), vec2(1.0)), crop_tint_lod).rgb;
					crop = mix(crop, satellite_hue(crop, layer), crop_tint * satellite.a);
				}
				float mottle = value_noise(xz * crop_mottle_frequency) * 0.65 + value_noise(xz * crop_mottle_frequency * 2.3 + 11.0) * 0.35;
				crop *= 1.0 + crop_mottle * (2.0 * mottle - 1.0);
				if (!is_balk && view_m < headland_fade_m) {
					float next_to_balk = 0.0;
					if (real_parcel) {
						// Along every exact edge of a real parcel (plain edges too).
						next_to_balk = edge_m < headland_m ? 1.0 : 0.0;
					} else {
						next_to_balk = max(
								max(parcel_balk(puv + vec2(headland_uv.x, 0.0)), parcel_balk(puv - vec2(headland_uv.x, 0.0))),
								max(parcel_balk(puv + vec2(0.0, headland_uv.y)), parcel_balk(puv - vec2(0.0, headland_uv.y))));
					}
					float fade = 1.0 - smoothstep(0.5 * headland_fade_m, headland_fade_m, view_m);
					crop *= mix(1.0, headland_dark, next_to_balk * fade);
				}
			} else {
				crop *= 1.0 + 0.12 * (value_noise(xz * 9.0) - 0.5);
			}
			// Not on steep, rocky or muddy ground.
			float cover = 1.0 - smoothstep(parcel_slope.x, parcel_slope.y, 1.0 - wn.y);
			cover *= 1.0 - smoothstep(0.2, 0.6, w[3]);
			cover *= 1.0 - smoothstep(0.1, 0.4, w[ROCK]);
			// Meadow / fallow keep the grass ground look under the `true` look.
			if (crop_true && crop_ground[kind] > 0.5) {
				cover = 0.0;
			}
			albedo = mix(albedo, crop, cover);
			crop_cover = cover;
			if (real_parcel && parcel_real) {
				parcel_keep = cover;
			}
		}
	}

	// Ground detail close to the camera (explicit gradients: the branch is not uniform).
	if (detail_on) {
		float detail = 1.0 - smoothstep(detail_fade.x, detail_fade.y, view_distance);
		if (detail > 0.0) {
			float inv = 1.0 / detail_repeat;
			float inv2 = inv / detail_second;
			vec4 d1 = textureGrad(detail_map, xz * inv, dpx.xz * inv, dpy.xz * inv);
			vec4 d2 = textureGrad(detail_map, far_rot * xz * inv2, far_rot * dpx.xz * inv2, far_rot * dpy.xz * inv2);
			float h = (d1.a + d2.a) * 0.5;
			albedo *= 1.0 + detail_albedo * detail * (2.0 * h - 1.0);
			albedo *= mix(vec3(1.0), detail_dry, smoothstep(0.45, 0.85, d2.a) * detail);
			vec2 tilt = (d1.rg * 2.0 - 1.0) + far_rot * (d2.rg * 2.0 - 1.0);
			n = normalize(vec3(n.xy + tilt * detail_normal * detail, n.z));
		}
	}

	// Macro brightness, then the per-vertex value / saturation (off-map margin, backdrop).
	float macro = value_noise(xz * macro_frequency) * 0.65 + value_noise(xz * macro_frequency * 2.7 + 17.0) * 0.35;
	albedo *= 1.0 + macro_brightness * (2.0 * macro - 1.0);
	// Satellite colour: a luminance-preserving tint near the camera, the layer itself far away.
	if (satellite_on) {
		vec3 ground_colour = satellite_ground(albedo, satellite, view_distance);
		if (parcel_keep > 0.0) {
			// A real parcel keeps its own colour and edges; the 10 m layer would blur them.
			vec3 own = mix(albedo, satellite_hue(albedo, satellite.rgb), parcel_satellite_hue * satellite.a);
			albedo = mix(ground_colour, own, parcel_keep);
		} else {
			albedo = ground_colour;
		}
	}
	if (grass_tone_on) {
		float ramp = smoothstep(grass_tone_ramp.x, grass_tone_ramp.y, view_distance);
		float grassy = clamp(w[0] + w[1], 0.0, 1.0) * (1.0 - crop_cover);
		float foot_m = length(fwidth(xz)) * metres_per_unit;
		vec2 cells_u = grass_tone_cells / metres_per_unit;
		float coarse = value_noise(xz / cells_u.y);
		float fine = value_noise(xz / cells_u.x);
		float fine_k = 1.0 - smoothstep(0.25, 0.5, foot_m / grass_tone_cells.x);
		float coarse_k = 1.0 - smoothstep(0.25, 0.5, foot_m / grass_tone_cells.y);
		float mottle = (2.0 * coarse - 1.0) * coarse_k * 0.6 + (2.0 * fine - 1.0) * fine_k * 0.4;
		vec3 toned = albedo * (1.0 + grass_tone_contrast * mottle);
		toned = mix(toned, toned * grass_tone_colour, grass_tone_mix);
		albedo = mix(albedo, toned, ramp * grassy);
	}
	float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = mix(vec3(lum), albedo, vertex_tint.y) * vertex_tint.x;
	albedo *= mix(1.0, 1.0 - bed_darkening, smoothstep(0.0, bed_depth, water_level - world_pos.y));

	albedo *= cloud_shadow_factor(xz);
	ALBEDO = albedo;
	ROUGHNESS = mix(roughness_min, 1.0, rough_ao.x);
	SPECULAR = specular;
	AO = mix(1.0, rough_ao.y, ao_strength);
	NORMAL = normalize(TANGENT * n.x + BINORMAL * n.y + NORMAL * n.z);
}
