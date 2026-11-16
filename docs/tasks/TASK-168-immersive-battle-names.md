# TASK-168: More immersive battle names (e.g. 'Contact with the enemy 5 km east of Suwałki')

- **Status**: done
- **Layers**: core, presentation
- **Depends on**: – (TASK-087 / TASK-112 place data already done)
- **Sections**: GDD "Battle hand-off and auto-resolve"
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Every battle of the operation has a two-line name: a situation phrase ("Contact with the enemy") and the nearest named place ("Suwałki, 5 km east"), shown wherever the battle appears. Computed on demand, nothing stored.

## Design (decided by the human 2026-11-16; [ASSUMPTION] = designer's gap-filling)

- **Format**: line 1 = situation phrase, line 2 = `StaffMapPlaceName.describe` text (nominative place, `DIR_*` keys; bare place closer than `NEAR_KM` 1.5 km; `HEX x,y` fallback when the map has no places). No declension. One-line form joins them with " · ".
- **Phrases (7)**: attacker: Assault (open), Assault on the town (urban), Forest assault (forest), River crossing (river); defender: Defence (open), Defence of the town (urban); both: Contact with the enemy (meeting engagement).
- **Selection precedence** (first match wins) **[ASSUMPTION]**:
  1. Meeting engagement: either side's `Mission.task` is `&"hold_out"` (a formation caught on the march) -> Contact with the enemy, for both roles. [ASSUMPTION] Chosen instead of "no objective hex" because a pending `BattleSetup` has `default_objectives()` (no hexes) until `ContactMap.build`, so the objective test would give a different name in the notice and in the briefing; the mission task is set at contact and never changes.
  2. Attacker: terrain `water` or caller flag `crossing` -> River crossing; then `urban` -> Assault on the town; then `forest` -> Forest assault; any other terrain (plains, fields, hills, marsh) -> Assault.
  3. Defender: `urban` -> Defence of the town; any other terrain (incl. forest, water) -> Defence **[ASSUMPTION]** (only two defender phrases were decided).
- **Role**: viewer is attacker when `setup.attacker == viewer`. **[ASSUMPTION]** Scenario battles (`attacker == -1`, no missions) have no operational name: no name is shown, as today.
- **Bridge**: `crossing: bool` is a parameter (default false); the caller sets it true when the battle's objective hex lies on a river/bridge in the cut tactical map, only if that is a cheap grid lookup in `ContactMap`; otherwise left false and noted in Implementation notes.

## Acceptance criteria (testable)

