# TASK-147: Strike launcher markers: the concrete launcher or carrier appears at the launch point of a missile

- **Status**: ready
- **Layers**: core (`src/core/data/`, `src/core/operational/`) + data (`data/strike/`) + presentation (staff map strike layer) + tests
- **Depends on**: TASK-141b (soft: TASK-098a – launcher sites may later become air-defence / SEAD targets)
- **Sections**: GDD "Deep strikes", TASK-141a / TASK-141b task files, ARCHITECTURE event table (`strike_launched`)
- **Model**: opus (core data + event + view, determinism of the launch point, and a design step in one task; if the human wants it split, do 147a core / 147b view with sonnet each)

## Goal

When a missile is launched, the staff map shows a **marker of the concrete launcher or carrier** at the launch point, for the duration of the flight, then fading: aircraft for air-launched weapons, ship / submarine for naval ones, truck launcher (TEL / HIMARS-like) for ground missiles, a drone launch site for drones. The name comes from the means' `platform` text (TASK-141a, now flavour only).

## Acceptance criteria (testable)

Core:
- [ ] New field on `StrikeMeansDefinition`: `launcher_kind` (enum / StringName: `aircraft`, `ship`, `submarine`, `launcher` = ground TEL, `drone_site`), set in `data/strike/*.tres`: Kinzhal, Kh-101, JASSM-ER, Storm Shadow = `aircraft`; Kalibr, Tomahawk = `ship` (the `submarine` kind exists for later variants); Iskander-M, ATACMS, PrSM, Homar-K = `launcher`; Geran-2, Warmate = `drone_site`. Test over all 12 shipped files: each has a valid kind (none empty); the `platform` text is unchanged.
- [ ] Launch point: a pure function `StrikeRules.launch_origin(state, player, means_id, target_coord) -> Vector2i` (deterministic, no `state.rng` draw so existing replays do not change) – ground and drone launchers: the player's own installation / formation hex of the matching kind nearest to the target, else the player's home-edge hex used by the current strike trail origin (`StaffMapStrikeTrail.origin`, move this logic to the core); aircraft: own airfield nearest to the target, else home edge; ships: nearest own coastal / sea-edge hex, else home edge. **[ASSUMPTION]** until the map has real launch sites; record the rule in the GDD "Deep strikes".
- [ ] **Standoff rule (2026-11-11, TASK-141b):** the fallback launch point must be the standoff rule of `StaffMapStrikeTrail.launch_origin(state, player, target, range_hexes)` (own hex within the weapon's range whose distance to the target is closest to 90 % of `range_hexes`; ties lowest x, then y; no own hex within range: the border hex `origin()`), not the plain border hex - move that function to the core together with `origin`.
- [ ] `strike_launched` gets `launcher_kind` (String) and `origin` (Vector2i) fields; table in docs/ARCHITECTURE.md updated; `StrikeCommand` fills them; replay / codec fixtures stay valid (the fields are additive). Tests: field values for one weapon of each kind; same state + same command = same origin.
- [ ] `StaffMapStrikeTrail.origin` uses the event's `origin` when present (fallback to the old logic for old events).

View (**new element, no mockup: start with `/design-ui`** for the marker – silhouettes of aircraft, ship, TEL truck, drone site in the existing staff-map symbol style (see `unit_tokens_hex.html`, installation markers; reuse the hex-tile base of TASK-142 if the human picks it) with a name tag; implement only the variant the human picks):
- [ ] The marker appears at the event's `origin` when the strike launches, stays during the flight of the salvo (the longest trace duration, TASK-141b), then fades out in 0.6 s; it never outlives the strike toast. Pure helper test: visible alpha at t = 0, mid-flight, flight end, end + 0.3 s, end + 0.6 s (0).
- [ ] Label = the means' `platform` text (e.g. "truck launcher (HIMARS)"), shown at zoom levels where unit counters are labelled, hidden when zoomed out; fixed screen size like place names.
- [ ] Marker shape follows `launcher_kind` (5 shapes, test: every kind maps to a drawable shape; an unknown kind falls back to a plain dot).
- [ ] Several launches in one turn (up to 8 traces): markers at the same hex stack with an offset, not overlap; at most 8 markers; one `CanvasItem`, no node per marker, redraw only while a marker is visible (60 FPS, FramePacing quiet when idle).
- [ ] Markers are presentation only: no state change, not saved, not selectable, no click hit-testing.

## Playtest (for the human)

1. NATO `--debug`: fire JASSM-ER – an aircraft marker appears at the launch hex with "fighter-launched (F-16 Block 52+)", stays during the flight, fades. ATACMS / Homar-K – a truck launcher. Warmate – a drone launch site. Tomahawk (F9 grant) – a ship at the coast.
2. `--side=russia`: Kalibr ship, Iskander truck launcher, Kinzhal / Kh-101 aircraft, Geran-2 drone site.
3. Fire three strikes in a row from the same area: markers do not overlap and clear after fading.
4. Zoom in / out: label appears / disappears; check FPS.

## Player manual

Deep strikes chapter: each launch shows what fired it (aircraft, ship, truck launcher, drone site) at the launch point for the duration of the flight; the label names the platform; the launch point rule (nearest own airfield / coast / site, else the home edge).

## Out of scope

Launchers as targetable or destroyable objects, SEAD against launch sites (TASK-098), per-launcher stock or ammunition, sound, battle-scene use.

## Implementation notes

_Filled in by the agent when done._
