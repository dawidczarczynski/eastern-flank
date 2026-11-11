# TASK-141b: Deep strikes with real named weapons (2/2, view): weapon list with glyphs, a weapon-specific trace for every missile

- **Status**: done
- **Layers**: presentation (staff map strike mode) + data (`data/strike/looks/`) + tests
- **Depends on**: TASK-141a, TASK-097b
- **Sections**: GDD "Deep strikes", TASK-097b task file (strike panel, confirm card, trail)
- **Model**: sonnet

## Goal

The strike mode (TASK-097b) lists the **named weapons** of the viewer's side and draws each missile as a trace that looks like that weapon: a drone crawls on a low line, a cruise missile skims, a ballistic missile climbs in a high steep arc and arrives fast. Presentation reads events and the means data only (rule 3).

## Acceptance criteria (testable)

Look data (not in the core resource): new `StrikeWeaponLook` resource in `src/presentation/operational/` with `data/strike/looks/<means_id>.tres` – `glyph` (one of `missile`, `ballistic`, `drone`, `rocket`, `loitering`, an icon / silhouette id from the HUD icon set or drawn shapes), `trail_color`, `speed_hexes_per_s`, `arc_height` (fraction of the flight distance, 0.02 – 0.45), `wobble` (0 – 1, drones), `trail_length`, `warhead` (`blast`, `heavy_blast`, `small`, `cluster`), `burst_scale`. **[ASSUMPTION values]**: Iskander-M / ATACMS / PrSM `ballistic` glyph, arc 0.40, fast (the animation ~0.35 s), a bright short trail, `heavy_blast`; Kinzhal arc 0.25, fastest, white-hot trail; Kalibr / Kh-101 / JASSM-ER / Storm Shadow / Tomahawk `missile` glyph, arc 0.03, ~0.8 s, thin long trail; stealthy JASSM-ER dimmer; Geran-2 / Warmate `drone` / `loitering` glyph, arc 0.02, wobble 0.6, slowest (~1.4 s), dotted trail, `small` burst; Homar-K `rocket` glyph, arc 0.2, short thick trail, `cluster` burst. Trail colours follow the striker's side tint, shaded per weapon (never a new palette – `StaffMapPalette`).

- [ ] Look lookup `StrikeWeaponLook.for_means(id)` returns the look or a safe default for a weapon without a file; test: every shipped means has a look file with values in range, and the default is used for an unknown id.
- [ ] Panel (`StaffMapStrikePanel`): one row per weapon of the viewer's side (`side` of the weapon = viewer; decided 2026-11-10: a weapon at stock 0 is **listed greyed, never hidden**, so Storm Shadow / Tomahawk show greyed with 0 until allies deliver; stock > 0 first): glyph, name, designation, `weapon_class` label, stock, range in **km** (hexes × 5) and "all map" above the cap of TASK-141a (accepted by the human 2026-11-10), max salvo. Hover card: platform text, accuracy, interceptability in words ("hard to intercept" ≤ 50, "normal" 51 – 110, "easy to intercept" > 110), damage. Test on the model: the NATO list holds the NATO weapons only (no `iskander_m`), the Russian list the Russian ones; order = by range descending then id; a weapon with stock 0 is listed with `enabled` false.
- [ ] Salvo stepper and confirm card use the weapon name ("3 × JASSM-ER on Chernyakhovsk airfield"); the toast text ("Iskander-M ×2 …") and the "Out of range of Iskander-M" reason use `display_name`. Test on the pure text helpers.
- [ ] **Trace per missile:** the trail layer draws one trace **per missile of the salvo** (capped at 6 drawn; the count label shows the rest), each with its weapon's `arc_height`, duration (distance / `speed_hexes_per_s`, clamped 0.3 – 2.0 s), `trail_color` and a head in the weapon's `glyph`; the missiles of one salvo are staggered 0.08 s apart; an intercepted missile stops short (at ~70 % of the path, the interception mark of TASK-097b flashes there) and a missed one ends in a small dust puff beside the target; a hit ends with the weapon's `warhead` burst scaled by `burst_scale`. Pure helper tests: the curve point at t for arc 0.02 vs 0.40 (apex height), duration clamping, the stagger offsets, the stop point of an intercepted missile.
- [ ] Traces kept as faint trace until the viewer's next turn, at most 8 traces (TASK-097b) – a salvo counts as one trace; the faint trace keeps the weapon's arc.
- [ ] 60 FPS: the layer draws with the existing single `CanvasItem` (no node per missile; ≤ 6 polylines + heads per trace); a scene smoke test that a 4-missile Kalibr salvo and a 6-missile Geran-2 salvo create the expected number of drawn heads and no extra nodes.
- [ ] A weapon without a look in a hand-made test state does not break the view (the default look).

