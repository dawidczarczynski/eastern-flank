// The picture side of the tree impostors (TASK-135, TreeImpostors), shared by
// tree_impostor.gdshader (per-instance data) and forest_impostor.gdshader (GPU-placed forest,
// TASK-189): a quad per tree, turned to the camera about the vertical, showing a baked picture of
// the real tree model. The atlas has one row per species x variant and one column per view around
// the tree; the two views nearest to the camera's direction (relative to the tree's own yaw) are
// blended. Opaque with discard (no alpha pass).
// Lit by the scene (TASK-191): `atlas` is the unlit albedo, `normal_atlas` (same layout) the
// view-space normal of the bake camera, encoded 0..1. The vertex shader passes the bake camera's
// axes as they stand in the world for this quad (impostor_basis: right, up, towards the camera,
// tilted with the ground by `slope_share`) and the fragment turns the baked normal into the view,
// so the scene's sun, shadows and ambient light the picture as they light the full trees.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_atlas : filter_linear_mipmap, repeat_disable;
// Elevation of the bake camera (radians, TreeImpostors.ELEVATION).
uniform float bake_elevation = 0.26;
uniform float rows = 1.0;
uniform float views = 8.0;
uniform float band_share = 0.08;
// The full-tree budget's reach (ForestField): from here on no full tree is drawn.
uniform float full_reach = 1.0e9;
// The picture spans `vertical_span` tree heights from `below_base` of a height below the base.
uniform float below_base = 0.12;
uniform float vertical_span = 1.25;
// Albedo factor of the picture against the full trees (LookPreset vegetation
// `impostor_albedo`: the light a crown's own leaves block on a full tree).
uniform float exposure = 1.0;
// As foliage_body.gdshaderinc.
uniform float backlight_strength = 0.35;
// How far the picture's normals turn with the ground's slope (0: upright trees only).
uniform float slope_share = 0.0;

varying vec3 tint;
varying float row;
varying float view_position;
// The bake camera's x, y, z axes in the world for this quad.
varying vec3 basis_x;
varying vec3 basis_y;
varying vec3 basis_z;

// Whether a tree at `camera_distance` is drawn as an impostor: between its full band (capped by
// the full-tree budget) and its impostor band, at its own point of the bands (`phase`).
bool impostor_in_band(float camera_distance, float full_centre, float out_centre, float phase) {
	float lod_from = min(
		mix(full_centre * (1.0 - band_share), full_centre * (1.0 + band_share), phase),
		full_reach
	);
	float lod_to = mix(out_centre * (1.0 - band_share), out_centre * (1.0 + band_share), phase);
	return camera_distance >= lod_from && camera_distance < lod_to;
}

// The world position of a quad corner (`uv`) of a tree at `origin`; `view` is the view_position
// for the fragment: the view whose rotation of the tree shows the camera's side (the tree's yaw
// minus the camera's azimuth, both from +z towards +x, in turns of the views).
vec3 impostor_corner(
	vec3 origin, vec3 cam, float width, float height, float yaw, vec2 uv, out float view
) {
	vec3 to_camera = cam - origin;
	to_camera.y = 0.0;
	float flat_length = length(to_camera);
	to_camera = flat_length > 1.0e-6 ? to_camera / flat_length : vec3(0.0, 0.0, 1.0);
	vec3 right = vec3(to_camera.z, 0.0, -to_camera.x);
	float up = mix(-below_base, vertical_span - below_base, 1.0 - uv.y);
	float azimuth = atan(to_camera.x, to_camera.z);
	view = mod((yaw - azimuth) / 6.2831853 * views, views);
	return origin + right * ((uv.x - 0.5) * width) + vec3(0.0, up * height, 0.0);
}

// `v` turned about the unit `axis` by `angle` (Rodrigues).
vec3 impostor_rotate(vec3 v, vec3 axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

// The bake camera's axes (x, y, z) in the world for a quad facing `cam` from `origin`, turned
// from the vertical towards the unit `ground_normal` by slope_share of the slope.
void impostor_basis(
	vec3 origin, vec3 cam, vec3 ground_normal, out vec3 x, out vec3 y, out vec3 z
) {
	vec3 to_camera = cam - origin;
	to_camera.y = 0.0;
	float flat_length = length(to_camera);
	vec3 forward = flat_length > 1.0e-6 ? to_camera / flat_length : vec3(0.0, 0.0, 1.0);
	float ce = cos(bake_elevation);
	float se = sin(bake_elevation);
	x = vec3(forward.z, 0.0, -forward.x);
	y = vec3(0.0, ce, 0.0) - forward * se;
	z = vec3(0.0, se, 0.0) + forward * ce;
	vec3 axis = cross(vec3(0.0, 1.0, 0.0), ground_normal);
	float axis_length = length(axis);
	if (axis_length > 1.0e-4 && slope_share > 0.0) {
		axis /= axis_length;
		float angle = acos(clamp(ground_normal.y, -1.0, 1.0)) * slope_share;
		x = impostor_rotate(x, axis, angle);
		y = impostor_rotate(y, axis, angle);
		z = impostor_rotate(z, axis, angle);
	}
}

// The world normal of the picture at `uv`.
vec3 impostor_world_normal(vec2 uv) {
	float i0 = floor(view_position);
	float f = view_position - i0;
	vec4 a = texture(normal_atlas, vec2((mod(i0, views) + uv.x) / views, (row + uv.y) / rows));
	vec4 b = texture(normal_atlas, vec2((mod(i0 + 1.0, views) + uv.x) / views, (row + uv.y) / rows));
	float alpha = a.a * (1.0 - f) + b.a * f;
	vec3 n = (a.rgb * (1.0 - f) + b.rgb * f) / max(alpha, 1.0e-3) * 2.0 - 1.0;
	return normalize(basis_x * n.x + basis_y * n.y + basis_z * n.z);
}

// The tinted picture colour at `uv` (rgb) and its coverage (a: discard below 0.5).
vec4 impostor_color(vec2 uv) {
	float i0 = floor(view_position);
	float f = view_position - i0;
	vec4 a = texture(atlas, vec2((mod(i0, views) + uv.x) / views, (row + uv.y) / rows));
	vec4 b = texture(atlas, vec2((mod(i0 + 1.0, views) + uv.x) / views, (row + uv.y) / rows));
	float alpha = a.a * (1.0 - f) + b.a * f;
	vec3 color = (a.rgb * (1.0 - f) + b.rgb * f) / max(alpha, 1.0e-3);
	return vec4(color * tint * exposure, alpha);
}
