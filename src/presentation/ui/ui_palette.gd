class_name UiPalette
extends RefCounted
## HUD colours from docs/design/README.md – the single place for UI colours.

const BACKGROUND := Color("#11130f")
const PANEL_BG := Color(17 / 255.0, 19 / 255.0, 15 / 255.0, 0.84)
const PANEL_BG_STRONG := Color(17 / 255.0, 19 / 255.0, 15 / 255.0, 0.94)
const PANEL_BORDER := Color(235 / 255.0, 232 / 255.0, 223 / 255.0, 0.12)
const DIVIDER := Color(235 / 255.0, 232 / 255.0, 223 / 255.0, 0.10)

const TEXT := Color("#ebe8df")
const TEXT_SECONDARY := Color("#a8a598")
const TEXT_MUTED := Color("#d8d5cb")
const TEXT_DIM := Color("#c9c6bb")
const ACCENT := Color("#e2c069")

const HP_HIGH := Color("#b9d38a")
const HP_MID := Color("#e2c069")
const HP_LOW := Color("#e07c5e")
const HP_EMPTY := Color(233 / 255.0, 231 / 255.0, 223 / 255.0, 0.12)

## Indexed by player id.
const FACTION: Array[Color] = [Color("#5b93d6"), Color("#d76a52")]
## Text colour on a faction-coloured badge.
const FACTION_INK: Array[Color] = [Color("#0f1a26"), Color("#2a110b")]

## Placeholder faction names (translation keys) and badge abbreviations, indexed by player id.
const FACTION_NAMES: Array[String] = ["Blue Force", "Red Force"]
const FACTION_SHORT: Array[String] = ["BF", "RF"]


static func hp_color(hp: int, max_hp: int) -> Color:
	if max_hp <= 0:
		return HP_LOW
	var ratio := float(hp) / float(max_hp)
	if ratio > 0.6:
		return HP_HIGH
	if ratio > 0.35:
		return HP_MID
	return HP_LOW
