# Visual design reference – operational (staff) map

Source: two Claude Design proposals received 2026-11-07 (the answer to the "Claude Design proposal" awaited in [TASK-093a](../../tasks/TASK-093a-staff-map-base.md), "Direction change"). Both are self-contained bundles: **open them in a browser** (they load React from a CDN; fonts are embedded). Like the battle-screen reference in [../README.md](../README.md) they are a **target look, not code to run** – port ideas and numbers to Godot.

| File | Contents |
|---|---|
| `operational_map_system.html` | "Mapa sztabowa – styl i komponenty": the style spec in 14 numbered sections (style direction, palette, line hierarchy, label typography, zoom levels, formation counters, orders, front line, turn bar, formation panel + hex card, contact + after-action report, political layer, side symmetry, Godot notes) |
| `operational_map_mockups.html` | "Mapa sztabowa – kluczowe widoki": four 1440×900 screens – theatre Z0, Suwałki Gap Z1 (order planning), contact notice, the same scene seen from Russia |

Descriptions in the files are Polish; UI strings in them are English (translation keys) – matches CLAUDE.md. The theatre geometry in the mock-ups is stylised; the game draws it from the OSM / Copernicus import (TASK-092a).

## Verdict

- **Direction:** dark, muted, **flat top-down with baked relief** (orthographic camera, hillshade from the DEM burnt into the base texture, soft-light ~0.8). 2.5D (~34° tilt) is shown and rejected as the default – it compresses the north (~40 % fewer pixels per hex), makes arrows and the front uneven and needs billboard counters; suggested only as an intro animation / "briefing" mode. Light paper map and full 3D rejected as well.
- **Conflict with our direction change (GDD, 2026-11-07: "modern, slightly 3D welcome"):** the *modern, no paper* part is confirmed by the proposal; the *slightly 3D* part is not – the designer argues for flat. **Decided by the human (2026-11-07): 2.5D is wanted** – [TASK-125](../../tasks/TASK-125-staff-map-restyle-2-5d.md) implements the proposal's look with a tilted camera (default ~35°, `V` toggles flat) and answers the designer's objections (pixel compression, uneven lines, billboard counters).
- Everything is consistent with HUD v3 (Chakra Petch, JetBrains Mono, amber `#e8b04a`) and with the architecture rules (view reads state only, counters on a `CanvasLayer`, one palette resource).

## Key values

**Palette** (one `MapPalette` resource, key names as below; there is no NATO / Russia colour, only own / enemy):
`map.void #0b0d0b` · `map.land #1d211c` · `map.forest #22302a` (edge `#2b3d31`) · `map.urban #363931` (edge `#4b4e45`) · `map.marsh #46677a` (7×5 px hatching) · `water.sea #0f1820` · `water.lake #132029` · `water.shore #2b4454` · `river.major #5384a0` / `named #46728c` / `minor #3a5c70` · `road.t1 #b4ac98` (outline `#0d100d`) / `t2 #7f7a6c` / `t3 #55534a` · `rail #70746b` · `border #a9afa1` · `side.own #5b93d6` (ink `#0f1a26`, country tint 5 %) · `side.enemy #d76a52` (ink `#2a110b`, tint 5.5 %) · `side.neutral #a8a598` · `ui.amber #e8b04a` · `ui.text #dfe5d6` · `ui.muted #8d9585` · `ui.alert #e07c5e` · strength `#b9d38a` (≥75 %) / `#e2c069` (≥50 %). Water labels `#6f95ab`, label halo `#111411` 3 px.

**Line hierarchy** (screen px, constant under zoom; Z0 / Z1 / Z2): front 2.4 / 3 / 3 (+ teeth 5.5 px every 15 px) · state border 1.4 dash-dot (casing 3.6) · road t1 1.3 / 1.9 / 2.4 · major river 1.8 / 2.2 / 3 · rail – / 1 / 1 · road t2 – / 1.3 / 1.6 · named river – / 1.4 / 1.8 · minor river – / – / 1.2 · road t3 and dotted drainage canals Z2 only 0.9. OSM mapping: motorway / trunk / primary → t1, secondary / tertiary → t2, rest → t3; rivers > 40 km with a name → major / named. Draw simplified OSM geometry (Douglas–Peucker ~150 m), not hex centres. One line mesh per class, built once; zoom changes only width (shader uniform `px_per_world`) and visibility.

