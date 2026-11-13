extends TestCase

## Any small resource: the loader hands whatever it loaded to `swap`.
const SMALL_RESOURCE := "res://data/battle/conditions.tres"
const POLL_LIMIT := 2000


func _loader(path: String, operation_name := "") -> SceneLoader:
	var loader := SceneLoader.new()
	loader.start(path, operation_name)
	return loader


func _poll_until_done(loader: SceneLoader) -> void:
	for i in POLL_LIMIT:
		if loader.poll():
			return
		OS.delay_msec(5)


func test_open_without_a_tree_does_nothing() -> void:
	assert_eq(SceneLoader.open(null, SMALL_RESOURCE), null)


func test_loading_screen_is_up_at_once_with_the_operation_name() -> void:
	var loader := _loader(SMALL_RESOURCE, "Suwalki Gap")
	assert_true(loader.is_loading())
	assert_eq(loader.screen().get_parent(), loader as Node)
	assert_eq(loader.screen().operation_text(), "SUWALKI GAP")
	assert_true(loader.screen().status_text() != "")
	_poll_until_done(loader)
	loader.free()


func test_hands_the_loaded_scene_over_once() -> void:
	var loader := _loader(SMALL_RESOURCE)
	var got: Array[Resource] = []
	loader.swap = func(scene: Resource) -> void: got.append(scene)
	_poll_until_done(loader)
	assert_false(loader.is_loading())
	assert_eq(got.size(), 1)
	assert_true(got[0] != null and got[0].resource_path == SMALL_RESOURCE)
	assert_true(loader.poll(), "a later poll stays done")
	assert_eq(got.size(), 1, "and does not change the scene again")
	loader.free()


func test_the_battle_scene_loads_through_the_loader() -> void:
	var loader := _loader(Session.BATTLE_SCENE)
	var got: Array[Resource] = []
	loader.swap = func(scene: Resource) -> void: got.append(scene)
	_poll_until_done(loader)
	assert_eq(got.size(), 1)
	assert_true(got[0] is PackedScene)
	loader.free()
