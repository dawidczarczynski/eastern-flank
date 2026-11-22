// Moving cloud shadows (TASK-201b): soft darker patches drifting over ground and trees. Godot's
// DirectionalLight3D has no light projector, so the opaque world shaders (terrain, road, grass,
// foliage, canopy, tree impostors) multiply their albedo by this mask; units (camo.gdshader) do
// not include it, they stay evenly lit. The global uniforms are registered at runtime by
// CloudShadows.setup() (src/presentation/cloud_shadows.gd), not in project.godot.
global uniform sampler2D cloud_noise : repeat_enable, filter_linear;
global uniform float cloud_shadow_strength;
global uniform float cloud_scale;
global uniform float cloud_speed;
global uniform vec2 cloud_drift;
global uniform vec2 cloud_sun_offset;

// Brightness factor (1 = lit) of the ground point at world (x, z): a low-frequency tileable noise
// one `cloud_scale` (world units) per period, drifting along `cloud_drift` at `cloud_speed`
// (units / s), shifted by the sun offset so the shadow falls away from the sun.
float cloud_shadow_factor(vec2 world_xz) {
	if (cloud_shadow_strength <= 0.0) {
		return 1.0;
	}
	vec2 p = (world_xz + cloud_sun_offset + cloud_drift * (TIME * cloud_speed)) / cloud_scale;
	float mask = smoothstep(0.38, 0.50, texture(cloud_noise, p).r);
	return 1.0 - mask * cloud_shadow_strength * 0.6;
}
