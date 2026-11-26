// Where the shrubs of the real-scale countryside grow (TASK-217a, ADR 0033): the GLSL twin of
// ShrubRules (src/presentation/shrub_rules.gd, the reference the tests use), shared by
// shrub_impostor.gdshader and shrub_mesh.gdshader. A shrub is a pure function of its grid cell
// (vegetation_hash.gdshaderinc) and the map textures ShrubRules.bind / ShrubField bind once per
// map: the habitat codes and the blurred forest stand (VegetationMasks), the parcels (ParcelMap),
// the drawn lattice heights. tests/unit/test_shrub_rules.gd checks the constants below against
// the GDScript ones; the tables are uniforms. Change both together.

#include "res://assets/shaders/vegetation_hash.gdshaderinc"

const uint SHRUB_POINT_SALT = 23297u; // 0x5B01
const uint SHRUB_VALUE_SALT = 23298u; // 0x5B02
const uint SHRUB_NOISE_SALT = 23299u; // 0x5B03
const uint SHRUB_VARIANT_SALT = 23300u; // 0x5B04
const int SHRUB_PART_CHANCE = 0;
const int SHRUB_PART_KIND = 1;
const int SHRUB_PART_HEIGHT = 2;
const int SHRUB_PART_WIDTH = 3;
const int SHRUB_PART_YAW = 4;
const int SHRUB_PART_HUE = 5;
const int SHRUB_PART_VALUE = 6;
const int SHRUB_PART_PHASE = 7;
const float SHRUB_JITTER = 0.8;
const int SHRUB_EDGE_FROM = 8;
const int SHRUB_EDGE_TO = 247;
const int SHRUB_PARCEL_NONE = 0;
const int SHRUB_PARCEL_MEADOW = 7;
const int SHRUB_PARCEL_BALK = 8;
const int SHRUB_CROP_NONE = 0;
const int SHRUB_CROP_FIELD = 1;
const int SHRUB_CROP_BALK = 2;
// VegetationMasks parcel flags and code mask.
const int SHRUB_NO_REAL_PARCEL = 128;
const int SHRUB_NO_STRIP_PARCEL = 64;
const int SHRUB_CODE_MASK = 63;
const float SHRUB_HEATH_NOISE_MIN = 0.2;
const float SHRUB_HEATH_NOISE_SPAN = 1.6;
const float SHRUB_MEADOW_NOISE_FROM = 0.55;
const float SHRUB_MEADOW_NOISE_TO = 0.85;
const float SHRUB_HUE_SHIFT = 0.03;
const float SHRUB_VALUE_MIN = 0.85;
const float SHRUB_VALUE_MAX = 1.1;
const int SHRUB_VARIANTS = 3;
// VegetationMasks.Habitat codes.
const int SHRUB_CODE_FIELD_EDGE = 1;
const int SHRUB_CODE_HEATH = 2;
const int SHRUB_CODE_BANK = 3;
const int SHRUB_CODE_HEDGE = 4;
const int SHRUB_CODE_KEEP_OFF = 255;
// ShrubRules.Habitat
const int SHRUB_NONE = 0;
const int SHRUB_FOREST_EDGE = 1;
const int SHRUB_HEDGE = 2;
const int SHRUB_BANK = 3;
const int SHRUB_HEATH = 4;
const int SHRUB_FIELD_EDGE = 5;
const int SHRUB_MEADOW = 6;

// Every uniform below is set by ShrubRules.bind / VegetationMasks.bind / ShrubField.
uniform uint shrub_seed;
uniform float spacing;
uniform float noise_wavelength;
uniform float parcel_strip;
uniform float near_chunk;
uniform float min_ground;
uniform float metres_per_unit;
uniform float habitat_chance[7];
uniform vec4 kind_shares[7];
// Height range (world units) and crown width over height per kind; linear leaf colour per kind.
uniform vec2 kind_heights[4];
uniform float kind_width_share[4];
uniform vec3 kind_colors[4];
uniform sampler2D habitat : filter_nearest, repeat_disable;
uniform sampler2D forest_edge : filter_nearest, repeat_disable;
// The masks' area (x0, z0, x1, z1) and texels per unit.
uniform vec4 mask_area;
uniform float mask_per_unit;
uniform bool use_parcels;
uniform sampler2D parcels : filter_nearest, repeat_disable;
uniform vec2 parcel_origin_m;
uniform float parcel_metres_per_pixel;
// The lattice: heights of (height_cells + 1)^2 vertices from height_origin, height_step apart.
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform vec2 height_origin;
uniform float height_step;
uniform ivec2 height_cells;
uniform float water_surface;

// The drawn near terrain around the camera target (NearHeightCache): heights of the near mesh's
// vertices, near_step apart from near_origin; MISSING (< -1e5) where no near chunk is built.
uniform bool use_near = false;
uniform sampler2D near_heights : filter_nearest, repeat_disable;
uniform vec2 near_origin;
uniform float near_step = 1.0;

