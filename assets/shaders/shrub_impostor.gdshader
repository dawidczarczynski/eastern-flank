shader_type spatial;
render_mode world_vertex_coords, cull_disabled, specular_disabled;
// The GPU-placed shrub impostors (TASK-217a, ADR 0033; ShrubField's far layer). A chunk is a
// MultiMesh of the TreeImpostors quad with one instance per shrub grid cell and no per-instance
// data: the cell comes from INSTANCE_ID and the chunk's `cells` (instance uniform), the shrub from
// shrub_rules.gdshaderinc (the twin of ShrubRules) and the map textures bound once per map. The
// picture is the baked atlas of the shrub's source model (tree_impostor_view.gdshaderinc, lit by
// the scene as the forest impostors are), tinted to its kind's colour; each shrub is drawn from
// its own point of the hand-over band around mesh_reach (the mesh layer draws it nearer) to its
// point of the band around impostor_reach. A cell without a shrub collapses to a point.

#include "res://assets/shaders/shrub_rules.gdshaderinc"
#include "res://assets/shaders/tree_impostor_view.gdshaderinc"
#include "res://assets/shaders/cloud_shadow.gdshaderinc"

// First cell (x, z) and cell counts (x, z) of the chunk.
instance uniform vec4 cells;

// Set by ShrubField: the source of every kind; per source x variant (crown width and height at
// scale 1, atlas row, quad width per unit of crown width); the linear leaf colour each source's
// picture was baked in; the hand-over and far ends (camera distances, world units); the sink;
// burnt circles.
uniform int kind_source[4];
uniform vec4 source_sizes[9];
uniform vec3 source_leaf[3];
uniform float mesh_reach = 1.0;
uniform float impostor_reach = 10.0;
uniform float sink = 0.0;
uniform vec4 burns[128];
uniform int burn_count;

vec3 shrub_rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}

vec3 shrub_hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// The kind colour shifted by the shrub's variation (as foliage_body.gdshaderinc does for the
// mesh), over the colour the source's picture was baked in.
vec3 shrub_tint(vec3 kind_color, vec3 leaf, float hue, float value) {
	vec3 hsv = shrub_rgb_to_hsv(kind_color);
	vec3 shifted = shrub_hsv_to_rgb(vec3(fract(hsv.x - hue), hsv.y, hsv.z * value));
	return clamp(shifted / max(leaf, vec3(0.02)), vec3(0.3), vec3(2.5));
}

void vertex() {
	ivec2 cell;
	bool alive = veg_instance_cell(INSTANCE_ID, cells, cell);
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	vec2 p = shrub_point(cell);
	float far_end = impostor_reach * (1.0 + band_share);
	// Outside both bands on the ground plane already: no texture reads.
	float flat_distance = distance(p, cam.xz);
	alive = alive && flat_distance < far_end;
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
	for (int b = 0; b < burn_count && alive; b++) {
		alive = distance(p, burns[b].xy) > burns[b].z;
	}
	vec3 origin = vec3(p.x, alive ? shrub_drawn_ground(p, ground) - sink : 0.0, p.y);
	tint = vec3(1.0);
	row = 0.0;
	view_position = 0.0;
	basis_x = vec3(1.0, 0.0, 0.0);
	basis_y = vec3(0.0, 1.0, 0.0);
	basis_z = vec3(0.0, 0.0, 1.0);
	VERTEX = origin;
	if (alive && impostor_in_band(distance(origin, cam), mesh_reach, impostor_reach, phase)) {
		int source = kind_source[kind];
		vec4 size = source_sizes[source * SHRUB_VARIANTS + shrub_variant(cell)];
		row = size.z;
		tint = shrub_tint(kind_colors[kind], source_leaf[source], hue, value);
		float view;
		vec3 face = impostor_facing(origin, MAIN_CAM_INV_VIEW_MATRIX, INV_VIEW_MATRIX);
		VERTEX = impostor_corner(origin, face, width * size.w, height, yaw, UV, view);
		view_position = view;
		float dx = shrub_lattice_height(p + vec2(height_step, 0.0)) - ground;
		float dz = shrub_lattice_height(p + vec2(0.0, height_step)) - ground;
		vec3 ground_normal = normalize(vec3(-dx, height_step, -dz));
		vec3 bx;
		vec3 by;
		vec3 bz;
		impostor_basis(origin, cam, ground_normal, bx, by, bz);
		basis_x = bx;
		basis_y = by;
		basis_z = bz;
		NORMAL = bz;
	}
}

void fragment() {
	vec4 color = impostor_color(UV);
	if (color.a < 0.5) {
		discard;
	}
	ALBEDO = color.rgb * cloud_shadow_factor((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz);
	NORMAL = normalize((VIEW_MATRIX * vec4(impostor_world_normal(UV), 0.0)).xyz);
	ROUGHNESS = 0.85;
	BACKLIGHT = color.rgb * backlight_strength;
}
