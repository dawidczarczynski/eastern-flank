extends SceneTree
## Headless test runner. Usually run via tools/test.sh.
## Manually: godot --headless --path . --script res://tests/run_tests.gd -- [filter]
## The filter matches a substring of "file.gd:test_name".

const TEST_DIRS := ["res://tests/unit", "res://tests/integration"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var filter: String = args[0] if args.size() > 0 else ""
	var total := 0
	var failed := 0

	for dir_path: String in TEST_DIRS:
		for path in _list_test_files(dir_path):
			var script: GDScript = load(path)
			var seen := {}
			for method in script.get_script_method_list():
				var method_name: String = method["name"]
				if not method_name.begins_with("test_") or seen.has(method_name):
					continue
				seen[method_name] = true
				var label := "%s:%s" % [path.get_file(), method_name]
				if filter != "" and not label.contains(filter):
					continue
				var instance: TestCase = script.new()
				instance.before_each()
				instance.call(method_name)
				total += 1
				if instance.failures.is_empty():
					print("  PASS ", label)
				else:
					failed += 1
					print("  FAIL ", label)
					for failure in instance.failures:
						print("       - ", failure)

	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)


func _list_test_files(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			result.append(dir_path.path_join(file))
	result.sort()
	return result
