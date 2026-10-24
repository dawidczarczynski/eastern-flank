class_name GameSettings
extends RefCounted
## User settings kept between runs in `user://settings.cfg` (TASK-084: the language). Only the
## presentation layer reads them; the simulation never sees a locale. Every function takes the
## file path so tests use a temp file.

const PATH := "user://settings.cfg"
const SECTION := "game"
const LOCALE_KEY := "locale"
## Available locales (assets/i18n/strings.csv columns) and the name each shows for itself.
const LOCALES: Array[String] = ["en", "pl"]
const LOCALE_NAMES := {"en": "English", "pl": "Polski"}


## The locale with a region stripped ("pl_PL" -> "pl"); "" when it is not one of LOCALES.
static func normalize(locale: String) -> String:
	var language := locale.split("_")[0].split("-")[0].to_lower()
	return language if language in LOCALES else ""


## The locale after `current` in LOCALES, wrapping around; an unknown one starts at the first.
static func next_locale(current: String) -> String:
	var index := LOCALES.find(normalize(current))
	return LOCALES[(index + 1) % LOCALES.size()]


## The stored locale; "" when there is no file, no entry or an unknown value.
static func load_locale(path: String = PATH) -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return ""
	return normalize(str(config.get_value(SECTION, LOCALE_KEY, "")))


## Stores the locale, keeping other entries of the file. Returns false when writing failed or
## the locale is unknown.
static func save_locale(locale: String, path: String = PATH) -> bool:
	if normalize(locale) == "":
		return false
	var config := ConfigFile.new()
	config.load(path)  # a missing file just starts a new one
	config.set_value(SECTION, LOCALE_KEY, normalize(locale))
	return config.save(path) == OK


## Switches the game language and stores the choice. Returns the locale now active.
static func set_locale(locale: String, path: String = PATH) -> String:
	var normalized := normalize(locale)
	if normalized == "":
		return normalize(TranslationServer.get_locale())
	TranslationServer.set_locale(normalized)
	save_locale(normalized, path)
	return normalized


## Applies the stored locale at start (nothing when none is stored). Returns the active locale.
static func apply_saved(path: String = PATH) -> String:
	var stored := load_locale(path)
	if stored != "":
		TranslationServer.set_locale(stored)
	return normalize(TranslationServer.get_locale())