**Design decision (2026-11-11, playtest: the old panel is unreadable):** the strike panel follows `docs/design/operational_map/strike_panel.html` (**variant A**, spec in the operational_map README "Strike panel"): 420 px docked window, row 46 px (glyph tile, name, designation · class · km, stock), stock 0 greyed with "ALLIES ONLY", a detail card under the list (model viewport 388×140 + RANGE / SALVO / ACCURACY / INTERCEPT chips + platform line), then the salvo stepper. The viewport shows the turntable model from TASK-144 (`WeaponModels.build`) and the class glyph at 96 px while a weapon has no model. This replaces the panel row layout and hover card described above; the other criteria (looks, traces) are unchanged. Also add TASK-144 as a soft dependency.

## Playtest (for the human)

1. NATO (`--debug`, F9 +stock): S – the list shows JASSM-ER, Homar-K, ATACMS, PrSM, Warmate with glyphs, ranges in km, stock; Storm Shadow and Tomahawk are listed greyed with stock 0 until allies deliver them (F9 grant). `--side=russia`: Iskander-M, Kinzhal, Kalibr, Kh-101, Geran-2 only.
2. Fire a salvo of 4 JASSM-ER at a distant airfield: four flat, thin traces in a stagger; fire 2 ATACMS at the same target: two high, quick arcs with a heavier burst; 6 Geran-2: slow wobbling dotted lines. Compare speeds and arc heights – do they read as different weapons at a glance?
3. Strike a defended target: intercepted missiles stop short with the mark; misses puff beside the target.
4. Zoom out: traces stay readable; watch FPS during a 6-drone salvo.
5. Judge the glyphs and trail colours against the side colours; tune the `data/strike/looks/*.tres`.

**Note (decision 2026-11-10, strike report card):** once TASK-141a adds the designation field, show it in the report card header (`docs/design/operational_map/strike-result-report.html`: name Chakra 700 21, designation mono under it, e.g. '9K720 · Ballistic · ×3') by extending `StaffMapStrikeText.report_model`; until then the header shows the name only. The weapon list / panel built here also gets the X close button (top-right, 24 px hit area).

## Player manual

Extend the **Deep strikes** chapter: the weapon list in strike mode (glyph, name, range in km, stock, what the hover card says), how to read a trace (ballistic = high fast arc, cruise = low, drones = slow and wobbling, rocket = short and thick), what a stopped trace (intercepted) and a puff beside the target (miss) mean, and the burst types.

## Out of scope

Sound (TASK-123), 3D missile models, launch effects at the launcher (no launcher is modelled), the battle-scene use of the weapons, a forecast of hit chances (TASK-101).

## Implementation notes

Done 2026-11-11 (presentation; not yet playtested by the human).

