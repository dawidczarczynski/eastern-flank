// Where the near grass of the real-scale countryside grows (TASK-217b, ADR 0033): the GLSL twin of
// GrassRules (src/presentation/grass_rules.gd, the reference the tests use), used by
// grass_gpu.gdshader. A clump is a pure function of its grid cell (vegetation_hash.gdshaderinc)
// and the map textures. Where one may stand (habitat, crop interiors, keep-off) is the shrubs'
// question, so this includes shrub_rules.gdshaderinc (its uniforms are bound by GrassRules.bind
// through ShrubRules.bind). tests/unit/test_grass_rules.gd checks the constants below against the
// GDScript ones; the tables are uniforms. Change both together.

#include "res://assets/shaders/shrub_rules.gdshaderinc"

const uint GRASS_POINT_SALT = 27137u; // 0x6A01
const uint GRASS_VALUE_SALT = 27138u; // 0x6A02
const uint GRASS_GROUP_SALT = 27139u; // 0x6A03
const uint GRASS_PATCH_SALT = 27153u; // 0x6A11
const uint GRASS_DRY_SALT = 27154u; // 0x6A12
const uint GRASS_BARE_SALT = 27155u; // 0x6A13
const uint GRASS_FLOWER_SALT = 27156u; // 0x6A14
const int GRASS_PART_CHANCE = 0;
const int GRASS_PART_KIND = 1;
const int GRASS_PART_TALL = 2;
const int GRASS_PART_SCALE = 3;
const int GRASS_PART_YAW = 4;
const int GRASS_PART_TINT = 5;
const int GRASS_PART_REED = 6;
const int GRASS_PART_FLOWER = 7;
const int GRASS_PART_FLOWER_HEIGHT = 8;
const int GRASS_PART_FLOWER_ROLL = 9;
const int GRASS_PART_FADE = 10;
const int GRASS_PART_PHASE = 11;
const float GRASS_JITTER = 0.9;
const float GRASS_OCTAVE_FREQUENCY = 2.03;
const float GRASS_OCTAVE_AMPLITUDE = 0.5;
// TerrainSplat: dirt patches, dry grass (and the dry layer's top weight), GrassPlanner scale range.
const float GRASS_DIRT_FROM = 0.8;
const float GRASS_DIRT_TO = 0.95;
const float GRASS_DRY_FROM = 0.55;
const float GRASS_DRY_TO = 0.75;
const float GRASS_DRY_MAX = 0.75;
const float GRASS_SCALE_MIN = 0.7;
const float GRASS_SCALE_RANGE = 0.6;
const int GRASS_MAX_GROUPS = 8;
// GrassRules.Kind
const int GRASS_SHORT = 0;
const int GRASS_TALL = 1;
const int GRASS_DRY_STALK = 2;
const int GRASS_NETTLE = 3;
const int GRASS_REED = 4;
const int GRASS_FLOWER = 5;

uniform uint grass_seed;
uniform float grass_spacing;
uniform float patch_wavelength;
uniform float flower_wavelength;
uniform float dry_wavelength;
uniform float bare_wavelength;
uniform float flower_cell;
uniform float flower_share;
uniform float max_slope;
uniform float shore_height;
// Chance of a cell per ShrubRules.Habitat.
uniform float grass_chance[7];
uniform float bare_thinning;
uniform float dry_stalk_share;
uniform float nettle_share;
uniform vec2 tall_range;
uniform float edge_tall_bonus;
uniform float bank_reeds;
uniform vec2 flower_range;
uniform float flower_dominance;
// Vertical multiplier per kind; a flower's range.
uniform float kind_height[6];
uniform vec2 flower_height;
// Flower species groups: cumulative shares, linear colours, count.
uniform float flower_cumulative[8];
uniform vec3 flower_colors[8];
uniform int flower_count;
// The linear colour a kind's mix pulls the ground colour towards and the mix; the dry reed colour.
uniform vec3 kind_target[6];
uniform float kind_mix[6];
uniform vec3 reed_dry;

// GrassRules.fbm
float grass_fbm(vec2 p, float wavelength, uint salt) {
	float a = veg_value_noise(grass_seed, p, wavelength, salt);
	float b = veg_value_noise(grass_seed, p, wavelength / GRASS_OCTAVE_FREQUENCY, salt + 1u);
	return (a + GRASS_OCTAVE_AMPLITUDE * b) / (1.0 + GRASS_OCTAVE_AMPLITUDE);
}

// GrassRules.point (two unit values; veg_point's 16-bit halves placed every clump far off its cell on D3D12)
vec2 grass_point(ivec2 cell) {
	uint h = veg_cell_hash(grass_seed, cell, GRASS_POINT_SALT);
	return (vec2(cell) + vec2(0.5) + GRASS_JITTER * vec2(veg_unit(h, 0) - 0.5, veg_unit(h, 1) - 0.5)) * grass_spacing;
}

// The lattice height at vertex (i, j), as shrub_lattice_height reads it.
float grass_vertex(int i, int j) {
	ivec2 v = ivec2(clamp(i, 0, height_cells.x), clamp(j, 0, height_cells.y));
	return max(texelFetch(heights, v, 0).r, water_surface);
}

