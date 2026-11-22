shader_type spatial;
render_mode unshaded, cull_disabled;
// The impostor bake of the full trees (TASK-191, TreeImpostors): the LOD0 card shader without
// light. One pass renders the unlit albedo (leaf colour x card texture x baked AO, bark), the
// other the view-space normal of the bent card normals, so the impostors can be lit by the
// scene's sun and ambient like the full trees.

#define IMPOSTOR_BAKE
#include "res://assets/shaders/foliage_body.gdshaderinc"
