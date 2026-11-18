# TASK-177: Russia's own main objective - the Kaliningrad - Belarus corridor

- **Status**: done
- **Layers**: core + data + ai + presentation
- **Depends on**: TASK-175b
- **Topic**: Two-layer game
- **Sections**: GDD "Sides" (Victory: Two chains, Points, Endings, Objective tiers), docs/design/operational_map/objectives_window.html, docs/design/operational_map/README.md (last paragraph), docs/tasks/TASK-175a-objectives-window-main-side.md, docs/tasks/TASK-175b-objectives-map-layer.md
- **Model**: opus

## Goal

Russia has its own main objective, different from NATO's: **connect the Kaliningrad oblast with Belarus** by Russian-held land across the Suwałki Gap (the **Russian corridor**). Held 5 rounds in a row it wins at once. NATO's main objective is the **Gap road**: keep Suwałki connected with Kaunas, scored at the end.

Design (human, 2026-11-18, second decision of the day, replaces the fixed 23-hex corridor and 13-hex Gap chain): objectives are **connectivity conditions, not prescribed routes**. Terms: **Gap road** (NATO) vs **Russian corridor** (Russia); "the Gap" alone = the geographic Suwałki Gap. Note: if this proves too big for one session, split at the Part 2 / Part 3 boundary (core+AI+balance / window+layer+i18n).

## Decisions (GDD "Sides", already written)

- Gap road: **open** while some route of land hexes (neighbours, no road needed, water never) joins `nato_link_from` (Suwałki, axial (17,34)) with `nato_link_to` (Kaunas, (40,13)) through hexes **none of which side 1 holds** (neutral / unheld allowed), else **cut** (`OperationVictory.gap_status` returns `open` / `cut`). NATO scores `gap_open_points` 10 at the end when open; no instant NATO win, no NATO counter.
- Corridor: **closed** while some route of land hexes **all held by side 1** joins any hex of `corridor_from_country` (`russia`, the Kaliningrad oblast) with any hex of `corridor_to_country` (`belarus`), else **open**. Counter `corridor_closed_rounds`, `closed_rounds_to_win` 5, instant win reason `corridor_closed`, `corridor_points` 10 at the end.
- Statuses are re-checked after every command that changed a hex holder; order at the end of a round: annihilation, counter, `corridor_closed`, `round_limit`.
- Renames: ending `gap_closed` -> `corridor_closed`; score line `gap_closed` -> `corridor`, `gap_open` stays; event `objective_changed` kinds: `gap` (old/new `open`/`cut`), `corridor` (old/new `open`/`closed`), `corridor_counter` (old `gap_counter` removed), `objective_id` `gap` / `corridor`.

## Superseded: fixed chains

The first version of this task (same day) used a fixed 13-hex `gap_chain` (Suwałki - Marijampolė road) and a fixed 23-hex `corridor_chain` (Kybartai - Marijampolė - Lazdijai - Kapčiamiestis). Both fields and their validation are removed; the shortest land routes now come from `OperationVictory.land_route` (corridor: 17 steps through the Polish strip of the Gap; Suwałki - Kaunas: 23 steps via Kalvarija and Marijampolė).

## Acceptance criteria (testable)

