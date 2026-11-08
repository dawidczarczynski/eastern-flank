# TASK-118: Allied contributions – a country that goes to war on its leaning side brings its formations (data per operation)

- **Status**: done
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data + presentation (allied counters, arrival notice)
- **Depends on**: TASK-114, TASK-092b
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Bringing an ally into the war is worth something: when Lithuania or Belarus becomes a belligerent on the side it leans to, its brigades appear on the map for that side (GDD "Operational layer" → "Countries and stances" → allies join with forces, "Strategic options"). This is the gain that the escalation cost of invoking an ally – or of letting the war widen – is weighed against.

## Acceptance criteria (testable)

Data:

- [ ] `CountrySetup.contribution: Array[FormationPlacement]` (the TASK-092b placement: `id`, `display_name`, `parent`, `player`, `definition`, `coord`). `Operation.from_definition` rejects (`push_error`, null – one test each): a contribution whose `player` ≠ the country's `leaning`; a country with a contribution but `leaning` −1; a contribution `coord` outside that country or impassable; an id that repeats any formation id of the operation (placed or contributed); a type whose faction is not the player's faction.
- [ ] `suwalki_gap.tres` **[ASSUMPTION – balance guess]**: lithuania (leaning 0) – `lt_iron_wolf_1`, `lt_iron_wolf_2` (`pl_mech_battalion`, parent "Iron Wolf Mechanised Infantry Brigade"), `nato_bde_lt` (`pl_tank_battalion`, parent "NATO Brigade Lithuania") around Kaunas / Rukla / Vilnius (strength 120); belarus (leaning 1) – `by_6_mech_1`, `by_6_mech_2` (`ru_motor_rifle_battalion`), `by_6_tank` (`ru_tank_battalion`), parent "6th Mechanised Brigade", around Grodno / Lida (110). Display names say "Lithuanian" / "Belarusian"; the types are the side's until those countries are factions (GDD open question). Coordinates picked by the agent on the real map, listed in the implementation notes; test: sums 120 / 110, every hex in its country.

Joining (hooked into `CountryRules.set_stance` – the one change point of TASK-114, so every cause triggers it: decisions, the ladder, events):

