extends TestCase

const EPSILON := 1e-4


func test_camera_position_follows_the_aabb_size() -> void:
	var aabb := AABB(Vector3(-0.5, 0.0, -0.25), Vector3(1.0, 0.5, 0.5))
	var camera := PortraitRenderer.camera_transform(aabb)
	var size := aabb.size.length()
	var expected := aabb.get_center() + size * Vector3(0.82, 0.4, 1.02)
	assert_true(camera.origin.distance_to(expected) < EPSILON, "position %s" % camera.origin)


func test_camera_looks_at_the_centre_slightly_below() -> void:
	var aabb := AABB(Vector3(-0.5, 0.0, -0.25), Vector3(1.0, 0.5, 0.5))
	var camera := PortraitRenderer.camera_transform(aabb)
	var target := aabb.get_center() - Vector3(0.0, 0.02, 0.0)
	var forward := -camera.basis.z
	var wanted := (target - camera.origin).normalized()
	assert_true(forward.distance_to(wanted) < EPSILON, "forward %s" % forward)


func test_same_pair_gives_the_same_texture() -> void:
	var renderer := PortraitRenderer.new()  # not in the tree: nothing is rendered
	var a := renderer.portrait(&"m1a2_sepv3", 0, null)
	var b := renderer.portrait(&"m1a2_sepv3", 0, null)
	var other_owner := renderer.portrait(&"m1a2_sepv3", 1, null)
	assert_true(a == b)
	assert_true(a != other_owner)
	assert_false(renderer.is_ready(&"m1a2_sepv3", 0))
	renderer.free()


func test_visible_aabb_skips_hidden_nodes() -> void:
	var root := Node3D.new()
	var shown := MeshInstance3D.new()
	shown.mesh = BoxMesh.new()
	root.add_child(shown)
	var hidden := MeshInstance3D.new()
	hidden.mesh = BoxMesh.new()
	hidden.position = Vector3(10, 0, 0)
	hidden.visible = false
	root.add_child(hidden)
	assert_true(PortraitRenderer.visible_aabb(root).size.is_equal_approx(Vector3.ONE))
	root.free()
