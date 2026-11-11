# TASK-131b: Weapon range in the battle UI – range overlay, LoS marks, forecast distance, manual

- **Status**: to playtest
- **Layers**: presentation
- **Depends on**: TASK-131a
- **Sections**: GDD "Combat" (as updated by TASK-131a), TASK-089b (forecast HUD); docs/design mockups (battle HUD, unit popup); `docs/CODEMAP.md` entries for range highlight in `map_view.gd`, `battle_controller.gd`, `unit_popup_model.gd`, `ui/unit_catalog.gd`
- **Model**: sonnet

## Goal

The player sees what a unit can hit: selecting it outlines the hexes in effective and maximum range and marks the hexes blocked from view; the hover forecast shows distance and the falloff; popup and catalog list ranges in metres.

## Decisions (2026-11-10)

1. Scale, LoS, distance effect, counterattack and artillery rules are those of TASK-131a (hex = 250 m; effective range full effect, 50 % at maximum; direct fire needs LoS; artillery minimum range 750 m = 3 hexes).
2. Overlay on **selecting** a unit (existing selection highlight code; today only rocket artillery shows its range, generalise it): hexes within effective range in the amber outline, hexes between effective and maximum in a lighter/dashed amber, hexes inside minimum range not marked.
3. LoS-blocked hexes (direct fire units only) are marked with a dimmed hatch/darker tint inside the range area; hexes in range and visible are the attackable ones.
4. Artillery whose range covers the whole map: overlay covers every map hex outside minimum range (clamped to the map; no infinite outline), the popup still shows the real range in metres.
5. Hover forecast (TASK-089b tag) adds `DIST 6 hex (1.5 km)` and the falloff factor (`-25 %`) when beyond effective range; reuse the tag component, no new look. An enemy hex in range but without LoS shows the normal cursor and, on RMB, the reason `NO LINE OF SIGHT`; `TOO CLOSE` for the minimum range.
6. Ranges are shown in metres or km, not hexes only: popup stat `Range 2 km (8 hex)`; catalog panel the same, with effective / maximum.
7. Follow `docs/design/` mockups; reuse existing HUD parts; state deviations.

## Acceptance criteria (testable)

- [ ] `UnitPopupModel` returns the range line as text: T-72B3 `2.0 km (8 hex), max 3.0 km`; infantry `500 m (2 hex), max 750 m`; Uragan `35 km (whole map)`, `min 750 m`.
- [ ] A pure range-overlay model (`src/presentation`, no scene) returns for a selected unit three hex sets: `effective`, `extended` (effective < d <= max), `blocked` (in range but no LoS); T-72B3 on open plains gives 8-ring sets with `blocked` empty.
- [ ] A forest hex between unit and target hex puts that target hex (and those behind it on the line) into `blocked` for a tank, but not for Homar-K.
- [ ] Artillery: sets cover every map hex at distance >= 3 and none at distance 1-2; sets never contain off-map hexes.
- [ ] Unit selection draws the overlay and deselection or end of turn clears it (view test: highlight node count before/after).
- [ ] Forecast tag text: distance 6 for T-72B3 shows no falloff; distance 10 shows `-25 %` (factor 0.75 from 8 effective / 12 max); distance 12 shows `-50 %`.
- [ ] Enemy at distance 5 behind a forest: no crosshair; RMB message uses `no_line_of_sight`; artillery at distance 2: `too_close`.
- [ ] Catalog panel lists effective/maximum range in metres for all six units and matches the `.tres` values.
- [ ] Performance: overlay for a whole-map artillery on a 30 x 24 map adds <= 1 draw call (one merged mesh or one multimesh) and keeps 60 FPS.
- [ ] `tools/screenshot.sh` frame with a selected T-72B3 is read and compared with the mockup; deviations listed in Implementation notes.

## Playtest (for the human)

1. Start the default battle, select a T-72B3: an outline appears out to 8 hexes, a paler band to 12 hexes; forest and hill hexes behind blockers are dimmed.
2. Select Homar-K: the whole map is outlined except a small hole of 2 hexes around the unit.
3. Hover an enemy at 10 hexes with the tank selected: tag shows `DIST` and `-25 %`.
4. Hover an enemy hidden behind a forest: no crosshair; RMB says no line of sight.
5. Open the unit card and the catalog: ranges in km / m shown, same as the manual.
6. Watch the frame rate with Homar-K selected (60 FPS).

## Player manual

Update docs/MANUAL.md: stats table "Range" column and bullet (metres, effective vs maximum, hexes are 250 m); Combat section (range replaces "range is not blocked by terrain"; line of sight rules; distance falloff to 50 %; counterattack needs reach and sight; artillery minimum range 3 hexes and whole-map reach; remove "no minimum range" and the Homar-K vs Uragan "6 vs 5" example, replace with the new numbers); worked examples at lines about 156-166 (distances and falloff); the attack tag and range overlay description (generalised from "Rocket artillery range"); unit catalog panel text.

## Out of scope

- Rules and numbers (TASK-131a); fog of war (TASK-007); operational-map strike ranges; animations of shots; ammunition.

## Implementation notes

- New pure `RangeOverlayModel` (effective / extended / blocked sets; blocked is a subset of the other two, so outlines follow distance only), `RangeText` (m/km, `2.0 km (8 hex), max 3.0 km`, DIST, falloff), `RangeOverlayMesh` (geometry; kept out of MapView, which hit the 1000-line lint limit).
- MapView.show_attack_range(effective, extended, blocked): still two meshes (fill + outline, same draw calls as before); tints are vertex colours, so `ground_overlay.gdshader` now multiplies `COLOR` (sRGB -> linear) into the albedo.
- Tag: `DIST n hex (x km)` always, `RANGE -25 %` beyond effective range. Ring/toast reasons `NO LINE OF SIGHT`, `TARGET TOO CLOSE` (strings.csv). Popup stat shows short range text; catalog the full line.
- Deviations from the plan: blocked hexes are a dark wash, not a hatch (no pattern in the overlay shader); "whole map" = max range >= 40 hexes (RangeText.WHOLE_MAP_HEXES). Overlay frame seen in a screenshot (amber outline + paler outer band visible); the dimming of blocked hexes is faint and was not verified against a mockup (no mockup exists for it). FPS with whole-map Homar-K not measured.
- Manual updated by game-designer; README screenshot refreshed.