Part 1 - data and rules (core)
- [x] `OperationDefinition`: `gap_chain` / `corridor_chain` removed; new `nato_link_from` / `nato_link_to: Vector2i` (default `Vector2i.MAX` = none) and `corridor_from_country` / `corridor_to_country: StringName` (&"" = none); `corridor_points` 10; `suwalki_gap.tres`: (17,34), (40,13), `russia`, `belarus`.
- [x] `Operation` validation: link ends both set or both unset, distinct land hexes of the map; corridor countries both set or both unset, distinct, countries of the operation. One test per broken case; a test loads the shipped data (ends = the Suwałki and Kaunas places, land; both land routes exist).
- [x] `OperationVictory` (pure, A* over land neighbours, deterministic, no rng): corridor closed by a winding non-straight route; one gap in it -> open; any other Russian-held route closes it again; the link cut only when every route is blocked, open while a detour exists, neutral hexes allowed, an end held by Russia cuts it; water is never walkable; missing objective -> open. `gap_route` / `corridor_route` / `land_route` / `country_hexes` / `border_hexes` exposed.
- [x] `side_score`: NATO line `gap_open` 10 only while the link is open, Russia line `corridor` 10 only while closed; no `gap_closed` line.
- [x] `end_round`: corridor closed at the end of 5 rounds in a row -> `operation_ended` winner 1, reason `corridor_closed`, `by` 1; broken -> counter 0 (`corridor_counter` event); closed at round 30 with a short counter -> scored only (`round_limit`); a cut link never moves the counter; annihilation first, `corridor_closed` before `round_limit`.
- [x] Events: a command that flips the link emits `objective_changed` kind `gap` once, one that flips the corridor kind `corridor` once; one hex can flip both (closing the corridor cuts the link); no status event without a holder change; `HexControl.is_objective_hex` is true for every land hex while a connection objective exists (no `holder` event for a route hex).
- [x] `OperationalState.corridor_closed_rounds` saved / restored; record replay of a closed-corridor operation gives the same result; `operation_match_runner` ending `corridor_closed`.

Part 2 - AI and balance
- [x] AI goals in `suwalki_gap.tres` (data only, ids and weights unchanged): Russia `ru_take_corridor_choke` (24,29) 7, `ru_take_corridor_mid` (24,33) 5, `ru_take_corridor_end` (24,37) 4 (on a shortest Kaliningrad - Belarus route; (24,29) is on the shortest Suwałki - Kaunas route too); NATO `nato_hold_corridor_choke` (24,29) 7, `nato_hold_corridor_mid` (29,22) Marijampolė 5. A test checks each lies on a shortest route of its objective.
- [ ] `tools/simulate.sh` operation mode, 20 matches per seed set (seeds 1.. and 101..): win shares reported in Implementation notes; NOT pass/fail, no retuning.

Part 3 - window, map layer, texts (presentation)

Note (connection model, 2026-11-18): the "n of 13 / 23" chain bars, `chain` framing and chain ribbons below assume the superseded fixed chains; the presentation rework replaces them (until then the main rows use `OperationVictory.land_route` as a stand-in chain).
- [ ] `StaffMapObjectivesModel.rows`: exactly 2 `main` rows (viewer's own main objective first, the enemy's second, flagged `enemy`) and 4 `side` rows. NATO viewer: own = Gap road, title "Keep the Gap road open", chain bar "n of 13 held by Russia" (n = Russian hexes of `gap_chain`), status chip OPEN / CUT, no counter, rule "Scored at the end: +10 while open". Russian viewer: own = corridor, title "Connect Kaliningrad with Belarus", bar "n of 23 held by Russia", progress "k / 5" with a 5-segment bar (k = `corridor_closed_rounds`, 5 = `closed_rounds_to_win`), rule "Wins at once after 5 rounds in a row; scored 10 at the end otherwise". Numbers 13 / 23 / 5 / 10 come from data. Tested for both viewers with the same state.
- [ ] The enemy main card is muted and tagged ENEMY: NATO sees "Russian corridor - n of 23 held by Russia, k / 5 rounds"; Russia sees "Gap road - n of 13 held by Russia, OPEN / CUT". Each row carries its `chain` (ordered hexes) and `hex`; clicking it frames the whole chain (all 23 / 13 hexes visible), Up/Down/Enter as in TASK-175a (selection order: own main, enemy main, side rows).
- [ ] Journal / toast texts (`staff_map_journal_text.gd`): `gap` -> "The Gap road is cut" / "The Gap road is open again"; `corridor` -> "The corridor is closed" / "The corridor is open again"; `corridor_counter` -> "Corridor held %d/%d rounds" and "Corridor broken - counter reset"; pure functions, wording per viewer (own/enemy), both sides see every change.
- [ ] Map layer (`StaffMapObjectivesLayer`, key M): both chains drawn as ribbons: Gap road as in TASK-175b but with the tag "THE GAP ROAD | n/13 +10" and status colouring by "Russia holds this hex"; corridor ribbon with the tag "CORRIDOR | n/23 +10"; Russia-held hexes solid in Russia's colour, the rest dotted (corridor dotted in a dimmer line than the road so the two are told apart; the shared hex is drawn once). Clicking either tag opens the window on that row.
- [ ] End notice (`StaffMapEndModel`): reason `corridor_closed` reads "Russia held the corridor long enough. The operation ends." (replaces the `gap_closed` text); points table lines `gap_open` "Gap road open" and `corridor` "Corridor closed".
- [ ] All new / changed strings in `assets/i18n/strings.csv` with Polish (see below); old `gap_closed` / `gap_counter` strings removed; no literals in the view.

