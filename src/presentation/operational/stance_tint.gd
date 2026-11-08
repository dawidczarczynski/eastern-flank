class_name StanceTint
extends RefCounted
## How the staff map tints the countries for one viewer (TASK-114): the single view function
## `for_viewer` maps every country of an operation to its relation seen from `player` (own /
## enemy / hostile / neutral, CountryRules.relation) and whether it is closed to that player
## (CountryRules.may_enter). No side or country literal lives here – swapping the viewer swaps
## own and hostile. Colours come from the staff map palette; the shader draws tint and hatch.

## Tint opacity (reference "Palette": own 5 %, enemy 5.5 %), scaled by a country's commitment.
const ALPHA_OWN := 0.05
const ALPHA_ENEMY := 0.055
const ALPHA_NEUTRAL := 0.05
## A merely aligned country is tinted at this share of a belligerent one's opacity; hostile (an
## aligned country on the other side) is the enemy colour at this lighter opacity.
const ALIGNED_SHARE := 0.6
const HOSTILE_SHARE := 0.6


## Country id -> {"relation": StringName, "closed": bool, "stance": StringName} for every country
## of `state`, seen from `player`.
static func for_viewer(state: OperationalState, player: int) -> Dictionary:
	var out := {}
	for country in state.countries:
		out[country.id] = {
			"relation": CountryRules.relation(state, player, country.id),
			"closed": is_closed(state, player, country.id),
			"stance": country.stance,
		}
	return out


## True when `player` may not enter the country (a country without a hex is open).
static func is_closed(state: OperationalState, player: int, country_id: StringName) -> bool:
	for coord: Vector2i in state.country_map:
		if state.country_map[coord] == country_id:
			return not CountryRules.may_enter(state, player, coord)
	return false


## The tint (RGB of the palette entry, A the opacity) of one `for_viewer` entry; transparent for
## an unknown relation.
static func colour(palette: StaffMapPalette, entry: Dictionary) -> Color:
	var commitment := 1.0 if entry["stance"] == CountryState.BELLIGERENT else ALIGNED_SHARE
	match entry["relation"]:
		&"own":
			return Color(palette.side_own, ALPHA_OWN * commitment)
		&"enemy":
			return Color(palette.side_enemy, ALPHA_ENEMY * commitment)
		&"hostile":
			return Color(palette.side_enemy, ALPHA_ENEMY * HOSTILE_SHARE)
		&"neutral":
			return Color(palette.side_neutral, ALPHA_NEUTRAL)
	return Color(0, 0, 0, 0)


## Solid stance colour for text (names, card): the palette entry without the tint opacity.
static func ink(palette: StaffMapPalette, relation: StringName) -> Color:
	match relation:
		&"own":
			return palette.side_own
		&"enemy", &"hostile":
			return palette.side_enemy
	return palette.side_neutral
