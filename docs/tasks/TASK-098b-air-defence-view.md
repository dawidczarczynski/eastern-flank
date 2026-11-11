# TASK-098b: Air defence and SEAD v1 (2/2, view) – coverage overlay on the staff map, suppressed state on air-defence markers, interception odds in the strike confirm card and panel

- **Status**: ready
- **Layers**: presentation (staff map); reads state and events only (`StrikeRules.coverage`, `StrikeRules.interception_chance`, `installation_suppressed`, `strike_resolved`), no rules
- **Depends on**: TASK-098a (soft: TASK-141b – the weapon list of the strike panel, TASK-100 – fog of sites)
- **Sections**: GDD "Deep strikes", "Operational map view"; ARCHITECTURE "Operational events"; TASK-098a, TASK-097b task files
- **Model**: sonnet (view only; pure text/model helpers carry the logic and are unit-tested)
- **Topic**: Two-layer game
- **Tags**: mvp

## Decisions (human, 2026-11-11)

Q1 a **coverage overlay** with translucent zones around the air-defence sites of both sides (no fog yet), suppressed sites dashed and greyed, **toggle key**; Q2 the air-defence marker and its hover card show the **suppressed state and the rounds left**; Q3 the **interception odds** ("interception ~X%") for the chosen weapon and target are shown in the existing strike confirm card and / or strike panel; Q4 there is **no mockup**: the first step is `/design-ui` (run by the human) and only the chosen variant is implemented; Q5 the rules and numbers are TASK-098a.

## Goal

The player sees where the air defence reaches, which sites are silenced and for how long, and what interception chance a planned strike faces, so that hitting the air defence first is a visible, plannable move (rules in [TASK-098a](TASK-098a-air-defence-core.md)).

## First step (before any code)

Run **`/design-ui`** (the human does) for: the coverage overlay (zones, overlap, suppressed look, toggle control and key), the suppressed marker state and its hover-card lines, and the "interception ~X%" line in the confirm card / strike panel. Implement **only the variant the human picks**; save the chosen mockup in `docs/design/operational_map/` and name it in the notes. Components to reuse (grep `docs/CODEMAP.md`): `StaffMapInstallationMarker` / `StaffMapInstallations` (marker and its layer), `StaffMapInstallationCard` (hover card, `StaffMapCard` look), `StaffMapStrikeConfirm` (confirm card), `StaffMapStrikePanel` (means list), `StaffMapStrikeText` (pure texts), `StaffMapStrikeReport` (result card), the toast.

## Acceptance criteria (testable)

Pure models and texts (unit-tested without a scene):

- [ ] Odds text from `StrikeRules.interception_chance(state, player, weapon, coord)` and `coverage`: X > 0 → "Interception ~X% per missile" (X exactly the core value); X = 0 and at least one covering site is suppressed → "Air defence suppressed"; X = 0 otherwise → "No air defence cover". Test on the shipped operation: `jassm_er` on a Russian c2 in the Kaliningrad zone shows the core number; on Lida "No air defence cover"; with the Kaliningrad site suppressed and no other cover "Air defence suppressed".
- [ ] The line appears in the confirm card for the chosen weapon and target and updates when the weapon changes; in the strike panel it appears for the hovered target while a weapon is picked (hidden with no target hovered). It does not appear for a target that is not legal (no reason line overlaps it).
- [ ] Zone model: one entry per site from `coverage(state, player)` for both players: centre hex, radius in hexes, owner side, `suppressed`; the screen radius is `radius_hexes` × 5 km on the map scale (a true circle, not hex-shaped); destroyed sites have no zone; a test per case (active, suppressed, destroyed, both sides).
- [ ] Hover card of an air-defence marker adds: type name and examples ("Medium air defence – NASAMS, Buk-M3"), reach "radius 10 hexes (50 km)", and when suppressed "Suppressed – n rounds left" (n = `suppressed_rounds`); a non-suppressed site has no such line. Text model tested for active, suppressed 2, suppressed 1, other classes (no air-defence lines).

Scene:

- [ ] **Coverage overlay** (per the chosen design): translucent zones in the side colour of the owner around every non-destroyed air-defence site of both sides, overlaps readable, suppressed zones dashed and greyed; toggled by the key from the chosen design (default off) and its control; the overlay never blocks clicks or hover on hexes, counters and markers; it follows pan / zoom; it is hidden when the strike mode is closed unless toggled on (the strike mode itself shows it automatically while a weapon is picked – design decides, test pins the chosen behaviour).
- [ ] **Marker state**: an air-defence marker of a suppressed site is greyed / struck through per the design with the rounds left as a small number; it returns to normal on `installation_suppressed` with `after` 0; updates on `installation_suppressed` events without a rebuild of the other markers. Scene test: strike hit on an air-defence site → marker shows "2"; end the round twice → normal.
- [ ] **Result report / toast**: when a strike hits an air-defence site the report card (`StaffMapStrikeText.report_model`) adds the line "Suppressed for n rounds" (n from the event), and interceptor sites in the report come from `interceptor_ids` of `strike_resolved`; model tests: hit on a site → line present, 0 hits or destroyed → absent.
- [ ] Scene-level smoke test: with a hand-made state, S → pick a weapon → hover / click a target inside a zone → the confirm card shows the odds line; the overlay toggle key shows and hides the zones (count of zones = `coverage` of both sides); `--side=russia` works the same.
- [ ] Performance: with the overlay on and 6 zones the staff map still holds 60 FPS (the overlay is drawn from cached geometry, no per-frame allocation of polygons); stated in the notes with the way it was checked.

## Look (Claude Design)

No mockup yet: see "First step". Follow the chosen variant for frame, colours, line styles (dashed = suppressed), fonts and sizes; reuse the counter palette and `StaffMapCard` look. State any deviation and why in the notes; compare a `tools/screenshot.sh` render with the mockup before reporting.

## Playtest (for the human)

1. **Operation** (`--debug`): press the overlay key: three zones per side (a large long-range circle, a medium one, a small short one) around the air-defence markers; press again: gone; pan / zoom: zones follow; you can still click counters under a zone.
2. Hover a Kaliningrad air-defence marker: type, examples, radius; nothing about suppression.
3. S → pick `jassm_er` → hover a Kaliningrad target (at Open war): "Interception ~X% per missile" in the confirm card after clicking; hover Lida: "No air defence cover".
4. Strike the Kaliningrad air-defence site (F9 raise to Open war if needed): its marker turns grey with "2", its zone dashed; the report says "Suppressed for 2 rounds"; strike the airfield next: "Air defence suppressed", the interception percentage was 0 in the result.
5. End turn twice: the site is normal again, zone solid; the odds line shows the percentage again (reduced if the site is damaged).
6. `--side=russia`: the same against Polish sites.

## Player manual

Chapter **Deep strikes**, a part "Air defence on the map": the coverage overlay and its key, what a zone and a dashed (suppressed) zone mean, the suppressed marker with rounds left, the "Interception ~X%" line when planning a strike and what "No air defence cover" / "Air defence suppressed" mean, the "Suppressed for n rounds" line in the report, and the controls (overlay key, button) as in the chosen design.

## Out of scope

Fog of air-defence sites (TASK-100); the full strike forecast (hit chance, expected damage – TASK-101, which will extend the odds line); animation of the interception beyond the existing interception marks of the strike trail (TASK-097b); changes to the rules or numbers (TASK-098a, TASK-103); battle-layer display.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