// GrassRules.lattice_slope: the steepness of the lattice triangle under p.
float grass_lattice_slope(vec2 p) {
	vec2 f = (p - height_origin) / height_step;
	int i = int(floor(f.x));
	int j = int(floor(f.y));
	float u = f.x - float(i);
	float v = f.y - float(j);
	float ha = grass_vertex(i, j);
	float hb = grass_vertex(i + 1, j);
	float hc = grass_vertex(i, j + 1);
	vec2 gradient;
	if (u + v <= 1.0) {
		gradient = vec2(hb - ha, hc - ha);
	} else {
		float hd = grass_vertex(i + 1, j + 1);
		gradient = vec2(hd - hc, hd - hb);
	}
	return length(gradient) / height_step;
}

// GrassRules.pick_group
int grass_pick_group(float roll) {
	for (int k = 0; k < GRASS_MAX_GROUPS; k++) {
		if (roll < flower_cumulative[k]) {
			return min(k, flower_count - 1);
		}
	}
	return flower_count - 1;
}

// GrassRules.flower_group
int grass_flower_group(vec2 p, float roll) {
	if (roll >= flower_dominance) {
		return grass_pick_group((roll - flower_dominance) / (1.0 - flower_dominance));
	}
	ivec2 cell = ivec2(floor(p / flower_cell));
	return grass_pick_group(veg_unit(veg_cell_hash(grass_seed, cell, GRASS_GROUP_SALT), 0));
}

// GrassRules.pick_kind
int grass_pick_kind(int habitat_kind, vec2 p, uint h, float dry, float bare) {
	bool in_edge = habitat_kind == SHRUB_FOREST_EDGE;
	if (habitat_kind == SHRUB_BANK) {
		if (veg_unit(h, GRASS_PART_REED) < bank_reeds) {
			return GRASS_REED;
		}
	} else if (habitat_kind == SHRUB_MEADOW && bare < 0.5 && flower_share > 0.0) {
		float cluster = smoothstep(flower_range.x, flower_range.y, grass_fbm(p, flower_wavelength, GRASS_FLOWER_SALT));
		if (veg_unit(h, GRASS_PART_FLOWER) < flower_share * cluster) {
			return GRASS_FLOWER;
		}
	}
	float roll = veg_unit(h, GRASS_PART_KIND);
	if (roll < dry * dry_stalk_share) {
		return GRASS_DRY_STALK;
	}
	if (in_edge && roll >= 1.0 - nettle_share) {
		return GRASS_NETTLE;
	}
	float tall = smoothstep(tall_range.x, tall_range.y, grass_fbm(p, patch_wavelength, GRASS_PATCH_SALT));
	if (in_edge) {
		tall += edge_tall_bonus;
	}
	if (veg_unit(h, GRASS_PART_TALL) < clamp(tall, 0.0, 1.0)) {
		return GRASS_TALL;
	}
	return GRASS_SHORT;
}

// GrassRules.cell_clump for a cell whose point `p` is known: false when the cell holds none.
// `ground` is the lattice height; the kind, the vertical multiplier of the kind, the scale, yaw,
// tint roll, the dry share, the hand-over phase and the fade roll of the clump, the colour of a
// flower.
bool grass_at(
	ivec2 cell, vec2 p, out float ground, out int kind, out float height, out float scale,
	out float yaw, out float tint, out float dry, out float phase, out float fade,
	out vec3 flower_colour
) {
	ground = 0.0;
	kind = 0;
	height = 1.0;
	scale = 1.0;
	yaw = 0.0;
	tint = 0.5;
	dry = 0.0;
	phase = 0.0;
	fade = 0.0;
	flower_colour = vec3(1.0);
	if (p.x < mask_area.x || p.y < mask_area.y || p.x >= mask_area.z || p.y >= mask_area.w) {
		return false;
	}
	int habitat_kind = shrub_habitat(p);
	if (habitat_kind == SHRUB_NONE) {
		return false;
	}
	uint h = veg_cell_hash(grass_seed, cell, GRASS_VALUE_SALT);
	float bare = smoothstep(GRASS_DIRT_FROM, GRASS_DIRT_TO, grass_fbm(p, bare_wavelength, GRASS_BARE_SALT));
	float keep = grass_chance[habitat_kind] * (1.0 - bare_thinning * bare);
	if (veg_unit(h, GRASS_PART_CHANCE) >= keep) {
		return false;
	}
	ground = shrub_lattice_height(p);
	if (ground <= shore_height) {
		return false;
	}
	if (grass_lattice_slope(p) > max_slope) {
		return false;
	}
	dry = smoothstep(GRASS_DRY_FROM, GRASS_DRY_TO, grass_fbm(p, dry_wavelength, GRASS_DRY_SALT));
	kind = grass_pick_kind(habitat_kind, p, h, dry, bare);
	height = kind_height[kind];
	if (kind == GRASS_FLOWER) {
		height = mix(flower_height.x, flower_height.y, veg_unit(h, GRASS_PART_FLOWER_HEIGHT));
		int group = grass_flower_group(p, veg_unit(h, GRASS_PART_FLOWER_ROLL));
		flower_colour = flower_colors[group];
	}
	scale = GRASS_SCALE_MIN + GRASS_SCALE_RANGE * veg_unit(h, GRASS_PART_SCALE);
	yaw = veg_unit(h, GRASS_PART_YAW) * 6.2831853;
	tint = veg_unit(h, GRASS_PART_TINT);
	phase = veg_unit(h, GRASS_PART_PHASE);
	fade = veg_unit(h, GRASS_PART_FADE);
	return true;
}
