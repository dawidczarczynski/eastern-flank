class_name StaffMapJournalText
extends RefCounted
## Pure texts of the operational journal window (TASK-148b, docs/design/operational_map/
## operational_journal.html, variant A): the sentence of every journal entry kind in the words of
## the viewing side ("We struck ...", "Enemy ... on our airfield"; never NATO / Russia), the tag,
## the side shape, the place line and the turn header. Reads an `OperationalJournal.Entry` and the
## state; no nodes, no rules. Political lines are bare effects, never who decided.
##
## A line model: {tag, side (&"own" / &"enemy" / &"neutral"), parts: [[text, style], ...], place}.
## Styles of a part: &"plain", &"bold" (means), &"hit" (amber), &"icpt" (intercepted), &"bad".

const PLAIN := &"plain"
const BOLD := &"bold"
const HIT := &"hit"
const ICPT := &"icpt"
const BAD := &"bad"

const OWN := &"own"
const ENEMY := &"enemy"
const NEUTRAL := &"neutral"

## Filter ids of the chips, in display order; "" = all.
const FILTERS: Array[StringName] = [&"", &"strike", &"battle", &"move", &"politics"]
const TAGS := {&"strike": "STR", &"battle": "BTL", &"move": "MOV", &"politics": "POL"}
const FILTER_LABELS := {
	&"": "ALL",
	&"strike": "STRIKES",
	&"battle": "BATTLES",
	&"move": "MOVES",
	&"politics": "POLITICS"
}
## "our airfield" etc.: the viewer's own installation hit by an enemy strike (a whole phrase, so
## languages with grammatical gender can agree the possessive).
const OWN_CLASS_NOUNS := {
	&"formation": "JRN_OUR_FORMATION",
	&"air_defence": "JRN_OUR_AIR_DEFENCE",
	&"depot": "JRN_OUR_DEPOT",
	&"airfield": "JRN_OUR_AIRFIELD",
	&"c2": "JRN_OUR_C2",
}
const CLASS_NOUNS := {
	&"formation": "JRN_CLASS_FORMATION",
	&"air_defence": "JRN_CLASS_AIR_DEFENCE",
	&"depot": "JRN_CLASS_DEPOT",
	&"airfield": "JRN_CLASS_AIRFIELD",
	&"c2": "JRN_CLASS_C2",
}


## The model of one entry for `viewer`. `namer` is the place namer ((Vector2i) -> String, may be
## invalid: the place line then falls back to the hex number).
static func line(
	entry: OperationalJournal.Entry, viewer: int, state: OperationalState, namer := Callable()
) -> Dictionary:
	var parts: Array = _parts(entry, viewer, state)
	return {
		"tag": TAGS.get(entry.category, ""),
		"side": _side(entry, viewer, state),
		"parts": parts,
		"place": place_line(entry, namer),
		"category": entry.category,
		"kind": entry.kind,
	}


## The sentence as plain text (tests, tooltips).
static func plain(parts: Array) -> String:
	var text := ""
	for part: Array in parts:
		text += part[0]
	return text


## The sentence as BBCode; `colours` maps a style to a Color (plain / bold use the default).
static func bbcode(parts: Array, colours: Dictionary) -> String:
	var text := ""
	for part: Array in parts:
		var style: StringName = part[1]
		var escaped := (part[0] as String).replace("[", "[lb]")
		if colours.has(style):
			var colour: Color = colours[style]
			text += "[color=#%s]%s[/color]" % [colour.to_html(false), escaped]
		else:
			text += escaped
	return text


## "SEJNY · 3 KM NORTH" style place line; "" for an entry without a place.
static func place_line(entry: OperationalJournal.Entry, namer: Callable) -> String:
	if not entry.has_coord:
		return ""
	var named := StaffMapPlaceName.named(namer, entry.coord)
	return named if named != "" else StaffMapTurnReport.place_text(entry.coord)


## True when `entry` passes the chip `filter` ("" = all).
static func matches(entry: OperationalJournal.Entry, filter: StringName) -> bool:
	return filter == &"" or entry.category == filter


