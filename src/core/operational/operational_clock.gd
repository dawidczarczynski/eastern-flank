class_name OperationalClock
extends RefCounted
## Calendar of an operation (TASK-093b): `turn` is one 12 h period in which both blocs move.
## Odd turns are day (06:00–18:00), even turns night (18:00–06:00). Turn 1 starts on the
## operation's start date at 06:00.

const DAY := "06:00–18:00"
const NIGHT := "18:00–06:00"
const SECONDS_PER_DAY := 86400
## Turns (12 h each) per calendar day.
const TURNS_PER_DAY := 2


static func is_day(turn: int) -> bool:
	return turn % 2 == 1


static func time_of_day(turn: int) -> String:
	return DAY if is_day(turn) else NIGHT


## ISO date (YYYY-MM-DD) on which `turn` starts; "" when `start_date` is empty or not a date.
static func date(turn: int, start_date: String) -> String:
	if start_date == "":
		return ""
	var parts := start_date.split("-")
	if parts.size() != 3 or not (parts[0].is_valid_int() and parts[1].is_valid_int()):
		return ""
	if not parts[2].is_valid_int():
		return ""
	var start := Time.get_unix_time_from_datetime_dict(
		{"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]), "hour": 6}
	)
	var seconds := start + (turn - 1) * (SECONDS_PER_DAY / TURNS_PER_DAY)
	return Time.get_date_string_from_unix_time(seconds)
