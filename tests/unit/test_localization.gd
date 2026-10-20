extends TestCase

const CSV_PATH := "res://assets/i18n/strings.csv"

var _previous_locale: String


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)


## Returns all data rows (without the header) as PackedStringArray.
func _read_rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	assert_true(file != null, "cannot open " + CSV_PATH)
	if file == null:
		return rows
	var header := file.get_csv_line()
	assert_eq(header, PackedStringArray(["keys", "en", "pl"]), "CSV header")
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue  # trailing empty line
		rows.append(row)
	return rows


## Sorted list of printf placeholders (%d, %s, %%) in the text.
func _placeholders(text: String) -> Array[String]:
	var regex := RegEx.create_from_string("%[ds%]")
	var result: Array[String] = []
	for m in regex.search_all(text):
		result.append(m.get_string())
	result.sort()
	return result


func test_csv_integrity() -> void:
	var rows := _read_rows()
	assert_true(rows.size() > 0, "CSV has rows")
	var seen := {}
	for row in rows:
		assert_eq(row.size(), 3, "field count in row %s" % str(row))
		if row.size() != 3:
			continue
		for field in row:
			assert_false(field.strip_edges().is_empty(), "empty field in row %s" % str(row))
		assert_false(seen.has(row[0]), "duplicate key '%s'" % row[0])
		seen[row[0]] = true
		var expected := _placeholders(row[0])
		assert_eq(_placeholders(row[1]), expected, "en placeholders for '%s'" % row[0])
		assert_eq(_placeholders(row[2]), expected, "pl placeholders for '%s'" % row[0])


func test_all_source_literals_are_keys() -> void:
	var keys := {}
	for row in _read_rows():
		keys[row[0]] = true
	var regex := RegEx.create_from_string(
		'(?:\\btr|\\b_t|\\bTranslationServer\\.translate)\\("((?:[^"\\\\]|\\\\.)*)"\\)'
	)
	var found := 0
	for path in _list_scripts("res://src"):
		var text := FileAccess.get_file_as_string(path)
		for m in regex.search_all(text):
			found += 1
			var literal := m.get_string(1)
			assert_true(keys.has(literal), "%s: '%s' is not in the CSV" % [path, literal])
	assert_true(found > 0, "scan found at least one literal")


func test_polish_translations() -> void:
	TranslationServer.set_locale("pl")
	assert_eq(String(TranslationServer.translate("End turn")), "Zakończ turę")
	assert_eq(String(TranslationServer.translate("CLASS_INFANTRY")), "Piechota")
	assert_eq(String(TranslationServer.translate("Ready")), "Gotowa do działania")


func test_english_translations() -> void:
	TranslationServer.set_locale("en")
	assert_eq(String(TranslationServer.translate("End turn")), "End turn")
	assert_eq(String(TranslationServer.translate("CLASS_INFANTRY")), "Infantry")
	assert_eq(String(TranslationServer.translate("Ready")), "Ready")


func test_unknown_key_translates_to_itself() -> void:
	TranslationServer.set_locale("pl")
	assert_eq(String(TranslationServer.translate("__missing__")), "__missing__")


func _list_scripts(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.ends_with(".gd"):
			result.append(dir_path.path_join(file))
	for sub in dir.get_directories():
		result.append_array(_list_scripts(dir_path.path_join(sub)))
	return result
