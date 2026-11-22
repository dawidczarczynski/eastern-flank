shader_type spatial;
render_mode world_vertex_coords, cull_disabled, specular_disabled;
// Tree impostors with per-instance data (TASK-135, TreeImpostors; the planned trees of TreeField –
// the dense forest is GPU-placed, forest_impostor.gdshader). Instance data: transform = base +
// scale (x quad width, y tree height), COLOR = tint relative to the baked colour, CUSTOM = (full
// range centre, impostor range centre, atlas row, phase). The picture, the bands and the view
// choice and the lighting: tree_impostor_view.gdshaderinc.

#include "res://assets/shaders/tree_impostor_view.gdshaderinc"
#include "res://assets/shaders/cloud_shadow.gdshaderinc"

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	float phase = INSTANCE_CUSTOM.a;
	tint = COLOR.rgb;
	row = INSTANCE_CUSTOM.b;
	float width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	float yaw = fract(phase * 7.31 + origin.x * 3.17 + origin.z * 1.93) * 6.2831853;
	float view;
	vec3 face = impostor_facing(origin, MAIN_CAM_INV_VIEW_MATRIX, INV_VIEW_MATRIX);
	VERTEX = impostor_corner(origin, face, width, height, yaw, UV, view);
	view_position = view;
	// Upright: the planned trees carry no ground normal.
	vec3 bx;
	vec3 by;
	vec3 bz;
	impostor_basis(origin, face, vec3(0.0, 1.0, 0.0), bx, by, bz);
	basis_x = bx;
	basis_y = by;
	basis_z = bz;
	NORMAL = bz;
	if (!impostor_in_band(distance(origin, cam), INSTANCE_CUSTOM.r, INSTANCE_CUSTOM.g, phase)) {
		VERTEX = origin;
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
