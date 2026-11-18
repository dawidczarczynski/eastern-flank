extends SceneTree
## Headless test runner. Usually run via tools/test.sh.
## Env: TEST_FAST=1 skips the tests of tests/slow_tests.txt; TEST_TIMES=1 also prints
## "  TIME <ms> <label>" per test; TEST_SHARD="i/n" runs only a balanced share of the test files
## (tests/shard_weights.json; tools/test.sh runs the shards in parallel).
## Manually: godot --headless --path . --script res://tests/run_tests.gd -- [filter]
## The filter matches a substring of "file.gd:test_name".

const TEST_DIRS := ["res://tests/unit", "res://tests/integration"]
const WEIGHT_DEFAULT_MS := 300


func _initialize() -> void:
	# Tests write nothing into the player's cache folder (the cache tests use their own).
	TerrainTextures.cache_dir = ""
	MeshLods.cache_dir = ""
	var args := OS.get_cmdline_user_args()
	var filter: String = args[0] if args.size() > 0 else ""
	var total := 0
	var failed := 0
	var timing := OS.get_environment("TEST_TIMES") != ""
	var shard := OS.get_environment("TEST_SHARD").split("/")
	var shard_index := int(shard[0]) if shard.size() == 2 else 0
	var shard_count := int(shard[1]) if shard.size() == 2 else 1
	var shard_files := _shard_files(shard_index, shard_count)
	# --fast (TEST_FAST=1) leaves out the tests of tests/slow_tests.txt, unless a filter picks tests.
	var skip_slow := OS.get_environment("TEST_FAST") != "" and filter == ""
	var slow_tests := FileAccess.get_file_as_string("res://tests/slow_tests.txt").split("\n")
	var skipped := 0

	for dir_path: String in TEST_DIRS:
		for path in _list_test_files(dir_path):
			if not shard_files.has(path):
				continue
			var script: GDScript = load(path)
			var seen := {}
			var methods: Array[String] = []
			for method in script.get_script_method_list():
				var method_name: String = method["name"]
				if not method_name.begins_with("test_") or seen.has(method_name):
					continue
				seen[method_name] = true
				var label := "%s:%s" % [path.get_file(), method_name]
				if skip_slow and slow_tests.has(label):
					skipped += 1
				elif filter == "" or label.contains(filter):
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

	if skipped > 0:
		print("SKIPPED_SLOW %d" % skipped)
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)


## least loaded shard (weights: [all, without slow tests] ms per file in
## tests/shard_weights.json, tools/shard_weights.py refreshes it; unknown files count as
## WEIGHT_DEFAULT_MS), so the processes finish together.
## refreshes it; unknown files count as WEIGHT_DEFAULT_MS), so the processes finish together.
func _shard_files(index: int, count: int) -> Dictionary:
	var weights: Dictionary = {}
	var json_text := FileAccess.get_file_as_string("res://tests/shard_weights.json")
	if json_text != "":
		weights = JSON.parse_string(json_text)
	var files: Array[String] = []
	for dir_path: String in TEST_DIRS:
		files.append_array(_list_test_files(dir_path))
	var column := 1 if OS.get_environment("TEST_FAST") != "" else 0
	var weight_of := func(path: String) -> int:
		var pair: Array = weights.get(path.get_file(), [])
		return int(pair[column]) if pair.size() == 2 else WEIGHT_DEFAULT_MS
	# Sorted by weight, then by path: the same order in every shard process.
	files.sort_custom(
		func(a: String, b: String) -> bool:
			var wa: int = weight_of.call(a)
			var wb: int = weight_of.call(b)
			return wa > wb or (wa == wb and a < b)
	)
	var load_ms: Array[int] = []
	load_ms.resize(count)
	load_ms.fill(0)
	var mine := {}
	for path in files:
		var lightest := 0
		for i in count:
			if load_ms[i] < load_ms[lightest]:
				lightest = i
		load_ms[lightest] += weight_of.call(path)
		if lightest == index:
			mine[path] = true
	return mine


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
