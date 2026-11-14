shader_type spatial;
render_mode cull_back, specular_disabled;
// Distant trees (TreeField LOD1 / LOD2 and the backdrop's far trees): bark and a closed solid
// crown, no wind. Fully opaque (no ALPHA, back faces culled): unlike the card shader it renders in
// the opaque pass with the depth prepass and a plain depth-only shadow pass.

#define SOLID_CROWN
#include "res://assets/shaders/foliage_body.gdshaderinc"