- **Look data**: `StrikeWeaponLook` (`src/presentation/operational/strike_weapon_look.gd`) + `data/strike/looks/<means_id>.tres` for all 12 weapons (hand-written, no uid); `for_means(id)` falls back to a default look. Fields as in the task plus `dotted` (drones / loitering draw dotted traces). `trail_color` is a *shade*: the striker's side colour is mixed towards its RGB by its alpha (alpha 0 = plain side colour), so no new palette. Speeds / arcs are [ASSUMPTION]s: ballistic arc 0.40 at ~160 hexes/s, Kinzhal 0.25 at 260, cruise 0.03 at ~80, Geran-2 / Warmate 0.02 at 40 - 45 with wobble 0.6, Homar-K 0.20 at 110; durations clamp 0.3 – 2.0 s, so on a short strike all weapons hit the 0.3 s floor - judge the differences on long shots.
- **Pure helpers**: `StaffMapStrikeFlight` (curve point / apex, wobble, stagger 0.08 s, drawn indices for a big salvo, stop point of an intercepted missile, heading); `StaffMapStrike.means_list` (side filter, stock > 0 first, range descending, id; `enabled`, km, "whole map" above 120 hexes, interceptability words) and `StaffMapStrikeText.salvo_line`.
- **Trail / layer**: every trace carries its `look`, `duration`, `seed`; bursts carry `warhead` and `burst_scale` (`StaffMapStrikeFx`: heavy blast = second shockwave, small = flash without smoke, cluster = bomblets). At most 6 missiles of a strike are drawn, the first trace holds `more` (the layer draws "+n" at the target). `MAX_STRIKES` is now 8. `StaffMapStrikeLayer.heads()` gives the missiles in flight (one glyph head each, `StaffMapWeaponGlyph.draw_glyph`); still one CanvasItem, no node per missile. Faint traces are the same curve at progress 1, so they keep the arc. The old `StaffMapStrikeLayer.arc_points` is gone (replaced by `StaffMapStrikeFlight.points`).
- **Panel (variant A)**: `StaffMapStrikePanel` is now the 420 px window with `StaffMapStrikeRow` rows (46 px), `StaffMapWeaponCard` (388 x 140 stage with `WeaponTurntable` or the 96 px class glyph, four chips, platform line), stepper and strikes line; the tab reads "STRIKE · <SIDE>" in the side colour; the X comes from `StaffMapWindow`. Greyed rows (stock 0) show "ALLIES ONLY" and are not pickable (a click shows "Arrives only from allies"). The detail card follows hover, then the picked weapon, then the first row.
- **Texts**: confirm card `means_line` is now "3 × JASSM-ER" (plus `salvo_line` "3 × JASSM-ER on <target>" in the model); the panel hint starts with the salvo line; toast and "Out of range of <weapon>" already used `display_name` (now covered by tests).
- **Tests**: `test_strike_weapon_look`, `test_staff_map_strike_flight`, `test_staff_map_strike_panel` (list model, texts, panel, card, layer heads smoke test), additions in `test_staff_map_strike_model`.
- **Deviations from the mockup**: chip INTERCEPT shows the short word (HARD / NORMAL / EASY), the long phrase ("hard to intercept") is the platform line's tooltip; the key caps 1 – 7 on the right of a row are not built; the stage floor is a flat ellipse instead of a radial gradient; the panel stays docked on the right (as before), not at x 16; glyphs are my drawn outlines (not the mockup's SVGs). "WHOLE MAP" starts above 120 hexes as the README says, so JASSM-ER (185 hexes) reads "WHOLE MAP" while the mockup table shows 925 km.
- **Not done / open**: the report card header already shows the designation (141a). README / menu screenshots not re-rendered (the battle scene is unchanged). docs/MANUAL.md "Deep strikes" chapter still to be extended by game-designer.

### Playtest round (2026-11-11)

- Range is always km (hexes x 5); the "WHOLE MAP" / "all map" texts and `WHOLE_MAP_HEXES` are gone.
- Polish: platform lines, the strike toast words (intercepted / hit / miss / destroyed / integrity / strength, "on"), the card words and class names are in `assets/i18n/strings.csv`; the card translates `platform`.
- Launch origin (final rule): `StaffMapStrikeTrail.launch_origin(state, player, target, range_hexes)` (pure) = a safe standoff point: the own hex within the weapon's range whose distance to the target is closest to 90 % of `range_hexes` (`STANDOFF_SHARE`; ties lowest x, then y); a long-range weapon with no own hex that far fires from the farthest own hex in range; no own hex in range falls back to the border hex (`origin`). `LAUNCH_DEPTH` is gone. TASK-147 must move this rule (not the border hex) to the core.
- Stock / max salvo / resupply raised (start stock in `data/operations/suwalki_gap.tres`, max salvo in `data/strike/*.tres`): NATO stock JASSM-ER 24, ATACMS 12, PrSM 8, Homar-K 36, Warmate 40 (resupply 4 / 6 / 6 for JASSM-ER / Homar-K / Warmate); Russia Iskander-M 18, Kinzhal 6, Kalibr 20, Kh-101 20 (+3), Geran-2 80 (+8). Max salvo: Iskander-M 3, Kinzhal 2, Kalibr 12, Kh-101 12, Geran-2 24, JASSM-ER 12, Storm Shadow 9, ATACMS 4, PrSM 3, Homar-K 24, Warmate 20, Tomahawk 9. Storm Shadow / Tomahawk stay at 0 until allies deliver.
- Salvo control is an `HSlider` (integer, 1 .. max salvo, amber on card-edge track) with the count beside it; `StaffMapStrikePanel.salvo_set` -> `StaffMapStrikeHud.set_salvo`.
