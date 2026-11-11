class_name StaffMapEscalation
extends RefCounted
## Pure texts and colours of the escalation ladder on the staff map (TASK-115): the chip, the
## toast of a change, the ladder window's collapse strips, and the end
## notice. Everything
## is read from `state.ladder` (data) and translated; nothing here changes the state.

const CALM_COLOUR := Color("#b9d38a")
## Cause -> translation key (the English text, it holds the side's placeholder).
const CAUSES := {
	&"decision": "raised by %s",
	&"declaration": "%s declared war",
	&"alliance": "%s called its allies",
	&"sanctuary_breach": "%s entered enemy sanctuary",
	&"urban_strike": "%s struck a town",
	&"stand_down": "%s stood down",
	&"nuclear_use": "%s used a nuclear weapon",
}
const CLASS_KEY_PREFIX := "ESC_CLASS_"


## Colour of `level` on the calm -> alert scale (interpolated between the two ends).
static func level_colour(level: int, top: int, palette: StaffMapPalette) -> Color:
	var t := clampf(float(level) / maxf(float(top), 1.0), 0.0, 1.0)
	return CALM_COLOUR.lerp(palette.ui_alert, t)


## "2 · Limited war" for the chip.
static func chip_text(state: OperationalState) -> String:
	return "%d · %s" % [state.escalation_level, level_name(state, state.escalation_level)]


## Translated name of ladder level `level`.
static func level_name(state: OperationalState, level: int) -> String:
	var levels := state.ladder.levels
	return TranslationServer.translate(levels[clampi(level, 0, levels.size() - 1)].display_name)


## "Formations, air defence, ..." allowed to be struck at `level`, "Nothing" for none.
static func roe_text(state: OperationalState, level: int) -> String:
	var names: Array[String] = []
	for strike_class in state.ladder.strike_classes_at(level):
		names.append(
			TranslationServer.translate(CLASS_KEY_PREFIX + String(strike_class).to_upper())
		)
	if names.is_empty():
		return TranslationServer.translate("ESC_ROE_NONE")
	return ", ".join(names)


## The toast of an `escalation_changed` event: "Open war – NATO entered enemy sanctuary", calm
## decay as "Calm: level 2 → 1".
static func change_text(state: OperationalState, event: Dictionary) -> String:
	var level: int = event["level"]
	var cause: StringName = event["cause"]
	if cause == &"calm":
		return TranslationServer.translate("Calm: level %d → %d") % [event["previous"], level]
	var by: int = event.get("by", -1)
	var text := level_name(state, level)
	if by < 0 or by >= state.player_sides.size():
		return text
	return (
		"%s – %s"
		% [
			text,
			(
				TranslationServer.translate(CAUSES.get(cause, "%s"))
				% StaffMapTurnBar.side_name(state, by)
			)
		]
	)


## "Operation over" notice lines: [what happened, defeat text, victory text] for `operation_ended`.
## The only end of the ladder is the nuclear attack (reason `nuclear_use`, TASK-140): "Russia used
## a nuclear weapon. The operation ends."
static func end_lines(state: OperationalState, event: Dictionary) -> Array[String]:
	var by: int = event["by"]
	var side := StaffMapTurnBar.side_name(state, by)
	var lines: Array[String] = [
		TranslationServer.translate("%s used a nuclear weapon. The operation ends.") % side,
		TranslationServer.translate("Nobody wins."),
	]
	return lines


## The collapse strip of the ladder window for `player` (TASK-140): {name, strength, readiness,
## text, collapse}, text "Russia ·
## strength 72 % · readiness 80 · collapse at ≤ 50 %" from CollapseRules, `collapse` lights the red
## COLLAPSE tag.
static func collapse_strip(state: OperationalState, player: int) -> Dictionary:
	return {
		"name": StaffMapTurnBar.side_name(state, player),
		"strength": CollapseRules.strength_pct(state, player),
		"readiness": CollapseRules.avg_readiness(state, player),
		"text":
		(
			TranslationServer.translate("%s · strength %d %% · readiness %d · collapse at ≤ %d %%")
			% [
				StaffMapTurnBar.side_name(state, player),
				CollapseRules.strength_pct(state, player),
				CollapseRules.avg_readiness(state, player),
				state.ladder.collapse_strength_pct,
			]
		),
		"collapse": CollapseRules.in_collapse(state, player),
	}
