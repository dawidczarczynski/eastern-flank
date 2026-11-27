shader_type spatial;
render_mode cull_disabled, specular_disabled;
// The full 3D trees of the real-scale forest (TASK-221, ADR 0027 amendment 2): the LOD0 model of
// foliage.gdshader (bark + alpha-scissor leaf cards, with wind) drawn from the compacted lists of
// forest_cells.glsl (ForestFullTrees): every instance is a tree with its transform and variation
// (INSTANCE_CUSTOM) – or an unused slot of the list, whose zero basis collapses it before any work
// (COMPACTED_TREES, foliage_body.gdshaderinc). The compute pass decides the range (tree by tree,
// by the impostor's own hand-over band), so no LOD band is judged here.

#define COMPACTED_TREES
#include "res://assets/shaders/foliage_body.gdshaderinc"
