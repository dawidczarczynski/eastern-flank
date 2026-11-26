// The fill of the real-scale forest on the GPU (TASK-189, ADR 0027; shared by the impostors,
// forest_impostor.gdshader, and the full trees, forest_tree.gdshader, TASK-221): the map data the
// cell -> tree formulas read (ForestFill.bind and ForestField bind it once per map) and the two
// map lookups – the drawn lattice height (TerrainLattice.mesh_height_at) and whether a tree may
// stand (ForestFill._stands). The hash and the cell formulas: forest_hash.gdshaderinc.

#include "res://assets/shaders/forest_hash.gdshaderinc"

// Set by ForestFill.bind and ForestField (lattice).
uniform uint forest_seed;
uniform float spacing;
uniform float min_ground;
uniform float high_ground;
// ScatterPlanner's conifer chance above / below high_ground.
uniform vec2 conifer_chance;
// Cumulative shares: pine (of the conifers), birch, birch + oak, all (of the deciduous trees).
uniform vec4 shares;
uniform float autumn_share;
// The fill area (x0, z0, x1, z1), end exclusive.
uniform vec4 fill_area;
// Where a tree may stand (ForestFill's stand mask from a ForestMaskSource: forest land cover minus
// the tile-centre clearing, roads and rivers), mask_per_unit texels per unit from fill_area.xy.
uniform sampler2D forest_mask : filter_nearest, repeat_disable;
uniform float mask_per_unit;
uniform bool use_parcels;
uniform sampler2D parcels : filter_nearest, repeat_disable;
uniform vec2 parcel_origin_m;
uniform float parcel_metres_per_pixel;
uniform float metres_per_unit;
// The lattice: heights of (height_cells + 1)^2 vertices from height_origin, height_step apart.
uniform sampler2D heights : filter_nearest, repeat_disable;
uniform vec2 height_origin;
uniform float height_step;
uniform ivec2 height_cells;
uniform float water_surface;

// TerrainLattice.mesh_height_at
float lattice_height(vec2 p) {
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

// ForestFill._stands: on the stand mask and off the parcels.
bool stands(vec2 p) {
	ivec2 t = ivec2(floor((p - fill_area.xy) * mask_per_unit));
	ivec2 size = textureSize(forest_mask, 0);
	if (t.x < 0 || t.y < 0 || t.x >= size.x || t.y >= size.y || texelFetch(forest_mask, t, 0).r < 0.5) {
		return false;
	}
	if (!use_parcels) {
		return true;
	}
	// ParcelMap.blocks_standing: every kind but none (0) and the balk (8).
	ivec2 q = ivec2(floor((p * metres_per_unit - parcel_origin_m) / parcel_metres_per_pixel));
	ivec2 parcel_size = textureSize(parcels, 0);
	if (q.x < 0 || q.y < 0 || q.x >= parcel_size.x || q.y >= parcel_size.y) {
		return true;
	}
	int kind = int(round(texelFetch(parcels, q, 0).r * 255.0));
	return kind == 0 || kind == 8;
}
