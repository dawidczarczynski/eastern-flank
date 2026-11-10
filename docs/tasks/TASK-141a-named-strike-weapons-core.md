# TASK-141a: Deep strikes with real named weapons (1/2, core + data): Iskander-M, Kalibr, Kh-101, Geran-2, JASSM-ER, ATACMS / PrSM, Homar-K … replace the generic means

- **Status**: ready
- **Layers**: core (`src/core/data/`, `src/core/operational/`) + data (`data/strike/`, `data/operations/suwalki_gap.tres`) + tests
- **Depends on**: TASK-097a (done)
- **Sections**: GDD "Deep strikes" (table of weapons), "Outside support" (means grants); TASK-097a, TASK-122 task files
- **Model**: opus (changes the core data model, ids in snapshot / codec / replays / fixtures)

## Goal

Playtest feedback 2026-11-10: the strike means must be **concrete real weapons of the Suwałki 2020s setting**, not "cruise / ballistic / drone". `StrikeMeansDefinition` stays the one data class (a weapon *is* a means); the three generic ids are replaced by named weapons with a **per-side availability**. The rules (`StrikeRules`, `StrikeCommand`, stock, resupply, TASK-122 grants) do not change in shape. The view is TASK-141b.

## Acceptance criteria (testable)

Data model (`StrikeMeansDefinition`, new fields; defaults keep a test-made means valid):

- [ ] `weapon_class: StringName` one of `cruise`, `ballistic`, `aeroballistic`, `rocket`, `drone`, `loitering` (`problem()` rejects anything else; the class is a label for the view and the manual only – **no rule reads it**).
- [ ] `side: int` – `-1` usable by either side, `0` NATO only, `1` Russia only (a data flag, no rule names a side). `platform: String` short text, e.g. "ship / coastal launcher", "fighter-launched", "truck launcher" (view only). `designation: String` the NATO / manufacturer code, e.g. "9M723" (view only).
- [ ] `SHIPPED` lists the new ids; `shipped()` / `find()` unchanged. A test loads every shipped file and asserts `problem() == ""`, unique ids, and that every shipped weapon has `side` 0 or 1 (no shared weapon in v1; `-1` stays valid for test data).
- [ ] **Availability is enforced where stock enters:** `Operation.from_definition` rejects (`push_error`, null – one test each) a starting stock or resupply entry for a weapon whose `side` is the other side; `StrikeRules.add_stock` rejects it (no change, returns `[]`, `push_warning`) – so TASK-122 grants cannot give NATO a Russian missile. `StrikeCommand` needs no new reason (no stock = `out_of_stock`).
- [ ] Old ids are **removed**: `cruise.tres`, `ballistic.tres`, `strike_drone.tres` deleted; `find(&"cruise")` returns null.

Shipped weapons **[ASSUMPTION – real data rounded; 1 hex = 5 km; accuracy, interceptability, damage, stock, resupply are balance guesses for TASK-103]**. Interceptability = % of the air-defence interception chance that bites (100 = a subsonic missile; lower = fast / stealthy / ballistic). Damage = integrity lost by an installation; "form." = strength points per hit.

| id | Name (designation) | Side | Class | Real range → hexes | Acc. | Int. | Dmg | Form. | Max salvo | Start stock | Resupply / round |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `iskander_m` | Iskander-M (9M723) | 1 | ballistic | 500 km → 100 | 80 | 40 | 45 | 3 | 2 | 6 | 0 |
| `kinzhal` | Kh-47M2 Kinzhal | 1 | aeroballistic | 2 000 km → 400 (cap, see notes) | 75 | 25 | 45 | 3 | 1 | 2 | 0 |
| `kalibr` | 3M14 Kalibr (land attack) | 1 | cruise | 1 500 km → 300 | 80 | 100 | 35 | 2 | 4 | 4 | 0 |
| `kh101` | Kh-101 | 1 | cruise | 2 500 km → 500 (cap) | 85 | 80 | 40 | 2 | 4 | 4 | 1 |
| `geran_2` | Geran-2 (Shahed-136) | 1 | drone | 1 800 km → 360 (cap) | 55 | 150 | 12 | 1 | 8 | 16 | 2 |
| `jassm_er` | AGM-158B JASSM-ER | 0 | cruise | 925 km → 185 | 90 | 70 | 40 | 2 | 4 | 6 | 1 |
| `storm_shadow` | Storm Shadow / SCALP-EG | 0 | cruise | 560 km → 110 | 85 | 85 | 40 | 2 | 3 | 0 (allies only) | 0 |
| `atacms` | MGM-140 ATACMS (M39 / M57) | 0 | ballistic | 300 km → 60 | 80 | 45 | 35 | 3 | 2 | 4 | 0 |
| `prsm` | PrSM (Increment 1) | 0 | ballistic | 500 km → 100 | 85 | 40 | 40 | 3 | 2 | 2 | 0 |
| `homar_k` | Homar-K (CGR-080, K239 / K263 rockets) | 0 | rocket | 290 km → 58 | 70 | 90 | 20 | 2 | 6 | 6 | 1 |
| `warmate` | WB Warmate loitering munition | 0 | loitering | 50 km → 10 | 60 | 130 | 8 | 1 | 6 | 6 | 1 |
| `tomahawk` | BGM-109 Tomahawk (Block V, land attack) | 0 | cruise | 1 600 km → 320 (cap) | 85 | 90 | 40 | 2 | 3 | 0 (allies only) | 0 |

