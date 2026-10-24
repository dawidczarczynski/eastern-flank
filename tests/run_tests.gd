extends SceneTree
## Headless test runner. Usually run via tools/test.sh.
## Env: TEST_TIMES=1 also prints "  TIME <ms> <label>" per test; TEST_SHARD="i/n" runs only every
## n-th test file, starting at i (tools/test.sh runs shards in parallel).
## Manually: godot --headless --path . --script res://tests/run_tests.gd -- [filter]
## The filter matches a substring of "file.gd:test_name".

const TEST_DIRS := ["res://tests/unit", "res://tests/integration"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var filter: String = args[0] if args.size() > 0 else ""
	var total := 0
	var failed := 0
	var timing := OS.get_environment("TEST_TIMES") != ""
	var shard := OS.get_environment("TEST_SHARD").split("/")
	var shard_index := int(shard[0]) if shard.size() == 2 else 0
	var shard_count := int(shard[1]) if shard.size() == 2 else 1
	var file_index := 0

	for dir_path: String in TEST_DIRS:
		for path in _list_test_files(dir_path):
			file_index += 1
			if file_index % shard_count != shard_index:
				continue
			var script: GDScript = load(path)
			var seen := {}
			var methods: Array[String] = []
			for method in script.get_script_method_list():
				var method_name: String = method["name"]
				if not method_name.begins_with("test_") or seen.has(method_name):
					continue
				seen[method_name] = true
				if filter == "" or ("%s:%s" % [path.get_file(), method_name]).contains(filter):
					methods.append(method_name)
			if methods.is_empty():
				continue
			# before_all/after_all run once per file, only when one of its tests runs.
			var suite: TestCase = script.new()
			var started := Time.get_ticks_msec()
			suite.before_all()
			if timing:
				print(
					"  TIME %d %s:before_all" % [Time.get_ticks_msec() - started, path.get_file()]
				)
			for method_name in methods:
				var label := "%s:%s" % [path.get_file(), method_name]
				started = Time.get_ticks_msec()
				var instance: TestCase = script.new()
				instance.before_each()
				instance.call(method_name)
				instance.after_each()
				total += 1
				if timing:
					print("  TIME %d %s" % [Time.get_ticks_msec() - started, label])
				# Failures of before_all count against the file's first test.
				instance.failures.append_array(suite.failures)
				suite.failures.clear()
				if not _report(label, instance.failures):
					failed += 1
			suite.after_all()
			if not suite.failures.is_empty():
				_report("%s:after_all" % path.get_file(), suite.failures)
				failed += 1

	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)


## Prints PASS/FAIL for `label`; true when `failures` is empty.
func _report(label: String, failures: Array[String]) -> bool:
	if failures.is_empty():
		print("  PASS ", label)
		return true
	print("  FAIL ", label)
	for failure in failures:
		print("       - ", failure)
	return false


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
