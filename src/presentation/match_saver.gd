class_name MatchSaver
extends RefCounted
## Writes a MatchRecord as JSON to disk (F5 and the automatic save on game_over).

const LAST_MATCH_PATH := "user://matches/last_match.json"


## Saves `record` to `path`, creating missing folders. Returns OK or the failing Error
## (push_error is called on failure).
static func save(record: MatchRecord, path: String = LAST_MATCH_PATH) -> Error:
	var dir := ProjectSettings.globalize_path(path.get_base_dir())
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		push_error("Cannot create folder %s: %s" % [dir, error_string(err)])
		return err
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		err = FileAccess.get_open_error()
		push_error("Cannot write %s: %s" % [path, error_string(err)])
		return err
	file.store_string(record.to_json())
	file.close()
	return OK
