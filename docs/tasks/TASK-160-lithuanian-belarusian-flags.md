# TASK-160: National flags for Lithuanian and Belarusian units

- **Status**: ready
- **Layers**: core (data) + presentation
- **Depends on**: –
- **Sections**: GDD "Factions and units (decided 2026-10-18)", GDD "Sides", GDD "Countries and stances"
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Lithuanian and Belarusian battalions are fielded as their own factions (`lithuania`, `belarus`) and show their national flag wherever the game already shows a faction flag (battle HUD turn bar, battle result, contact notice, side-select window).

## Decisions (human, 2026-11-16)

1. Source idea: Lithuanian and Belarusian units show their national flag like other nations do (notes after a full operation playthrough).
2. Add NEW factions `lithuania` (short name LT) and `belarus` (BY) in `data/factions/*.tres`: **identity only**. They reuse existing unit definitions and rosters (Lithuania = Polish-style units, Belarus = Russian-style units), so stats and balance do not change. Own rosters, models and stats are out of scope (separate future tasks).
3. Flags are own simple SVG drawings in `assets/flags/` like `poland.svg` / `russia.svg`: Lithuania yellow-green-red horizontal tricolour; Belarus red-green two bands (ornament stripe omitted or simplified). `assets/flags/README.md` is updated. `SideFlag` rasterises SVG at 2x with mipmaps (unchanged).
4. Flags only in places that ALREADY have a flag slot (HUD turn bar via `HudModel.flags_of`, staff-map battle result tabs/title, contact notice, side-select window). The staff-map counter / formation-panel national flag has no mockup: OUT OF SCOPE, becomes a separate idea task (needs `/design-ui` first).

## Assumptions

- **[ASSUMPTION]** The new factions apply to the formations the two countries contribute (`CountrySetup.contribution` in `data/operations/suwalki_gap.tres`: `lt_iron_wolf_1`, `lt_iron_wolf_2`, `nato_bde_lt`, `by_6_mech_1`, `by_6_mech_2`, `by_6_tank`). The implementer first checks how a formation's faction is resolved when a battle is generated (grep CODEMAP: `FactionRegistry`, `FormationPlacement`, `CountrySetup`, `HudModel`; see `src/core/operational/contact_battle.gd`). If `FormationPlacement` has no faction field, add an optional `faction: StringName` (default empty = the player's side lead faction, so existing placements behave as before).
- **[ASSUMPTION]** Faction colours: Lithuania a green-yellow tint clearly distinct from Poland's blue; Belarus a colour clearly distinct from Russia's red (e.g. dark green); the implementer picks the values, `ink_color` for contrast.
- **[ASSUMPTION]** The side flag stays; `HudModel.flags_of` already hides a second flag that repeats the first.
- **[ASSUMPTION]** Battle unit models/camouflage of a new faction fall back to the reused roster's look (check `UnitRenderRules` and model lookup by faction id so nothing breaks).

## Acceptance criteria (testable)

- [ ] `FactionRegistry.get_faction(&"lithuania")` and `(&"belarus")` return non-null with `short_name` "LT" / "BY" and a non-null `flag`.
- [ ] Each new faction's `roster` has the same unit ids (same count) as the faction it reuses (Poland: 3, Russia: as in `russia.tres`).
- [ ] `lithuania.svg` and `belarus.svg` exist in `assets/flags/` and load as `Texture2D` with width:height equal to the other flags' ratio.
- [ ] `lithuania.color` differs from `poland.color`, and `belarus.color` from `russia.color`, by at least 0.15 in some RGB channel.
- [ ] `HudModel.flags_of(lithuania)` returns 2 flags (side flag, then Lithuanian) and `flags_of(belarus)` returns 2 (side flag, then Belarusian); the existing Poland/Russia results are unchanged.
- [ ] A battle generated from a `by_6_tank` contact has Belarusian-faction units (`faction_of(player)` = `belarus`); one from `lt_iron_wolf_1` has `lithuania`; a Polish formation (e.g. `pl_mech_1`) still has `poland`.
- [ ] `FormationPlacement` with an empty faction resolves to the side's lead faction (backward compatible; all other operations/tests unchanged).
- [ ] An unknown faction id on a placement is rejected with a clear error (no crash, no silent fallback).
- [ ] Every new faction `display_name` has an English and a Polish row in `assets/i18n/strings.csv` ("Lithuania"/"Litwa", "Belarus"/"Białoruś" already exist: reuse the keys).
- [ ] Existing tests that enumerate factions (grep `tests/unit/` for `data/factions` / faction lists) pass or are updated to 4 factions.
- [ ] No unit stat or balance value changes (`data/units/*.tres` untouched); `tools/simulate.sh` results for the Suwałki scenario with no contributions are unchanged.

## Playtest (for the human)

1. Start the Suwałki operation, advance until Lithuania and Belarus join (or use a scenario with their formations).
2. Fight a battle with a Lithuanian battalion: the HUD turn bar shows the side flag and the Lithuanian tricolour next to that player; colours differ from Poland's.
3. Fight a battle with a Belarusian battalion: red-green flag next to the player, distinct from Russia's.
4. Check the battle result tabs/title, the contact notice and the side-select window for the same flags; Polish and Russian battles look as before.

## Player manual

MANUAL.md mentions flags only in passing (objective flags, camouflage lines). Add: Lithuanian and Belarusian formations fight under their own flag and colour (identity only, same units as Poland / Russia respectively); update the camouflage line if units there are described per army.

## Out of scope

- Staff-map counter and formation-panel national flag (no mockup; follow-up idea task, `/design-ui` first).
- Own rosters, unit models, camouflage or stats for Lithuania and Belarus.
- Changes to country stances, sides or any operational rule.

## Implementation notes

_Filled in by the agent when done._