## Header of a turn: {title: "TURN 5", date: "14 JUN", range: "DAY 06–18", text: both joined}.
static func turn_header(turn: int, state: OperationalState) -> Dictionary:
	var iso := OperationalClock.date(turn, state.start_date)
	var date := ""
	var parts := iso.split("-")
	if parts.size() == 3:
		date = ("%d %s" % [int(parts[2]), StaffMapTurnBar.MONTHS[clampi(int(parts[1]) - 1, 0, 11)]])
	var hours := OperationalClock.time_of_day(turn).replace(":00", "")
	var range_text := "%s %s" % [_t("DAY") if OperationalClock.is_day(turn) else _t("NIGHT"), hours]
	return {
		"title": "%s %d" % [_t("TURN"), turn],
		"date": date,
		"range": range_text,
		"text": range_text if date == "" else "%s · %s" % [date, range_text],
	}


static func empty_text() -> String:
	return _t(
		"Nothing has happened yet. Orders you issue and strikes you launch are recorded here."
	)


static func filtered_empty_text() -> String:
	return _t("Nothing under this filter")


# --- sentences -------------------------------------------------------------------------------


static func _parts(entry: OperationalJournal.Entry, viewer: int, state: OperationalState) -> Array:
	var a := entry.args
	match entry.kind:
		&"formation_moved":
			return _plain(_t("%s moved") % _who(a, "formation_id", viewer, state, entry.actor))
		&"formation_halted":
			var who := _who(a, "formation_id", viewer, state, entry.actor)
			var reason := String(a.get("reason", ""))
			if reason == "contact":
				return _plain(_t("%s halted on contact") % who)
			if reason == "forbidden":
				return _plain(_t("%s halted at a closed border") % who)
			return _plain(_t("%s halted") % who)
		&"order_completed":
			return _plain(_t("%s arrived") % _who(a, "formation_id", viewer, state, entry.actor))
		&"order_interrupted":
			var why := StaffMapTurnReport.kind_text(
				StaffMapTurnMarks.INTERRUPTED, StringName(a.get("reason", ""))
			)
			return _plain(
				"%s: %s" % [_who(a, "formation_id", viewer, state, entry.actor), _lower_first(why)]
			)
		&"order_issued":
			var posture := _t("POSTURE_" + String(a.get("posture", "")).to_upper())
			return _plain(
				(
					_t("%s ordered to move (%s)")
					% [_who(a, "formation_id", viewer, state, entry.actor), posture.to_lower()]
				)
			)
		&"order_cancelled":
			return _plain(
				_t("%s: order cancelled") % _who(a, "formation_id", viewer, state, entry.actor)
			)
		&"posture_changed":
			var posture := _t("POSTURE_" + String(a.get("posture", "")).to_upper())
			return _plain(
				(
					_t("%s changed posture to %s")
					% [_who(a, "formation_id", viewer, state, entry.actor), posture.to_lower()]
				)
			)
		&"contact_forbidden":
			return _plain(
				(
					_t("%s stopped at the closed border of %s")
					% [
						_who(a, "attacker_id", viewer, state, entry.actor),
						_country(state, StringName(a.get("country", "")))
					]
				)
			)
		&"formation_joined":
			return _plain(
				(
					_t("%s joined (%s)")
					% [
						_who(a, "formation_id", viewer, state, entry.actor),
						_country(state, StringName(a.get("country", "")))
					]
				)
			)
		&"battle_pending":
			return _plain(
				(
					_t("Contact: %s and %s")
					% [
						_who(a, "attacker_id", viewer, state, -1),
						_who(a, "defender_id", viewer, state, -1)
					]
				)
			)
		&"battle_resolved":
			return _battle_resolved(a, viewer, state)
		&"battle_consequences":
			return _battle_consequences(a, viewer)
		&"formation_retreated":
			var who := _who(a, "formation_id", viewer, state, -1)
			if a.get("blocked", false):
				return [[_t("%s could not retreat") % who, PLAIN]]
			return _plain(_t("%s retreated one hex") % who)
		&"formation_destroyed":
			return [
				[
					(
						_t("%s was destroyed")
						% _who(a, "formation_id", viewer, state, int(a.get("player", -1)))
					),
					BAD
				]
			]
		&"strike":
			return _strike(entry, viewer, state)
		&"stance_changed":
			return _plain(_stance(a, viewer, state))
		&"level_changed":
			var level := int(a.get("level", 0))
			if a.get("cause", "") == "calm":
				return _plain(_t("Calm: level %d → %d") % [int(a.get("previous", 0)), level])
			var ladder := state.ladder
			if ladder == null or ladder.levels.is_empty():
				return _plain(_t("Escalation level %d") % level)
			return _plain(
				_t("Escalation level %d: %s") % [level, StaffMapEscalation.level_name(state, level)]
			)
		&"decision":
			var text := (
				_t("Decision: %s")
				% _t(StaffMapDecisionsModel.TITLES.get(StringName(a.get("decision", "")), ""))
			)
			var country := _country(state, StringName(a.get("country", "")))
			return _plain(text if country == "" else "%s · %s" % [text, country])
		&"sanctuary_breach":
			return _plain(
				_t("Sanctuary breached: %s") % _country(state, StringName(a.get("country", "")))
			)
		&"casus_belli":
			return _plain(
				_t("Casus belli over %s") % _country(state, StringName(a.get("country", "")))
			)
		&"operation_ended":
			var winner := int(a.get("winner", -1))
			if winner < 0:
				return [[_t("The operation ended: nobody won"), BAD]]
			if winner == viewer:
				return _plain(_t("The operation ended: we won"))
			return [[_t("The operation ended: we lost"), BAD]]
	return _plain(String(entry.kind))