## i18n strings (en / pl)

| English | Polish |
|---|---|
| Keep the Gap road open | Utrzymaj drogę przez Przesmyk otwartą (exists) |
| Connect Kaliningrad with Belarus | Połącz Obwód Kaliningradzki z Białorusią |
| Gap road | Droga przez Przesmyk |
| Russian corridor | Korytarz rosyjski |
| The Gap road is cut | Droga przez Przesmyk jest przecięta |
| The Gap road is open again | Droga przez Przesmyk znów jest otwarta |
| The corridor is closed | Korytarz jest zamknięty |
| The corridor is open again | Korytarz znów jest otwarty |
| Corridor held %d/%d rounds | Korytarz utrzymany przez %d/%d rund |
| Corridor broken - counter reset | Korytarz przerwany - licznik wyzerowany |
| %d of %d corridor hexes held by Russia | Rosja trzyma %d z %d hexów korytarza |
| THE GAP ROAD | DROGA PRZESMYKU |
| CORRIDOR | KORYTARZ |
| CUT | PRZECIĘTA |
| Russia held the corridor long enough. The operation ends. | Rosja utrzymała korytarz wystarczająco długo. Operacja się kończy. |
| Gap road open | Droga przez Przesmyk otwarta |
| Corridor closed | Korytarz zamknięty |

## Design check

Compare a render with `docs/design/operational_map/objectives_window.html` (variant A) and README; the second (enemy) main card and the second ribbon are minor variations of existing parts (no new design needed). State every deviation in Implementation notes.

## Playtest (for the human)

1. NATO, press O: one main card "Keep Suwałki connected with Kaunas" (SUWAŁKI ↔ KAUNAS, chip CONNECTED, +10), then only Chernyakhovsk and Grodno. No enemy card, no counter.
2. Press M: end rings at Suwałki and Kaunas with one tag between them, no ribbon, no Vilnius / Białystok marker. Click the tag or a ring: the window opens on the main row; clicking the row frames both ends.
3. Russia: "Connect Kaliningrad with Belarus" (NOT CONNECTED, "0 / 5"), side rows Białystok, Vilnius, Grodno; map rings at Kaliningrad and Belarus, tag "KALININGRAD ↔ BELARUS ▪ 0/5". No NATO objective anywhere.
4. Hot-seat: as Russia take Kaunas (or block every route): NATO gets "The Suwałki–Kaunas link is cut", red tag; Russia sees no toast or journal line for it.
5. As Russia hold a route Kaliningrad - Belarus of your choice: "link is established", "held k/5 rounds" each round, win after 5; breaking it resets the counter; NATO sees none of these.
6. Check texts in Polish.

## Player manual

Not changed by the designer yet (the manual describes the game as implemented now). The implementer updates docs/MANUAL.md: section 12b "Objectives" paragraph (main objective differs per side: NATO's Gap road with OPEN / CUT, Russia's corridor of 23 hexes with the "k / 5" counter; enemy main card; two ribbons "THE GAP ROAD n/13 +10" and "CORRIDOR n/23 +10"); section 12c "Points" (Gap road open at the end = 10 for NATO while Russia holds no hex of it; corridor closed = 10 for Russia), "Objective changes" (road cut / open, corridor closed / open) and "Endings" (Russia wins at once when the **corridor** stays closed 5 rounds in a row; replaces "the Gap stays closed").

