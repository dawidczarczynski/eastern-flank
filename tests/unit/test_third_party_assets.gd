extends TestCase
## Guards downloaded third-party assets (ADR 0011): every file under assets/third_party/
## is credited in credits.json, CC0 only, within the size budget.

const ROOT := "res://assets/third_party"
const MANIFEST_PATH := ROOT + "/credits.json"
const REQUIRED_KEYS: Array[String] = [
	"id", "kind", "title", "author", "source_url", "license", "downloaded", "files", "notes"
]
const KINDS: Array[String] = ["hdri", "textures", "models"]
const LICENSE := "CC0-1.0"
const MAX_TOTAL_BYTES := 80 * 1024 * 1024
const MAX_IMAGE_SIDE := 2048
const MAX_HDRI_SIDE := 4096
const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "tga", "bmp", "hdr", "exr"]


## Parsed manifest entries; fails the test if the file is missing or not a JSON array.
func _read_manifest() -> Array:
	assert_true(FileAccess.file_exists(MANIFEST_PATH), "missing " + MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert_true(parsed is Array, "credits.json must be a JSON array")
	return parsed if parsed is Array else []


## Paths relative to ROOT of all files that must be credited, sorted.
func _files_on_disk(dir_path: String = ROOT, prefix: String = "") -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.include_hidden = true
	for file_name in dir.get_files():
		var relative := prefix + file_name
		if relative == "credits.json" or file_name.ends_with(".import") or file_name == ".gdignore":
			continue
		result.append(relative)
	for sub in dir.get_directories():
		result.append_array(_files_on_disk(dir_path + "/" + sub, prefix + sub + "/"))
	result.sort()
	return result


## Problems with the manifest against the files on disk (structure, licence, coverage).
## Pure: does not read files, so it can be tested with made-up data.
func _manifest_problems(manifest: Array, files_on_disk: Array[String]) -> Array[String]:
	var problems: Array[String] = []
	var listed := {}
	var ids := {}
	for entry: Variant in manifest:
		if not entry is Dictionary:
			problems.append("entry is not an object: %s" % str(entry))
			continue
		var id := str(entry.get("id", "?"))
		for key in REQUIRED_KEYS:
			if not entry.has(key):
				problems.append("%s: missing key '%s'" % [id, key])
		if ids.has(id):
			problems.append("%s: duplicate id" % id)
		ids[id] = true
		if entry.get("license") != LICENSE:
			problems.append("%s: license must be %s" % [id, LICENSE])
		var kind := str(entry.get("kind", ""))
		if not kind in KINDS:
			problems.append("%s: unknown kind '%s'" % [id, kind])
		var files: Variant = entry.get("files", [])
		if not files is Array or (files as Array).is_empty():
			problems.append("%s: 'files' must be a non-empty array" % id)
			continue
		for file: Variant in files:
			var path := str(file)
			if not path.begins_with(kind + "/"):
				problems.append("%s: %s is not in the '%s/' folder" % [id, path, kind])
			if listed.has(path):
				problems.append("%s: %s is also listed by %s" % [id, path, listed[path]])
			listed[path] = id
			if not path in files_on_disk:
				problems.append("%s: listed file %s does not exist" % [id, path])
	for path in files_on_disk:
		if not listed.has(path):
			problems.append("%s is not listed in credits.json" % path)
	return problems


func test_manifest_matches_files() -> void:
	var problems := _manifest_problems(_read_manifest(), _files_on_disk())
	assert_eq(problems, [] as Array[String], "\n".join(problems))


func test_total_size_within_budget() -> void:
	var total := 0
	for path in _files_on_disk():
		var file := FileAccess.open(ROOT + "/" + path, FileAccess.READ)
		if file != null:
			total += file.get_length()
	assert_true(
		total <= MAX_TOTAL_BYTES,
		(
			"assets/third_party is %.1f MB, budget %d MB"
			% [total / 1048576.0, MAX_TOTAL_BYTES / 1048576]
		)
	)


func test_image_resolution_within_budget() -> void:
	for path in _files_on_disk():
		if not path.get_extension().to_lower() in IMAGE_EXTENSIONS:
			continue
		# Load the raw file (not the imported resource) to measure the source resolution.
		var image := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "/" + path))
		assert_true(image != null, "cannot load image " + path)
		if image == null:
			continue
		var limit := MAX_HDRI_SIDE if path.begins_with("hdri/") else MAX_IMAGE_SIDE
		var side := maxi(image.get_width(), image.get_height())
		assert_true(side <= limit, "%s is %d px, limit %d px" % [path, side, limit])


func _valid_entry() -> Dictionary:
	return {
		"id": "grass_01",
		"kind": "textures",
		"title": "Grass 01",
		"author": "Someone",
		"source_url": "https://ambientcg.com/view?id=Grass001",
		"license": LICENSE,
		"downloaded": "2026-10-22",
		"files": ["textures/grass_01/albedo.jpg"],
		"notes": "",
	}


func test_validator_accepts_valid_manifest() -> void:
	var files: Array[String] = ["textures/grass_01/albedo.jpg"]
	assert_eq(_manifest_problems([_valid_entry()], files), [] as Array[String])


func test_validator_accepts_empty_manifest() -> void:
	assert_eq(_manifest_problems([], [] as Array[String]), [] as Array[String])


func test_validator_rejects_unlisted_file() -> void:
	var files: Array[String] = ["textures/grass_01/albedo.jpg", "textures/grass_01/normal_gl.jpg"]
	assert_eq(_manifest_problems([_valid_entry()], files).size(), 1)


func test_validator_rejects_missing_file() -> void:
	assert_eq(_manifest_problems([_valid_entry()], [] as Array[String]).size(), 1)


func test_validator_rejects_file_listed_twice() -> void:
	var other := _valid_entry()
	other["id"] = "grass_02"
	var files: Array[String] = ["textures/grass_01/albedo.jpg"]
	assert_eq(_manifest_problems([_valid_entry(), other], files).size(), 1)


func test_validator_rejects_non_cc0_license() -> void:
	var entry := _valid_entry()
	entry["license"] = "CC-BY-4.0"
	var files: Array[String] = ["textures/grass_01/albedo.jpg"]
	assert_eq(_manifest_problems([entry], files).size(), 1)


func test_validator_rejects_missing_key() -> void:
	var entry := _valid_entry()
	entry.erase("author")
	var files: Array[String] = ["textures/grass_01/albedo.jpg"]
	assert_eq(_manifest_problems([entry], files).size(), 1)


func test_validator_rejects_unknown_kind_and_folder_mismatch() -> void:
	var entry := _valid_entry()
	entry["kind"] = "hdri"
	var files: Array[String] = ["textures/grass_01/albedo.jpg"]
	assert_eq(_manifest_problems([entry], files).size(), 1, "kind does not match the folder")
	entry["kind"] = "sounds"
	assert_eq(_manifest_problems([entry], files).size(), 2, "unknown kind + folder mismatch")