// TerrainLattice.mesh_height_at (as forest_impostor.gdshader).
float shrub_lattice_height(vec2 p) {
	float fx = clamp((p.x - height_origin.x) / height_step, 0.0, float(height_cells.x));
	float fz = clamp((p.y - height_origin.y) / height_step, 0.0, float(height_cells.y));
	int i = min(int(floor(fx)), height_cells.x - 1);
	int j = min(int(floor(fz)), height_cells.y - 1);
	float u = fx - float(i);
	float v = fz - float(j);
	float ha = texelFetch(heights, ivec2(i, j), 0).r;
	float hb = texelFetch(heights, ivec2(i + 1, j), 0).r;
	float hc = texelFetch(heights, ivec2(i, j + 1), 0).r;
	float h;
	if (u + v <= 1.0) {
		h = ha + u * (hb - ha) + v * (hc - ha);
	} else {
		float hd = texelFetch(heights, ivec2(i + 1, j + 1), 0).r;
		h = hd + (1.0 - u) * (hc - hd) + (1.0 - v) * (hb - hd);
	}
	return max(h, water_surface);
}

// The drawn ground under p (NearHeightCache.height_at): the near mesh's triangles where a near
// chunk is built, else `lattice` (the lattice height, what is drawn there). Drawing only: the
// placement decisions read the lattice.
float shrub_drawn_ground(vec2 p, float lattice) {
	if (!use_near) {
		return lattice;
	}
	vec2 f = (p - near_origin) / near_step;
	ivec2 i = ivec2(floor(f));
	ivec2 size = textureSize(near_heights, 0);
	if (i.x < 0 || i.y < 0 || i.x + 1 >= size.x || i.y + 1 >= size.y) {
		return lattice;
	}
	float ha = texelFetch(near_heights, i, 0).r;
	float hb = texelFetch(near_heights, i + ivec2(1, 0), 0).r;
	float hc = texelFetch(near_heights, i + ivec2(0, 1), 0).r;
	float hd = texelFetch(near_heights, i + ivec2(1, 1), 0).r;
	if (min(min(ha, hb), min(hc, hd)) < -1.0e5) {
		return lattice;
	}
	float u = f.x - float(i.x);
	float v = f.y - float(i.y);
	if (u + v <= 1.0) {
		return ha + u * (hb - ha) + v * (hc - ha);
	}
	return hd + (1.0 - u) * (hc - hd) + (1.0 - v) * (hb - hd);
}

// ShrubRules.point
vec2 shrub_point(ivec2 cell) {
	return veg_point(veg_cell_hash(shrub_seed, cell, SHRUB_POINT_SALT), cell, spacing, SHRUB_JITTER);
}

// VegetationMasks.texel: (-1, -1) outside the masks.
ivec2 shrub_texel(vec2 p) {
	ivec2 t = ivec2(floor((p - mask_area.xy) * mask_per_unit));
	ivec2 size = textureSize(habitat, 0);
	if (t.x < 0 || t.y < 0 || t.x >= size.x || t.y >= size.y) {
		return ivec2(-1);
	}
	return t;
}

// ShrubRules._crop_at: a crop (1), a balk (2) or nothing (0: unpainted, a meadow parcel, or a
// parcel texel where the land cover carries no parcel – the habitat texel's flags).
int shrub_crop(vec2 p) {
	ivec2 q = ivec2(floor((p * metres_per_unit - parcel_origin_m) / parcel_metres_per_pixel));
	ivec2 parcel_size = textureSize(parcels, 0);
	if (q.x < 0 || q.y < 0 || q.x >= parcel_size.x || q.y >= parcel_size.y) {
		return SHRUB_CROP_NONE;
	}
	vec4 texel = texelFetch(parcels, q, 0);
	int kind = int(round(texel.r * 255.0));
	if (kind == SHRUB_PARCEL_NONE || kind == SHRUB_PARCEL_MEADOW) {
		return SHRUB_CROP_NONE;
	}
	int flag = texel.b > 0.0 ? SHRUB_NO_REAL_PARCEL : SHRUB_NO_STRIP_PARCEL;
	ivec2 t = shrub_texel(p);
	int byte_value = t.x < 0 ? SHRUB_CODE_KEEP_OFF : int(round(texelFetch(habitat, t, 0).r * 255.0));
	if ((byte_value & flag) != 0) {
		return SHRUB_CROP_NONE;
	}
	return kind == SHRUB_PARCEL_BALK ? SHRUB_CROP_BALK : SHRUB_CROP_FIELD;
}

