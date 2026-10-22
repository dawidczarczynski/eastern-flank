class_name GrassMesh
extends RefCounted
## The grass clump mesh (TASK-057): three vertical quads crossed 60 degrees apart, pivot at the
## bottom centre. UV.y is 0 at the tip and 1 at the root (the wind shader bends by it). Normals
## point up so the cards are lit like the ground instead of like flat walls.

const CARDS := 3


## A clump `width` wide and `height` tall (world units).
static func clump(width: float, height: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for card in CARDS:
		var angle := PI * float(card) / CARDS
		var half := Vector3(cos(angle), 0.0, sin(angle)) * (width * 0.5)
		var base := vertices.size()
		vertices.append_array(
			[-half, half, half + Vector3.UP * height, -half + Vector3.UP * height]
		)
		normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