- [ ] When a country becomes **belligerent on its leaning side** and has not contributed yet: for each placement in order, a new `Formation` (built like `Operation` builds formations: full strength, refs `<id>/<n>`, the operation's `initial_posture`, no order) is placed on its `coord` when that hex is free (no formation) and passable; otherwise on the nearest free passable hex **of the same country** within 3 hexes (by hex distance, ties by ring order starting in `Hex.DIRECTIONS[0]` – deterministic); otherwise it is lost. Placed formations are appended to `state.formations` (they execute orders after the existing ones). The placement is one shared pure helper, `Reinforcements.place(state, placements, player, source: StringName, require_open := false) -> Dictionary` (`{events, unplaced: Array[FormationPlacement]}`; `require_open` also skips hexes with `CountryRules.may_enter == false`) – TASK-121 reuses it for off-map support, which keeps unplaced formations waiting instead of losing them. Events after `country_stance_changed`, one per placement: `formation_joined` (`formation_id`, `player`, `country` – the country of the placed hex, `coord`, `source` – `&"contribution"` here, the package id in TASK-121) or `formation_join_failed` (`formation_id`, `country`, `reason` `&"no_free_hex"`). The country is marked `contributed` (in `CountryState` and the snapshot) – it never contributes twice.
- [ ] Becoming belligerent on the **other** side (e.g. a neutral Belarus declared on by Russia joins Poland) brings no formations (test).
- [ ] Examples on a hand-made grid (6 × 2 plains, q 0–2 `poland`, q 3–5 `lithuania` aligned 0, leaning 0, contribution A on (4, 0), B on (5, 0)): `set_stance(lithuania, belligerent, 0, …)` → A on (4, 0), B on (5, 0), owned by player 0, strengths full, events in order. With an enemy formation on (4, 0) → A goes to the nearest free lithuania hex by the tie rule (the test names the expected hex), B to (5, 0). All lithuania hexes occupied → both `formation_join_failed`. A second `set_stance` path cannot repeat it (belligerent is final; `contributed` true). Mirrored for side 1 (both sides playable – GDD "Sides"): the same grid with q 3–5 `belarus` aligned 1, leaning 1, the contribution's `player` 1 → the same placements owned by player 1. `Reinforcements.place(..., require_open = true)` with (4, 0) in a country closed to the player → A is in `unplaced`, no event for it.
- [ ] Contributed formations are full formations: they can get orders (`IssueOrderCommand`) in their player's next turn, show in `snapshot()`, and the state is deterministic (two runs of the same scripted `set_stance` sequence give identical snapshots and events). If TASK-117 is already done, the operational replay test of TASK-117 gets one `InvokeAllianceCommand` that brings formations in.
- [ ] No `rng` draws.
- [ ] docs/ARCHITECTURE.md: contributions in "Two layers"; "Operational events": `formation_joined`, `formation_join_failed`.

View (allies appear on the map):

- [ ] On `formation_joined` the staff map shows a **notice** ("Lithuania joins NATO – 3 formations", with a *Show* button that centres the map on them) and the new counters appear with a short pulse; they are ordinary counters with a small country tag, selectable like any other (panel shows the formation's country of origin). They obey orders (TASK-092d) from the turn after they appear.
- [ ] A scene smoke test: setting Lithuania to belligerent on NATO's side through the state adds three counters to the scene, none appear for a country that stays neutral.

## Playtest (for the human)

1. **Operation** as NATO (`--debug`): note the count of blue counters (8 Polish).
2. F9 → set Lithuania belligerent on NATO's side (or play *Invoke Article 5* once TASK-117 exists): the notice "Lithuania joins NATO – 3 formations" appears; *Show* centres on them; 3 blue counters stand on Lithuanian soil near the Gap.
3. Click one: panel shows its companies and "Lithuania". Order it somewhere: the route preview works as for Polish battalions.
4. Do the same for Belarus on Russia's side (red counters near Grodno).
5. Review the allies' order of battle in GDD "Formations" (Lithuania 120, Belarus 110 against Poland 276 / Russia 332).

## Player manual

Section in the "Politics" chapter (started by TASK-113) – which allies can join, with how many formations, and when (invoked alliance, a declaration against them, the Regional war level).

## Out of scope

- Lithuanian and Belarusian factions, rosters and camouflage (later, if wanted); off-map support – NATO allies' reinforcements, North Korean troops, Chinese / Iranian weapons (TASK-121 / TASK-122); mobilisation and replacements (TASK-105).

## Implementation notes

**Logic**: `CountrySetup.contribution`, `CountryState.contributed`, `OperationalState.initial_posture`, shared helper `Reinforcements.place`, hooked into `CountryRules.set_stance`; events `formation_joined` / `formation_join_failed` (in ARCHITECTURE.md). `Reinforcements.place` serves the wanted hexes of the whole batch first and only then resolves fallbacks (otherwise A would take B's hex); in the spec example A lands on (3,0).

**Data** (`suwalki_gap.tres`, axial coords, [ASSUMPTION] balance guess): Lithuania (leaning 0, 120): `lt_iron_wolf_1` (40,13) Kaunas, `lt_iron_wolf_2` (46,8) Rukla, `nato_bde_lt` (56,17) Vilnius. Belarus (leaning 1, 110): `by_6_mech_1` (26,45) next to Grodno (24,45 is occupied), `by_6_mech_2` (47,38) Lida, `by_6_tank` (37,41) east of Grodno.

**View**: `StaffMapJoinNotice` (notice + *Show*), `StaffMapCounters.sync_new()`, country tag + pulse on counters, "Country" row in the formation panel; `join:<country>:<side>` token in `tools/screenshot.gd`.

**Limitations**: the origin country is the country of the hex at join time (wrong for TASK-121 off-map arrivals – `formation_joined` should then carry the origin); `formation_join_failed` has no player-visible feedback; the notice is placed when shown and not re-placed on window resize; the TASK-117 replay test is not done (TASK-117 not done); no player-facing trigger yet except the F9 debug panel.
