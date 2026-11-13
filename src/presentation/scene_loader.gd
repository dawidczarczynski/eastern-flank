class_name SceneLoader
extends CanvasLayer
## Opens a heavy scene without freezing the window: the loading screen goes up at once, the
## scene (and the few hundred scripts behind it) loads on a ResourceLoader thread, and the
## scene changes when it is ready. A plain `change_scene_to_file` blocks the old scene for the
## whole load – over ten seconds for the battle on a slow disk – with nothing on screen.
## The battle scene puts up the same LoadingScreen in its `_ready`, so the two read as one;
## this one stays for LINGER_FRAMES after the change to cover the hand-over.
## Usage: SceneLoader.open(get_tree(), Session.BATTLE_SCENE, setup.operation_name)

const STATUS := "BUILDING THE BATTLEFIELD"
const LAYER := 100
const LINGER_FRAMES := 2

## Called with the loaded scene instead of `SceneTree.change_scene_to_packed` (tests).
var swap := Callable()
var _path := ""
var _operation_name := ""
var _screen: LoadingScreen
var _linger := -1  # frames left before the loader frees itself; -1 while loading


## Starts loading `path` and covers `tree`'s window with the loading screen; null without a
## tree (headless tests). `operation_name` is the untranslated name the screen shows ("" = the
## game title).
static func open(tree: SceneTree, path: String, operation_name := "") -> SceneLoader:
	if tree == null:
		return null
	var loader := SceneLoader.new()
	loader.start(path, operation_name)
	tree.root.add_child(loader)
	return loader


## Requests the threaded load; `open` calls it.
func start(path: String, operation_name := "") -> void:
	name = "SceneLoader"
	layer = LAYER
	_path = path
	_operation_name = operation_name
	_screen = LoadingScreen.new()
	_screen.set_operation(operation_name)
	_screen.set_status(STATUS)
	add_child(_screen)
	if ResourceLoader.load_threaded_request(path) != OK:
		push_warning("SceneLoader: no threaded load of %s, loading it directly" % path)


func screen() -> LoadingScreen:
	return _screen


func is_loading() -> bool:
	return _linger < 0


## Checks the load once: changes the scene when it has finished (a failed threaded load falls
## back to a blocking one). True once the scene was handed over.
func poll() -> bool:
	if not is_loading():
		return true
	var status := ResourceLoader.load_threaded_get_status(_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return false
	var scene: Resource = null
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		scene = ResourceLoader.load_threaded_get(_path)
	if scene == null:
		scene = load(_path)
	_linger = LINGER_FRAMES
	if swap.is_valid():
		swap.call(scene)
	elif scene is PackedScene and is_inside_tree():
		get_tree().change_scene_to_packed(scene as PackedScene)
	return true


func _process(_delta: float) -> void:
	if not poll():
		return
	_linger -= 1
	if _linger < 0:
		set_process(false)
		queue_free()


## The old scene is still alive under the screen: it must not react to keys while loading.
func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
