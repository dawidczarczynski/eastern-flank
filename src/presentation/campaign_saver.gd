class_name CampaignSaver
extends RefCounted
## Campaign saves on disk (TASK-094d, ADR 0015 §4): one CampaignRecord JSON per operation in
## `user://campaigns/<name>.json`. Writes are atomic (a temp file next to the save, then a rename),
## loading validates the file (CampaignRecord.from_json, then the fast replay) and reports a
## problem as a code – never a crash. Continue on the main menu loads the latest save.

const DIR := "user://campaigns"
const _TEMP_SUFFIX := ".tmp"


## Path of the save `save_name` in `dir`.
static func path_for(save_name: String, dir: String = DIR) -> String:
	return "%s/%s.json" % [dir, save_name]


## Writes `record` to `path` (creating the folder): the JSON goes to `<path>.tmp` first and is
## renamed over the old save, so a failed write never leaves a half file. OK or the Error.
static func save(record: CampaignRecord, path: String) -> Error:
	if record == null:
		return ERR_INVALID_PARAMETER
	var dir := ProjectSettings.globalize_path(path.get_base_dir())
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		push_error("Cannot create folder %s: %s" % [dir, error_string(err)])
		return err
	var temp := path + _TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		err = FileAccess.get_open_error()
		push_error("Cannot write %s: %s" % [temp, error_string(err)])
		return err
	file.store_string(record.to_json())
	file.close()
	err = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path)
	)
	if err != OK:
		push_error("Cannot rename %s to %s: %s" % [temp, path, error_string(err)])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	return err


## The most recently written save in `dir`; "" when there is none.
static func latest(dir: String = DIR) -> String:
	var access := DirAccess.open(dir)
	if access == null:
		return ""
	var best := ""
	var best_time := -1
	for file_name in access.get_files():
		if file_name.get_extension() != "json":
			continue
		var path := "%s/%s" % [dir, file_name]
		var time := FileAccess.get_modified_time(path)
		if time > best_time or (time == best_time and path < best):
			best = path
			best_time = time
	return best


## {"record": CampaignRecord, "simulation": OperationalSimulation, "error": ""} or, with record
## and simulation null, "error" = "unreadable" (no such file / cannot open), "corrupt" (not a
## campaign record of this version) or "replay_failed" (the operation cannot be rebuilt from it;
## "detail" is the replay's error code and reason).
static func load_campaign(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("unreadable", path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("unreadable", path)
	var record := CampaignRecord.from_json(file.get_as_text())
	file.close()
	if record == null:
		return _failure("corrupt", path)
	var replay := record.replay()
	if not replay["ok"]:
		return _failure("replay_failed", "%s %s" % [replay["error"], replay["reason"]])
	return {"record": record, "simulation": replay["simulation"], "error": "", "detail": ""}


## The player-facing text of a failed load (translated).
static func message(loaded: Dictionary) -> String:
	var error: String = loaded.get("error", "")
	if error == "":
		return ""
	return TranslationServer.translate("CAMPAIGN_LOAD_" + error.to_upper())


static func _failure(error: String, detail: String) -> Dictionary:
	return {"record": null, "simulation": null, "error": error, "detail": detail}