- [ ] New pure class `BattleName` (core, `src/core/operational/`): `situation(setup, viewer, crossing := false) -> StringName` returns one of 7 keys; no `TranslationServer`, no `Node`.
- [ ] Attacker viewer: terrain `plains`/`fields`/`hills`/`marsh` -> `ASSAULT`; `urban` -> `ASSAULT_TOWN`; `forest` -> `ASSAULT_FOREST`; `water` -> `ASSAULT_RIVER`; `plains` with `crossing = true` -> `ASSAULT_RIVER`.
- [ ] Defender viewer: `urban` -> `DEFENCE_TOWN`; `plains`, `forest`, `water` -> `DEFENCE`.
- [ ] A setup where either mission has task `hold_out` -> `CONTACT_ENEMY` for both viewers, even on `urban` terrain (precedence over every other rule).
- [ ] A setup with `attacker == -1` / no missions returns `&""` (no name).
- [ ] Same setup, viewer 0 vs viewer 1 gives different keys on `urban` (`ASSAULT_TOWN` vs `DEFENCE_TOWN`); same inputs twice give identical output (no RNG used).
- [ ] `BattleName.place(map, coord)` returns `{name, km, dir}` (`km` int via the `describe` rounding, `dir` a `DIR_*` key; `km` 0 and `dir` `""` when closer than 1.5 km; `{}` when the map is null or has no places); on a 3-place test map the nearest is chosen, and a hex at 5 km east gives `km` 5, `dir` `DIR_E`.
- [ ] `StaffMapPlaceName.describe` is refactored onto `BattleName.place` (nearest-place maths exists once); its existing tests still pass unchanged.
- [ ] Presentation `BattleNameText`: `two_lines(setup, viewer, map, coord)` returns `[phrase, place]` translated; `one_line(...)` returns `"phrase · place"`; with a null map the place part is `HEX x,y`; a scenario battle returns `[]` / `""`.
- [ ] `strings.csv` has the 7 situation keys with EN and PL (`Assault`/`Szturm`, `Assault on the town`/`Szturm na miasto`, `Forest assault`/`Szturm w lesie`, `River crossing`/`Forsowanie rzeki`, `Defence`/`Obrona`, `Defence of the town`/`Obrona miasta`, `Contact with the enemy`/`Spotkanie z wrogiem`); a test checks every key has non-empty EN and PL.
- [ ] Contact notice title = the two lines upper-cased (replaces `"ATTACK – place"`); `CONTACT_TITLE_ATTACK` / `CONTACT_TITLE_DEFEND` removed from the title if unused elsewhere.
- [ ] Battle briefing shows the two lines under the formation title; the in-battle HUD shows the one-line form as the battle's name reminder.
- [ ] Battle result screen heading = phrase, subtitle = place; journal `battle_pending` and `battle_resolved` lines carry the one-line form (e.g. `CONTACT WITH THE ENEMY · SUWAŁKI, 5 KM EAST`), still short enough for one journal row (<= 60 chars before upper-casing for the Suwałki map).
- [ ] No new field in `BattleSetup`, `OperationalState` or any save format (`to_dict` outputs unchanged; existing serialization tests pass).

## Playtest (for the human)

1. Start the Suwałki operation, end turns until a contact occurs. Contact notice title: two lines, e.g. "CONTACT WITH THE ENEMY" / "SUWAŁKI, 5 KM EAST" (or "ASSAULT ..." when you attack from a planned order).
2. Press Play battle: briefing shows the same two lines under the formation title; the in-battle HUD shows the one-line form.
3. Finish or auto-resolve: result screen heading = phrase, subtitle = place. Open the journal: the contact and the result lines use the same name.
4. Switch the language to Polish and repeat; check "Szturm na miasto" on an urban hex, no clipping or overflow in any panel.
5. Compare the same battle from the other side (hot-seat / second player): attacker and defender phrases differ.

## Player manual

Short note in the Battles chapter of docs/MANUAL.md: every battle is named by what is happening (assault, defence, river crossing, contact with the enemy) and by the nearest town with distance and compass direction; the name appears in the contact notice, briefing, battle HUD, result and journal and reads differently for the attacker and the defender.

## Out of scope

- Polish declension / genitive forms; formation-type phrases; naming strategic-level events other than battles; per-place historical names; storing names in state or saves.

## Implementation notes

- Core: `BattleName` (`situation`, `situations`, `place`); `StaffMapPlaceName.describe` now uses `BattleName.place`. `battle_pending` and `battle_resolved` events carry `situation` (key per player); `battle_resolved` also `at` (defender hex, before consequences) so the journal and result screen name a battle after its setup is gone. Nothing added to setups, state or saves.
- View: `BattleNameText` (namer-based, plus map-based `two_lines` / `one_line`); contact notice title, briefing (`BattleName` label under the formation title), HUD mission line prefix, result screen, journal place line. `CONTACT_TITLE_*` strings removed.
- `crossing` is not set by any caller (no cheap bridge lookup in `ContactMap`); only `water` terrain gives *River crossing*.
- Result screen: heading = phrase; the subtitle is `place · winner · reason · turn` so the winner is not lost.
- Battle scene: the name is computed from the operation's pending battle (`Session.simulation`), as the cut setup has no operational hex.