**Zoom levels:** Z0 < 1.6 px/km (countries, capitals + 2 cities, t1 roads, 4 rivers, lakes > 3 km, front, brigade counters ×n) · Z1 1.6–5 px/km (+ towns, t2, rail, named rivers, battalions, orders) · Z2 > 5 px/km (+ villages, t3, canals, hex grid 7 %; `G` forces the grid at 12 %). Fade 150 ms with ±10 % hysteresis. Hillshade az 315°, alt 38°, ×1.4 on Z0; optional 25 m contours at Z2. Towns and lakes drawn from real outlines, not single hexagons.

**Typography:** Chakra Petch (country names 26–34 px, tracking .42em, 55–60 % stance colour; titles) · IBM Plex Sans Condensed (places: capital 13 px caps, city 12.5, town 11, village 10, water italic) · JetBrains Mono (data on the map). Label collisions: rank, then distance to cursor; counter-colliding labels try E, W, NE, SW, else hide.

**Counters** (fixed screen size, on a `CanvasLayer`): own rectangle 40×26 px, enemy **diamond** 38×38 px (shape encodes the side, colour is the second channel); recommended style A "HUD" (side fill, ink glyph, cut corner); B classic APP-6 and C outline as alternatives. Strength = 5 slanted segments under the frame (HP colours). Estimated enemy: dashed frame, "?", "EST.", no strength bar. States: normal, selected (2 px corners), has order, moved, in contact (dashed `ui.alert` ring), low strength, estimated / detected enemy, stack / aggregate. Icons stay APP-6.

**Orders:** posture = line style, picker `[1] March [2] Attack [3] Defend` under the selected formation (keys 1/2/3, ⌫ cancels); route smoothed with Chaikin ×3 through A* hex centres, halts shown as a cross-bar with "+n"; planning preview full opacity with hex dots and an amber target, issued orders 82 % without dots; enemy orders invisible (fog), intel may show a thin dotted red "predicted axis".

**Front line:** edge between an RU hex and a NATO hex on land, chained into polylines; smoothed variant (edge midpoints + Chaikin ×3) recommended, exact variant for debug / Z2 grid; teeth point to the enemy from the player's perspective (flip when playing Russia); rebuilt only on `control_changed`; no front against a closed country.

**Turn bar** (top centre): side + formation count, TURN number, date, day / night (odd turns 06–18, even 18–06) with sun / moon, side to move, End turn with `ORDERS n / m ↵` (greys out as "AI moving…"); under it the escalation chip (level, name, 5 ticks green → red; click opens the ladder).

**Panels:** formation panel on the right edge (strength, posture, order, supply, cohesion, location, subunits list); hex card at the cursor (`pointer-events: none`; elevation, road, river, country + stance, control, move cost, tags, route row only while planning); closed-country card (stance to you, access, forces estimate, opens at escalation level, entry cost). **Contact notice** next to the battle hex with a dimmed map: attacker vs defender, strength, odds, 3-band forecast (breakthrough / stalemate / repulse), Play battle `B` / Auto-resolve `A`, contact queue "1 OF 2" on the left. **After-action report:** who holds, retreat, strength before → after, losses own / enemy, front and escalation effect as separate lines, Continue `↵`. **Political layer:** escalation ladder table (0 Crisis … 4 Strategic threshold), decision card with expiry, 2–3 options with effects in one line, advisor. **Symmetry:** the view function `stance(country, player_side)` returns own / enemy / neutral / closed; everything else follows.

**Layer toggles / keys in the mock-ups:** P political, F front line, O orders, T terrain, R rail, G hex grid, L labels; Tab next formation, Esc menu, F centre on formation. Interaction: hover = amber hex outline 1.6 px + 10 % fill; selection = 2 px corners around the counter.

## Where it lands in the backlog

- Palette, line hierarchy, zoom levels, label typography, hillshade → restyle of the staff map (TASK-093a follow-up, to be written) and TASK-112 (place names, borders, shaded relief).
- Counters, formation panel, hex card → TASK-092b; turn bar, escalation chip → TASK-093b / TASK-115; route preview and posture picker → TASK-092c / 092d; front line → TASK-093c; borders, stance tints, closed-country card → TASK-113 / 114; contact notice, report → TASK-094 / 095; decision card, ladder → TASK-117 / 119.
- Not adopted automatically (see CLAUDE.md "look first, rules later"): the three-band forecast, supply "3 d", cohesion and mortar / firing statuses are mock-up ideas that need their own rules.
