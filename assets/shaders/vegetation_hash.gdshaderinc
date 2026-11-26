// The shared cell hash of the GPU-placed vegetation layers (TASK-217a, ADR 0033): the GLSL twin
// of VegetationHash (src/presentation/vegetation_hash.gd). It reuses the forest's uint32 hash
// (forest_hash.gdshaderinc, ADR 0027: forest_mix, forest_tile_seed, forest_unit) and adds the
// generic pieces every layer needs: the jittered cell point, the cell of an instance and a value
// noise. tests/unit/test_vegetation_hash.gd checks the constants below against the GDScript ones.
// Change both together.

#include "res://assets/shaders/forest_hash.gdshaderinc"

const uint VEG_NOISE_SALT = 28161u; // 0x6E01

// VegetationHash.cell_hash
uint veg_cell_hash(uint seed_value, ivec2 cell, uint salt) {
	return forest_tile_seed(seed_value, cell, salt);
}

// VegetationHash.unit
float veg_unit(uint h, int part) {
	return forest_unit(h, part);
}

// VegetationHash.point: the jittered point (world XZ) of a cell from its point hash.
vec2 veg_point(uint h, ivec2 cell, float spacing, float jitter) {
	return vec2(
		(float(cell.x) + 0.5 + jitter * (float(h & 65535u) / 65536.0 - 0.5)) * spacing,
		(float(cell.y) + 0.5 + jitter * (float((h >> 16u) & 65535u) / 65536.0 - 0.5)) * spacing
	);
}

// The cell of an instance: the chunk's first cell and cell counts (x, z) are its `cells`
// instance uniform; instances beyond the chunk's cells (the shared MultiMesh holds the largest
// chunk's count) report false.
bool veg_instance_cell(int instance_id, vec4 cells, out ivec2 cell) {
	int nx = max(int(cells.z), 1);
	cell = ivec2(int(cells.x) + instance_id % nx, int(cells.y) + instance_id / nx);
	return instance_id < nx * int(cells.w);
}

float veg_lattice(uint seed_value, int i, int j, uint salt) {
	return veg_unit(veg_cell_hash(seed_value, ivec2(i, j), salt ^ VEG_NOISE_SALT), 0);
}

// VegetationHash.value_noise
float veg_value_noise(uint seed_value, vec2 p, float wavelength, uint salt) {
	vec2 f = p / wavelength;
	int i = int(floor(f.x));
	int j = int(floor(f.y));
	float u = f.x - float(i);
	float v = f.y - float(j);
	u = u * u * (3.0 - 2.0 * u);
	v = v * v * (3.0 - 2.0 * v);
	float a = veg_lattice(seed_value, i, j, salt);
	float b = veg_lattice(seed_value, i + 1, j, salt);
	float c = veg_lattice(seed_value, i, j + 1, salt);
	float d = veg_lattice(seed_value, i + 1, j + 1, salt);
	return mix(mix(a, b, u), mix(c, d, u), v);
}
