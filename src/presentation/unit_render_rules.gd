class_name UnitRenderRules
extends RefCounted
## What a unit model may cost the renderer (ADR 0023), checked for every model and faction by
## tests/unit/test_unit_model_contract.gd and printed by tools/render_unit.sh. A unit is a few
## dozen pixels in the battle view, so what counts is not its triangles first but what its
## materials make the renderer do for the whole screen:
## - `material_violations`: a unit material must stay in the opaque pass with the depth prepass
##   and must not switch on a full-screen pass. Soldiers' skin with subsurface scattering cost
##   0.9 ms a frame (the scattering pass runs over the screen however small the faces are).
## - `far_triangles`: triangles drawn in the default battle view (FAR_PIXEL per pixel), through
##   the automatic levels of detail of MeshLods; at most MAX_FAR_TRIANGLES per model.
## Usage: UnitRenderRules.violations(UnitModels.build(id, 0, faction)) -> ["...", ...]

## World units one pixel covers on a unit in the default battle view: CameraRig.DEFAULT_DISTANCE
## 24 at the 40 degree camera on a 1080 px high screen (2 * 24 * tan(20 deg) / 1080).
const FAR_PIXEL := 0.0162
## Triangles a model may draw at FAR_PIXEL (the levels MeshLods generates): half the full-detail
## budget of the model contract (40 000).
const MAX_FAR_TRIANGLES := 20000

## Shader code a unit material must not contain -> why.
const FORBIDDEN_SHADER_CODE := {
	"SSS_STRENGTH": "subsurface scattering (a full-screen pass)",
	"hint_screen_texture": "reads the screen (a full-screen copy)",
	"hint_depth_texture": "reads the depth buffer (a full-screen copy)",
	"hint_normal_roughness_texture": "reads the normal / roughness buffer (an extra prepass)",
	"blend_add": "blended (alpha pass, no depth prepass)",
	"blend_sub": "blended (alpha pass, no depth prepass)",
	"blend_mul": "blended (alpha pass, no depth prepass)",
	"blend_premul_alpha": "blended (alpha pass, no depth prepass)",
	"depth_prepass_alpha": "alpha (alpha pass)",
	"alpha_to_coverage": "alpha antialiasing (alpha pass, no depth prepass)",
	"ALPHA_ANTIALIASING_EDGE": "alpha antialiasing (alpha pass, no depth prepass)",
}


## Every broken rule of a built model (UnitModels.build / a model's `build`), as readable lines;
## empty when the model is fine.
static func violations(model: Node) -> Array[String]:
	var found: Array[String] = []
	var seen := {}
	for instance in _instances(model, true):
		for material in _materials(instance):
			if seen.has(material):
				continue
			seen[material] = true
			for reason in material_violations(material):
				found.append("material on %s: %s" % [instance.name, reason])
	var far := far_triangles(model)
	if far > MAX_FAR_TRIANGLES:
		found.append(
			(
				"%d triangles in the battle view (max %d): too little for MeshLods to simplify"
				% [far, MAX_FAR_TRIANGLES]
			)
		)
	return found


## Why `material` breaks the rules (empty = allowed): anything that leaves the opaque pass or
## needs a full-screen pass. An alpha scissor is allowed (opaque pass).
static func material_violations(material: Material) -> Array[String]:
	var found: Array[String] = []
	if material == null:
		return found
	if material.next_pass != null:
		found.append("next_pass (the part is drawn twice)")
	var base := material as BaseMaterial3D
	if base != null:
		var scissor := BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		if (
			base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			and base.transparency != scissor
		):
			found.append("transparency (alpha pass, no depth prepass)")
		if base.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
			found.append("blend mode (alpha pass, no depth prepass)")
		if base.subsurf_scatter_enabled:
			found.append("subsurface scattering (a full-screen pass)")
		if base.refraction_enabled:
			found.append("refraction (a full-screen copy)")
		if base.proximity_fade_enabled:
			found.append("proximity fade (reads the depth buffer)")
		if base.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
			found.append("distance fade (alpha or dither)")
		if base.no_depth_test:
			found.append("no depth test")
	var shaded := material as ShaderMaterial
	if shaded != null and shaded.shader != null:
		var code := shader_source(shaded.shader.code)
		for token: String in FORBIDDEN_SHADER_CODE:
			if code.contains(token):
				found.append("%s: %s" % [token, FORBIDDEN_SHADER_CODE[token]])
		var alpha := RegEx.create_from_string("\\bALPHA\\s*[-+*]?=[^=]")
		if alpha.search(code) != null and not code.contains("ALPHA_SCISSOR_THRESHOLD"):
			found.append("ALPHA without a scissor (alpha pass, no depth prepass)")
	return found


## Shader `code` without comments and with its `#include` files pasted in (one level deep is all
## the project uses; nested includes are followed too).
static func shader_source(code: String, depth := 0) -> String:
	var comments := RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/")
	var include := RegEx.create_from_string('#include\\s+"([^"]+)"')
	var result := comments.sub(include.sub(code, "", true), "", true)
	if depth >= 4:
		return result
	for found in include.search_all(code):
		var path := found.get_string(1)
		if FileAccess.file_exists(path):
			result += "\n" + shader_source(FileAccess.get_file_as_string(path), depth + 1)
	return result


## Triangles of the model's visible meshes at full detail.
static func triangles(model: Node) -> int:
	var total := 0
	for instance in _instances(model, false):
		total += MeshLods.triangles(instance.mesh)
	return total


## Triangles the renderer draws of the model's visible meshes when a pixel covers `pixel` world
## units (default: the battle view): each mesh at the level MeshLods generated for an error of
## one pixel. `model` is measured as built, with its own scale (UnitModels.build applies the
## game scale; a bare model `build` is at scale 1).
static func far_triangles(model: Node, pixel := FAR_PIXEL) -> int:
	var total := 0
	for instance in _instances(model, false):
		var scale := _scale_to(instance, model)
		total += MeshLods.triangles_at(instance.mesh, pixel / maxf(scale, 1e-6))
	return total


## The MeshInstance3D nodes with a mesh under `node` (inclusive); hidden branches (the squads'
## `Stand` variants) only with `hidden`.
static func _instances(
	node: Node, hidden: bool, into: Array[MeshInstance3D] = []
) -> Array[MeshInstance3D]:
	var spatial := node as Node3D
	if spatial != null and not spatial.visible and not hidden:
		return into
	var instance := node as MeshInstance3D
	if instance != null and instance.mesh != null:
		into.append(instance)
	for child in node.get_children():
		_instances(child, hidden, into)
	return into


## The materials `instance` is drawn with: its override (or the camo material a stored prototype
## keeps as metadata, see ModelParts.cached), else its surface materials.
static func _materials(instance: MeshInstance3D) -> Array[Material]:
	var found: Array[Material] = []
	if instance.material_override != null:
		found.append(instance.material_override)
	elif instance.has_meta(&"camo_material"):
		found.append(instance.get_meta(&"camo_material"))
	else:
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface)
			if material != null:
				found.append(material)
	return found


## Largest scale factor from `node`'s local space to `root`'s parent space.
static func _scale_to(node: Node3D, root: Node) -> float:
	var basis := Basis.IDENTITY
	var at: Node = node
	while at != null:
		if at is Node3D:
			basis = (at as Node3D).basis * basis
		if at == root:
			break
		at = at.get_parent()
	var scale := basis.get_scale().abs()
	return maxf(scale.x, maxf(scale.y, scale.z))