## Out of scope

- A NATO instant win or counter; a "no enemy on the chain" rule; score forecast; moving the Gap road.
- Changing hex-control rules or other scoring.

## Implementation notes

**Rework 2026-11-18 (connection model, core/data/AI)**: `gap_chain` / `corridor_chain` removed; `nato_link_from` / `nato_link_to`, `corridor_from_country` / `corridor_to_country`; `OperationVictory` A* route searches (`gap_route`, `corridor_route`, `land_route`, `country_hexes`, `border_hexes`); `OperationalSimulation` re-checks statuses only after a command changed a holder (cached per holders). AI goals retargeted (see Part 2). Route search costs ~8 % of a match (70 searches, ~0.45 s of 5.8 s, one match). Balance (report only, not retuned): `tools/simulate.sh 20 --mode=operation`: seeds 1..20 NATO 0 % / Russia 100 % (`corridor_closed` 90 %, round limit 10 %, avg 15.4 rounds); seeds 101..120 NATO 0 % / Russia 100 % (`corridor_closed` 85 %, avg 16.8 rounds). The shortest corridor (17 steps through the Polish strip) is closed by the Russian AI within ~10 rounds. The notes below describe the superseded fixed-chain version.

**Done**
- Core/data/AI: `corridor_chain` (23 hexes through Lithuania, none moved), `corridor_points`, `OperationVictory.gap_status` (open/cut) and `corridor_status` (open/closed), counter `corridor_closed_rounds`, end reason `corridor_closed`, events `gap` / `corridor` / `corridor_counter`, 5 AI goals (choke = shared hex (27,24), not (20,31)). Shipped-data test: all 23 hexes land and contiguous, first hex next to a Russian hex, last next to a Belarus hex, chains share exactly (27,24).
- Presentation: two main rows (own first, muted ENEMY second), two ribbons with tags, toasts/journal/end notice, i18n with Polish. Toast/journal texts are the same for both viewers (one string per event).
- Manual 12b/12c updated; ARCHITECTURE and TOOLS updated.

**Balance (report only, not retuned, corridor not shortened; human balances later)**: `tools/simulate.sh 20 --mode=operation`: seeds 1..20 NATO 40 % / Russia 60 %; seeds 101..120 NATO 30 % / Russia 70 %; all ended by round limit, `corridor_closed` never fired.

**Deviations from the mockup**: main cards have a points column ("+10 PTS" / "+10 ENEMY"); the enemy card has no rule text (window overflowed at 1280x720 in Polish); both cards use "%d of %d held by %s"; tag separator is the mockup's square instead of "|". Rendered screenshots (.screenshots/obj_ru.png, obj_nato.png) before the last tweak (held-hex discs not seen).

**Limits**: the only failing test under load is the timing test `test_loading_and_decoding_the_layers_stays_fast` (passes alone). Battle scene untouched, README screenshot not refreshed.

**Presentation rework (connection model, 2026-11-18)**: each side sees only its own main link and own / neutral side objectives (window, layer, toasts, journal; `concerns`, `shown`); no route drawn: end rings + one tag; Russia's ends are the biggest places of the two countries (Kaliningrad, Grodno). Manual 12b/12c rewritten. Decisions to check: holder toasts of the other side's side objectives are hidden too; Russia's tag is red when its link is connected; counters draw over the end rings at the start. Screenshots rendered in Polish only (locale env has no effect on the staff map).

**Known red test (accepted by the human 2026-11-18)**: `test_operation_balance.gd:test_both_sides_win_a_fair_share_of_operations` fails (NATO 0 / Russia 100 %) until TASK-178. Timing tests `test_loading_and_decoding_the_layers_stays_fast` and `test_a_long_operation_opens_fast` fail only under load and pass alone.
