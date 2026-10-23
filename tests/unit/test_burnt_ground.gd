extends TestCase


func test_indices_within_radius_only() -> void:
	var transforms: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 1.0)),
		Transform3D(Basis.IDENTITY, Vector3(5.0, 0.0, 5.0)),
		Transform3D(Basis.IDENTITY, Vector3(0.8, 3.0, 1.0)),
	]
	var hit := BurntGround.indices_within(transforms, Vector3.ZERO, Vector2(1.0, 1.0), 1.0)
	assert_eq(Array(hit), [0, 2])


func test_node_position_is_added_to_local_origins() -> void:
	var transforms: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(0.5, 0.0, 0.0))]
	var hit := BurntGround.indices_within(
		transforms, Vector3(8.0, 0.0, 8.0), Vector2(8.0, 8.0), 1.0
	)
	assert_eq(Array(hit), [0])
	hit = BurntGround.indices_within(transforms, Vector3(8.0, 0.0, 8.0), Vector2(0.0, 0.0), 1.0)
	assert_eq(hit.size(), 0)