static func _strike(entry: OperationalJournal.Entry, viewer: int, state: OperationalState) -> Array:
	var a := entry.args
	var own := entry.actor == viewer
	var means := String(a.get("means", ""))
	var definition: StrikeMeansDefinition = state.strike_means.get(StringName(means))
	if definition != null:
		means = _t(definition.display_name)
	var noun := _t(CLASS_NOUNS.get(StringName(a.get("class_id", "")), "JRN_CLASS_FORMATION"))
	var count := "%s ×%d" % [means, int(a.get("count", 1))]
	var own_noun := _t(OWN_CLASS_NOUNS.get(StringName(a.get("class_id", "")), "JRN_OUR_FORMATION"))
	var parts: Array = []
	if own:
		parts.append([_t("We struck the enemy %s with ") % noun, PLAIN])
		parts.append([count, BOLD])
	else:
		parts.append([_t("Enemy "), PLAIN])
		parts.append([count, BOLD])
		parts.append([_t(" on %s") % own_noun, PLAIN])
	parts.append([": ", PLAIN])
	var hits := int(a.get("hits", 0))
	var intercepted := int(a.get("intercepted", 0))
	if hits > 0:
		parts.append([_t("%d hit") % hits, HIT])
	else:
		parts.append([_t("no hit"), PLAIN])
	if intercepted > 0:
		parts.append([", ", PLAIN])
		parts.append([_t("%d intercepted") % intercepted, ICPT])
	if a.get("target_destroyed", false):
		parts.append([" – ", PLAIN])
		parts.append([_t("target destroyed"), BAD])
	elif a.has("before") and a.has("after") and int(a["after"]) < int(a["before"]):
		var what := _t("strength") if a.get("class_id", "") == "formation" else _t("integrity")
		parts.append([", %s %d → " % [what, int(a["before"])], PLAIN])
		parts.append([str(int(a["after"])), BAD])
	return parts


static func _battle_resolved(a: Dictionary, viewer: int, state: OperationalState) -> Array:
	var mine := _own_of(a, viewer, state)
	var theirs := _enemy_of(a, viewer, state)
	var winner := int(a.get("winner", -1))
	if winner == viewer:
		return _plain(_t("%s won the battle against %s") % [mine, theirs])
	if winner >= 0:
		return [[_t("%s lost the battle against %s") % [mine, theirs], BAD]]
	return _plain(_t("The battle between %s and %s ended in a draw") % [mine, theirs])


