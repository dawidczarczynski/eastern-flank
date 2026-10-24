class_name UiPalette
extends RefCounted
## HUD colours from docs/design/README.md – the single place for UI colours.

# --- HUD v3 "tactical C2" tokens (docs/design/hud_v3/README.md "Design Tokens") ---
# The older constants below stay until TASK-077 ... TASK-080 have moved the widgets over.
const BG_APP := Color("#0a0c09")
const PANEL := Color(8 / 255.0, 11 / 255.0, 8 / 255.0, 0.86)
const PANEL_STRONG := Color(8 / 255.0, 11 / 255.0, 8 / 255.0, 0.93)
const LINE := Color(232 / 255.0, 176 / 255.0, 74 / 255.0, 0.34)
const AMBER := Color("#e8b04a")
const HUD_TEXT := Color("#dfe5d6")
const HUD_MUTED := Color("#8d9585")
const HUD_DESC := Color("#b7bfae")
## Text / fills on coloured (faction, amber) surfaces.
const INK := Color("#0a0c09")
const DISABLED := Color("#e07c5e")
const NOTE_BG := Color(232 / 255.0, 176 / 255.0, 74 / 255.0, 0.10)
const NOTE_TEXT := Color("#f0c66e")
## Unfilled bar track / empty HP segment (muted at 15 % alpha) and stat bar tick gaps.
const TRACK := Color(141 / 255.0, 149 / 255.0, 133 / 255.0, 0.15)
const TICK_GAP := Color(8 / 255.0, 11 / 255.0, 8 / 255.0, 0.95)
## Outline of a spent unit in the ready counter.
const READY_EMPTY := Color(141 / 255.0, 149 / 255.0, 133 / 255.0, 0.45)
## Dark hatch on faction-coloured fills (end-turn button).
const INK_HATCH := Color(10 / 255.0, 12 / 255.0, 9 / 255.0, 0.55)
## Key hint panel.
const PANEL_HINT := Color(8 / 255.0, 11 / 255.0, 8 / 255.0, 0.82)
## Screen decoration (ScreenDecor): vignette edge, scanline darkening, bracket stroke.
const VIGNETTE_EDGE := Color(0, 0, 0, 0.42)
const SCANLINE := Color(0, 0, 0, 0.05)
const SCREEN_BRACKET := LINE

## Notices (TASK-080): banner band, targeting bar border, loading hatch track.
const BANNER_BAND := Color(8 / 255.0, 11 / 255.0, 8 / 255.0, 0.88)
const AMBER_BORDER := Color(232 / 255.0, 176 / 255.0, 74 / 255.0, 0.6)

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

## Faction colours/names come from FactionDefinition (data/factions/, TASK-038). These are
## the neutral stand-ins for a player without a known faction.
const NEUTRAL_FACTION := Color("#a8a598")
const NEUTRAL_INK := Color("#11130f")


static func hp_color(hp: int, max_hp: int) -> Color:
	if max_hp <= 0:
		return HP_LOW
	var ratio := float(hp) / float(max_hp)
	if ratio > 0.6:
		return HP_HIGH
	if ratio > 0.35:
		return HP_MID
	return HP_LOW


## UI colour of `faction`; neutral when null.
static func color_of(faction: FactionDefinition) -> Color:
	return faction.color if faction != null else NEUTRAL_FACTION


## UI colour of `player_id`'s faction in `state`; neutral for an unknown player or faction.
static func faction_color(state: GameState, player_id: int) -> Color:
	return color_of(state.faction_of(player_id))


## Text colour on a badge filled with faction_color().
static func faction_ink(state: GameState, player_id: int) -> Color:
	var faction := state.faction_of(player_id)
	return faction.ink_color if faction != null else NEUTRAL_INK


## Untranslated faction name (a translation key) of `player_id`; "Player N" when unknown.
static func faction_name(state: GameState, player_id: int) -> String:
	var faction := state.faction_of(player_id)
	return faction.display_name if faction != null else "Player %d" % (player_id + 1)


## Badge abbreviation of `player_id`'s faction; "P<N>" when unknown.
static func faction_short(state: GameState, player_id: int) -> String:
	var faction := state.faction_of(player_id)
	return faction.short_name if faction != null else "P%d" % (player_id + 1)
