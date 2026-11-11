shader_type canvas_item;
// The nuclear finale's fade (TASK-140): whatever is on screen goes to grey (`gray`), then to
// black (`dark`). Samples the screen drawn so far, so the rect must sit above the HUD.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float gray : hint_range(0.0, 1.0) = 0.0;
uniform float dark : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), gray);
	COLOR = vec4(c * (1.0 - dark), 1.0);
}