// ShrubRules.habitat_at
int shrub_habitat(vec2 p) {
	ivec2 t = shrub_texel(p);
	if (t.x < 0) {
		return SHRUB_NONE;
	}
	int byte_value = int(round(texelFetch(habitat, t, 0).r * 255.0));
	if (byte_value == SHRUB_CODE_KEEP_OFF) {
		return SHRUB_NONE;
	}
	int code = byte_value & SHRUB_CODE_MASK;
	bool field_edge = false;
	if (use_parcels) {
		int parcel = shrub_crop(p);
		if (parcel == SHRUB_CROP_BALK) {
			field_edge = true;
		} else if (parcel == SHRUB_CROP_FIELD) {
			vec2 offsets[4] = vec2[](
				vec2(parcel_strip, 0.0), vec2(-parcel_strip, 0.0), vec2(0.0, parcel_strip),
				vec2(0.0, -parcel_strip)
			);
			for (int k = 0; k < 4 && !field_edge; k++) {
				field_edge = shrub_crop(p + offsets[k]) != SHRUB_CROP_FIELD;
			}
			if (!field_edge) {
				return SHRUB_NONE;
			}
		}
	}
	int forest = int(round(texelFetch(forest_edge, t, 0).r * 255.0));
	if (forest >= SHRUB_EDGE_TO) {
		return SHRUB_NONE;
	}
	if (forest >= SHRUB_EDGE_FROM) {
		return SHRUB_FOREST_EDGE;
	}
	if (code == SHRUB_CODE_HEDGE) {
		return SHRUB_HEDGE;
	}
	if (code == SHRUB_CODE_BANK) {
		return SHRUB_BANK;
	}
	if (code == SHRUB_CODE_HEATH) {
		return SHRUB_HEATH;
	}
	if (field_edge || code == SHRUB_CODE_FIELD_EDGE) {
		return SHRUB_FIELD_EDGE;
	}
	return SHRUB_MEADOW;
}

// ShrubRules.chance
float shrub_chance(int kind_of_habitat, vec2 p) {
	float base = habitat_chance[kind_of_habitat];
	if (kind_of_habitat == SHRUB_HEATH || kind_of_habitat == SHRUB_MEADOW) {
		float n = veg_value_noise(shrub_seed, p, noise_wavelength, SHRUB_NOISE_SALT);
		if (kind_of_habitat == SHRUB_HEATH) {
			return base * (SHRUB_HEATH_NOISE_MIN + SHRUB_HEATH_NOISE_SPAN * n);
		}
		return base * smoothstep(SHRUB_MEADOW_NOISE_FROM, SHRUB_MEADOW_NOISE_TO, n);
	}
	return base;
}

// ShrubRules.pick_kind
int shrub_pick_kind(int kind_of_habitat, float roll) {
	vec4 shares = kind_shares[kind_of_habitat];
	float acc = shares.x;
	if (roll < acc) {
		return 0;
	}
	acc += shares.y;
	if (roll < acc) {
		return 1;
	}
	acc += shares.z;
	if (roll < acc) {
		return 2;
	}
	return 3;
}

// ShrubRules.variant_of
int shrub_variant(ivec2 cell) {
	vec2 centre = (vec2(cell) + vec2(0.5)) * spacing;
	ivec2 chunk = ivec2(floor(centre / near_chunk));
	uint h = veg_cell_hash(shrub_seed, chunk, SHRUB_VARIANT_SALT);
	return min(int(veg_unit(h, 0) * float(SHRUB_VARIANTS)), SHRUB_VARIANTS - 1);
}

// ShrubRules.cell_shrub for a cell whose point `p` is known: false when the cell holds none.
// `ground` is the lattice height; kind, height and width (world units), yaw, the hue shift,
// value factor and the hand-over phase of the shrub.
bool shrub_at(
	ivec2 cell, vec2 p, out float ground, out int kind, out float height, out float width,
	out float yaw, out float hue, out float value, out float phase
) {
	ground = 0.0;
	kind = 0;
	height = 0.0;
	width = 0.0;
	yaw = 0.0;
	hue = 0.0;
	value = 1.0;
	phase = 0.0;
	if (p.x < mask_area.x || p.y < mask_area.y || p.x >= mask_area.z || p.y >= mask_area.w) {
		return false;
	}
	int kind_of_habitat = shrub_habitat(p);
	if (kind_of_habitat == SHRUB_NONE) {
		return false;
	}
	uint h = veg_cell_hash(shrub_seed, cell, SHRUB_VALUE_SALT);
	if (veg_unit(h, SHRUB_PART_CHANCE) >= shrub_chance(kind_of_habitat, p)) {
		return false;
	}
	ground = shrub_lattice_height(p);
	if (ground < min_ground) {
		return false;
	}
	kind = shrub_pick_kind(kind_of_habitat, veg_unit(h, SHRUB_PART_KIND));
	vec2 range = kind_heights[kind];
	height = mix(range.x, range.y, veg_unit(h, SHRUB_PART_HEIGHT));
	width = height * kind_width_share[kind] * (0.85 + 0.3 * veg_unit(h, SHRUB_PART_WIDTH));
	yaw = veg_unit(h, SHRUB_PART_YAW) * 6.2831853;
	hue = (veg_unit(h, SHRUB_PART_HUE) * 2.0 - 1.0) * SHRUB_HUE_SHIFT;
	value = mix(SHRUB_VALUE_MIN, SHRUB_VALUE_MAX, veg_unit(h, SHRUB_PART_VALUE));
	phase = veg_unit(h, SHRUB_PART_PHASE);
	return true;
}
