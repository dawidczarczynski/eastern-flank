shader_type spatial;
render_mode cull_disabled, specular_disabled;
// The GPU-placed shrubs up close (TASK-217a, ADR 0033; ShrubField's near layer): the real LOD0
// model (bark + alpha-scissor leaf cards, foliage_body.gdshaderinc) of the shrub's source
// species, hash-placed from its cell like the impostors (shrub_rules.gdshaderinc). A chunk is a
// MultiMesh of identity instances, one per cell; its mesh carries one surface per source species
// (this material is one of them, `placed_source`), so a cell's shrub is drawn by the surface of
// its kind and collapsed by the others. Each shrub is drawn up to its own point of the hand-over
// band around mesh_reach; the impostors (shrub_impostor.gdshader) take it from there.

#define PLACED_VEGETATION
#include "res://assets/shaders/shrub_rules.gdshaderinc"

// First cell (x, z) and cell counts (x, z) of the chunk.
instance uniform vec4 cells;

// Set by ShrubField: which source species this surface draws (ShrubRules.SOURCES index), the
// source of every kind, the model's crown width and height (scale 1) per variant, the hand-over
// (camera distance, world units) and its band, the base sink and the burnt circles.
uniform int placed_source = 0;
uniform int kind_source[4];
uniform vec2 placed_sizes[3];
uniform float mesh_reach = 1.0;
uniform float hand_over_share = 0.08;
uniform float sink = 0.0;
uniform vec4 burns[128];
uniform int burn_count;

bool placed_instance(
	int instance_id, mat4 main_cam, float tag, out vec4 custom, out vec3 base_color, out vec3 origin,
	out mat3 placed, out mat3 placed_normal
) {
	custom = vec4(0.0, 1.0, 1.0, 0.0);
	base_color = vec3(0.0);
	origin = vec3(0.0);
	placed = mat3(1.0);
	placed_normal = mat3(1.0);
	ivec2 cell;
	bool alive = veg_instance_cell(instance_id, cells, cell);
	vec3 cam = main_cam[3].xyz;
	vec2 p = shrub_point(cell);
	// Beyond the hand-over band on the ground plane already: no texture reads.
	alive = alive && distance(p, cam.xz) < mesh_reach * (1.0 + hand_over_share);
	float ground = 0.0;
	int kind = 0;
	float height = 0.0;
	float width = 0.0;
	float yaw = 0.0;
	float hue = 0.0;
	float value = 1.0;
	float phase = 0.0;
	if (alive) {
		alive = shrub_at(cell, p, ground, kind, height, width, yaw, hue, value, phase);
	}
	alive = alive && kind_source[kind] == placed_source;
	for (int b = 0; b < burn_count && alive; b++) {
		alive = distance(p, burns[b].xy) > burns[b].z;
	}
	if (!alive) {
		return false;
	}
	origin = vec3(p.x, shrub_drawn_ground(p, ground) - sink, p.y);
	float lod_to = mix(mesh_reach * (1.0 - hand_over_share), mesh_reach * (1.0 + hand_over_share), phase);
	if (distance(origin, cam) >= lod_to) {
		return false;
	}
	vec2 size = placed_sizes[shrub_variant(cell)];
	float sx = width / max(size.x, 1.0e-6);
	float sy = height / max(size.y, 1.0e-6);
	float c = cos(yaw);
	float s = sin(yaw);
	// Basis(Vector3.UP, yaw) * Basis.from_scale(sx, sy, sx), columns.
	mat3 rotation = mat3(vec3(c, 0.0, -s), vec3(0.0, 1.0, 0.0), vec3(s, 0.0, c));
	placed = rotation * mat3(vec3(sx, 0.0, 0.0), vec3(0.0, sy, 0.0), vec3(0.0, 0.0, sx));
	placed_normal = rotation
		* mat3(vec3(1.0 / sx, 0.0, 0.0), vec3(0.0, 1.0 / sy, 0.0), vec3(0.0, 0.0, 1.0 / sx));
	base_color = kind_colors[kind];
	custom = vec4(hue, value, 1.0, phase);
	return true;
}

#include "res://assets/shaders/foliage_body.gdshaderinc"
