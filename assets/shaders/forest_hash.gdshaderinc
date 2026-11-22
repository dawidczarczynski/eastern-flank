// The cell -> tree formulas of the real-scale forest fill on the GPU (TASK-189, ADR 0027): the
// GLSL twin of ForestFill (src/presentation/forest_fill.gd, the reference the full trees and the
// tests use) and ScatterPlanner.tile_seed. 32-bit unsigned arithmetic only, so both give the same
// bits; tests/unit/test_forest_fill.gd checks that the constants below equal the GDScript ones.
// Change both together.

const uint FOREST_MIX_MULTIPLIER = 73244475u; // 0x45D9F3B
const uint FOREST_UNIT_MULTIPLIER = 2654435761u; // 0x9E3779B1
const uint FOREST_POINT_SALT = 61669u; // 0xF0E5
const uint FOREST_VALUE_SALT = 61726u; // 0xF11E
const uint FOREST_PICK_SALT = 61893u; // 0xF1C5
const float FOREST_JITTER = 0.8;
const float FOREST_SCALE_MIN = 0.8;
const float FOREST_SCALE_RANGE = 0.4;
const int FOREST_PART_SPECIES = 0;
const int FOREST_PART_VARIANT = 1;
const int FOREST_PART_HUE = 2;
const int FOREST_PART_VALUE = 3;
const int FOREST_PART_SATURATION = 4;
const int FOREST_PART_PHASE = 5;
const int FOREST_PART_AUTUMN = 6;
const int FOREST_PART_AUTUMN_HUE = 7;
// TreeSpecies: hue shift, value and saturation factors, the odd yellower deciduous tree.
const float FOREST_HUE_SHIFT = 0.03;
const float FOREST_VALUE_MIN = 0.85;
const float FOREST_VALUE_MAX = 1.1;
const float FOREST_SATURATION_MIN = 0.9;
const float FOREST_SATURATION_MAX = 1.05;
const float FOREST_AUTUMN_HUE_MIN = 0.04;
const float FOREST_AUTUMN_HUE_MAX = 0.07;
// TreeMeshes.VARIANTS
const int FOREST_VARIANTS = 3;

// ScatterPlanner._mix
uint forest_mix(uint h) {
	h = (h ^ (h >> 16u)) * FOREST_MIX_MULTIPLIER;
	h = (h ^ (h >> 16u)) * FOREST_MIX_MULTIPLIER;
	return h ^ (h >> 16u);
}

// ScatterPlanner.tile_seed (seed already masked to 32 bits)
uint forest_tile_seed(uint seed_value, ivec2 cell, uint salt) {
	uint h = forest_mix(seed_value ^ salt);
	h = forest_mix(h ^ uint(cell.x));
	return forest_mix(h ^ uint(cell.y));
}

// ForestFill.unit
float forest_unit(uint h, int part) {
	uint x = h ^ (uint(part + 1) * FOREST_UNIT_MULTIPLIER);
	x = (x ^ (x >> 16u)) * FOREST_MIX_MULTIPLIER;
	x = (x ^ (x >> 16u)) * FOREST_MIX_MULTIPLIER;
	x ^= x >> 16u;
	return float(x & 16777215u) / 16777216.0;
}

// ForestFill.point: the jittered point (world XZ) of a cell from its point hash
// (forest_tile_seed(seed, cell, FOREST_POINT_SALT)).
vec2 forest_point(uint h, ivec2 cell, float spacing) {
	return vec2(
		(float(cell.x) + 0.5 + FOREST_JITTER * (float(h & 65535u) / 65536.0 - 0.5)) * spacing,
		(float(cell.y) + 0.5 + FOREST_JITTER * (float((h >> 16u) & 65535u) / 65536.0 - 0.5)) * spacing
	);
}
