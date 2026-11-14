shader_type spatial;
render_mode cull_disabled, specular_disabled;
// Trees up close (TASK-060, TreeField LOD0): bark and alpha-scissor leaf cards, with wind. The
// cards are cut by the scissor alone: alpha antialiasing (alpha to coverage) would move the whole
// mesh into the alpha pass, where every layer of every crown is lit without the depth prepass
// (~1.6 ms on the target GPU). The solid crowns of LOD1 / LOD2 use foliage_solid.gdshader.

#include "res://assets/shaders/foliage_body.gdshaderinc"