static func _battle_consequences(a: Dictionary, viewer: int) -> Array:
	var losses: Array = a.get("losses", [0, 0])
	var ours := int(losses[viewer]) if losses.size() > viewer else 0
	var theirs := int(losses[1 - viewer]) if losses.size() > 1 - viewer else 0
	var text := _t("Losses: ours %d, enemy %d") % [ours, theirs]
	var holder := int(a.get("field_holder", -1))
	if holder == viewer:
		text += ". " + _t("We hold the field")
	elif holder >= 0:
		text += ". " + _t("Enemy holds the field")
	return _plain(text)


static func _stance(a: Dictionary, viewer: int, state: OperationalState) -> String:
	var country := _country(state, StringName(a.get("country", "")))
	var side := int(a.get("side", -1))
	var ours := side == viewer
	match StringName(a.get("stance", "")):
		CountryState.NEUTRAL:
			return _t("%s became neutral") % country
		CountryState.ALIGNED:
			if side < 0:
				return _t("%s changed its stance") % country
			return (
				(_t("%s moved to our side") if ours else _t("%s moved to the enemy side")) % country
			)
		CountryState.BELLIGERENT:
			if side < 0:
				return _t("%s entered the war") % country
			return (
				(
					_t("%s entered the war on our side")
					if ours
					else _t("%s entered the war on the enemy side")
				)
				% country
			)
	return _t("%s changed its stance") % country


# --- helpers ---------------------------------------------------------------------------------


static func _side(
	entry: OperationalJournal.Entry, viewer: int, state: OperationalState
) -> StringName:
	if entry.category == &"politics":
		return NEUTRAL
	if entry.kind == &"battle_resolved":
		var winner := int(entry.args.get("winner", -1))
		if winner < 0:
			return NEUTRAL
		return OWN if winner == viewer else ENEMY
	if entry.kind == &"battle_consequences":
		return NEUTRAL
	var owner := entry.actor
	if owner < 0 and entry.args.has("formation_id"):
		var f := state.get_formation(StringName(entry.args["formation_id"]))
		owner = f.owner_id if f != null else int(entry.args.get("player", -1))
	if owner < 0:
		return NEUTRAL
	return OWN if owner == viewer else ENEMY


## "Our 15th Bde" / "Enemy 11th Gds" for the formation id under `key`; `fallback_owner` names the
## side of a formation that is gone from the state (-1 = unknown).
static func _who(
	a: Dictionary, key: String, viewer: int, state: OperationalState, fallback_owner: int
) -> String:
	var f := state.get_formation(StringName(a.get(key, "")))
	var owner := f.owner_id if f != null else fallback_owner
	if f == null:
		if owner < 0:
			return _t("A formation")
		return _t("Our formation") if owner == viewer else _t("Enemy formation")
	var name := _t(f.display_name)
	return _t("Our %s") % name if owner == viewer else _t("Enemy %s") % name


## The viewer's own formation of a battle (attacker or defender).
static func _own_of(a: Dictionary, viewer: int, state: OperationalState) -> String:
	for key in ["attacker_id", "defender_id"]:
		var f := state.get_formation(StringName(a.get(key, "")))
		if f != null and f.owner_id == viewer:
			return _who(a, key, viewer, state, viewer)
	return _t("Our formation")


static func _enemy_of(a: Dictionary, viewer: int, state: OperationalState) -> String:
	for key in ["attacker_id", "defender_id"]:
		var f := state.get_formation(StringName(a.get(key, "")))
		if f != null and f.owner_id != viewer:
			return _who(a, key, viewer, state, 1 - viewer)
	return _t("Enemy formation")


static func _country(state: OperationalState, country_id: StringName) -> String:
	var country := state.get_country(country_id)
	if country == null:
		return String(country_id)
	return _t(country.definition.display_name)


static func _plain(text: String) -> Array:
	return [[text, PLAIN]]


static func _lower_first(text: String) -> String:
	return text.substr(0, 1).to_lower() + text.substr(1) if text != "" else text


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