Plausibility notes (put in the .tres comments and the notes): Iskander-M, Kalibr (Baltic Fleet corvettes), Kh-101, Kinzhal and Geran-2 are all in Russian service and used in Ukraine; Kaliningrad hosts Iskander-M. JASSM-ER is in Polish service (F-16 Block 52+), Homar-K (Chunmoo) and HIMARS (ATACMS, PrSM) are bought by Poland; Storm Shadow is British / French, so it only arrives as **allied** stock; Warmate is in Polish service but short-ranged. **Ranges beyond the map are capped**: any value above 120 hexes means "anywhere on the operation map" (the cap only matters for display – the rule is unchanged); `range_hexes` keeps the real value / 5 to stay data-true. The "anywhere on the map" display cap is accepted (human, 2026-11-10). Tomahawk (US Navy, ship- and submarine-launched; `platform` "ship / submarine-launched (US Navy)") is not in the Polish arsenal, so like Storm Shadow it is **allied-only** (start stock 0, arrives by TASK-122 grants); its numbers are **[ASSUMPTION]**, subsonic like Storm Shadow. **`platform` is flavour only**: launcher constraints (ships, aircraft, trucks) come with TASK-098 / TASK-132; until then every weapon is fired "from own soil" (TASK-097a).

Stock, resupply, grants:

- [ ] `data/operations/suwalki_gap.tres`: `strike_stock` and `strike_resupply` use the table's ids per side (NATO: jassm_er 6, atacms 4, prsm 2, homar_k 6, warmate 6, storm_shadow 0, tomahawk 0; Russia: iskander_m 6, kinzhal 2, kalibr 4, kh101 4, geran_2 16; resupply as in the last column). Test reads them and asserts the side rule.
- [ ] **No legacy aliases, no migration (human, 2026-11-10; the game is pre-release):** the old ids `cruise`, `ballistic`, `strike_drone` are replaced everywhere – `data/`, the operation, tests, `Fixtures`, snapshot / codec fixtures and recorded replays. Every committed replay or snapshot fixture that carries an old id is **regenerated** with the new ids (list them in the implementation notes; the expected strike outcomes in those tests are re-pinned, since stock and ids change while the draws do not: 2 `rng` draws per missile). There is no `LEGACY_IDS` and no `legacy_to_new`; a saved file with an old id simply fails to load / is rejected like any unknown means (test: an unknown means id in a snapshot is rejected with a clear error). A grep for `strike_drone` and a bare `&"cruise"` / `&"ballistic"` used as a means id outside code-built fixtures must come back empty.
- [ ] **TASK-122 contract:** `MeansGrant.means` takes the new ids; `Operation.from_definition` also rejects a grant of a weapon with the wrong `side` for the package's side (one test). Shipped packages in `suwalki_gap.tres`: `china_components` → +4 `kh101` (Chinese components keep Kh-101 production going **[ASSUMPTION]**), `iran_drones` → +8 `geran_2` (Shahed-136 Iranian origin), `allied_strike_means` → +4 `storm_shadow` and +2 `tomahawk`. TASK-122's file carries a note to use these ids (its tests too).
- [ ] Existing tests are rewritten, not deleted: `test_strike_rules.gd`, `test_strike_command.gd`, `test_strikes.gd` (core ones) use fixture weapons with the same numbers as the old generic ones through `Fixtures` (a generic fixture means may keep ids `cruise` etc. **only if built in code**, never from `data/strike/`), plus new tests: the shipped table (each row's numbers equal the .tres), the side rule for stock, resupply and grants, `add_stock` rejection, and mirror tests (the same weapon-neutral strike for player 0 and 1 gives the same result).
- [ ] No `rng` change: a strike with a named weapon draws exactly 2 numbers per missile, as before (test pins `rng_state` advance).
- [ ] docs/ARCHITECTURE.md: new fields on `StrikeMeansDefinition`, the side rule (no legacy-id table). docs/GDD.md "Deep strikes" already carries the weapon table (updated with this task).

## Playtest (for the human)

Nothing visible changes in the view yet (TASK-141b); the strike mode lists the new ids as plain names. Check with `--debug` (F9 +stock): a NATO player cannot be given `iskander_m` (but can be given `tomahawk`); start a new operation and strike once with `jassm_er`: the stock drops by the salvo.

## Player manual

Extend the **Deep strikes** chapter in docs/MANUAL.md after the weapons are in the game (the table of named weapons per side with range in km and hexes, max salvo, accuracy / interception in words, what "start stock" and "arrives only from allies" mean, plus a sentence that stock is per side and a weapon belongs to one side). Replace every "cruise missile / ballistic missile / strike drone" example in the manual by a named weapon.

## Out of scope

The view (TASK-141b); launchers, platforms, ships and aircraft as units; a technology tree of weapons (TASK-104); production beyond the fixed resupply; launcher constraints (TASK-098 / TASK-132), Patriot / air-defence weapons as named assets (TASK-098); balance by simulation (TASK-103); AI choice of weapon (TASK-102 – the AI picks by data: best expected damage per missile with stock).

## Implementation notes

_Filled in by the agent when done._
