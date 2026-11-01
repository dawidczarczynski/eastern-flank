# TASK-114: Countries and stances in the operational state – data, per-hex country, player-relative relation, open / closed hexes, legal stance changes

- **Status**: blocked
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data
- **Depends on**: TASK-113, TASK-092b
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The operation knows its countries and where each stands – neutral, aligned with a side, or at war on a side – and the rules can ask whether a side may enter or strike a hex (GDD "Operational layer" → "Countries and stances"; human decision 2026-11-01). This is the foundation of the operational freedom: later tasks add the escalation ladder (TASK-115), borders in movement (TASK-116), the player's decisions (TASK-117) and allied forces (TASK-118).

## Acceptance criteria (testable)

Data (`src/core/data/`, `data/`):

- [ ] `CountryDefinition` (Resource, `data/countries/<id>.tres`): `id` (StringName), `iso_code` (String, two letters), `display_name` (English, translation key), `sanctuary` (bool – sovereign soil of a nuclear power). `CountryDefinition.NAMES`, `find(id)`, `find_by_iso(code)` (null when unknown). Four files: `poland` PL false, `lithuania` LT false, `belarus` BY false, `russia` RU **true** (test reads them).
- [ ] `CountrySetup` (sub-resource) and `OperationDefinition.countries: Array[CountrySetup]`: `country` (CountryDefinition), `stance` (`&"neutral"`, `&"aligned"`, `&"belligerent"`), `side` (−1, 0, 1), `leaning` (−1, 0, 1). `suwalki_gap.tres` **[ASSUMPTION]**: poland belligerent 0 leaning 0; lithuania aligned 0 leaning 0; belarus aligned 1 leaning 1; russia belligerent 1 leaning 1.

State (`src/core/operational/`):

- [ ] `CountryState` (RefCounted): `id`, `definition`, `stance`, `side`, `leaning`, `casus_belli: Array[bool]` (per player – that player may declare hostilities on this country without escalation; both `false` at start), `breached_by: Array[bool]` (per player – that player has breached this country as a sanctuary; both `false`), `declared_by: Array[bool]` (per player – that player declared hostilities on it; both `false`).
- [ ] `OperationalState.countries: Array[CountryState]` (setup order), `get_country(id) -> CountryState` (null if unknown), `country_at(coord) -> StringName` (country id, `&""` for water / no country / off the map). `Operation.build` maps the map's ISO codes (TASK-113 `ImportedMap.country_at`) to country ids; `Operation.from_definition(definition, seed, grid = null, country_map: Dictionary = {})` takes `Vector2i → StringName` for hand-made test grids.
- [ ] `Operation.from_definition` rejects with `push_error` and null (one test each): an unknown stance; `neutral` with `side` ≠ −1; `aligned` / `belligerent` with `side` not 0 or 1; `leaning` outside −1 … 1; the same country twice; a country on the map without a setup; a map ISO code without a `CountryDefinition`; a formation placed on a hex that is **closed** to its player (below).
- [ ] `snapshot()` gains `countries: [{id, stance, side, casus_belli: [b, b], breached_by: [b, b], declared_by: [b, b]}]` sorted by id. The TASK-092b determinism test still passes.

Pure rules (`CountryRules`, static, `src/core/operational/country_rules.gd`). Test grid "strip": tiles q = 0 … 7, r = 0 … 1, plains; countries by column – q 0–1 `poland`, 2–3 `lithuania`, 4–5 `belarus`, 6–7 `russia`; stances as in `suwalki_gap` above:

- [ ] `relation(state, player, country_id) -> StringName`: `&"own"` (aligned or belligerent on the player's side), `&"enemy"` (belligerent on the other side), `&"hostile"` (aligned with the other side), `&"neutral"`, `&"none"` (empty id). Strip, player 0: poland own, lithuania own, belarus hostile, russia enemy; player 1: poland enemy, lithuania hostile, belarus own, russia own.
- [ ] `may_enter(state, player, coord) -> bool`: own → true; none → true; hostile / neutral → false; enemy → true, except a **sanctuary** country, which is open only when `breached_by[player]` (TASK-115 adds "or the level ≥ the ladder's `sanctuary_open_level`"). Strip, player 0: (1, 0) true, (2, 0) true, (4, 0) false, (6, 0) false; after setting `russia.breached_by[0] = true` → (6, 0) true. Player 1: (0, 0) true, (2, 0) false, (4, 0) true. **Side symmetry** (both sides are playable – GDD "Sides"; the sanctuary is a country flag, not a side rule): on the strip with a test `CountryDefinition` copy where `poland.sanctuary = true`, player 1 → (0, 0) false; after `poland.breached_by[1] = true` → true.
- [ ] `may_strike(state, player, coord) -> bool`: false on own soil, otherwise the same as `may_enter` (TASK-115 adds the ROE by target class).
- [ ] `set_stance(state, country_id, stance, side, cause: StringName, by: int) -> Array[Dictionary]` – the **only** place that changes a stance (TASK-115 / 117 / 118 call it). Legal transitions only (GDD table): neutral → aligned S; neutral → belligerent S; aligned S → belligerent S; aligned S → neutral. Anything else (same stance, aligned S → aligned other / belligerent other, belligerent → anything, neutral with a side) → `push_error`, no change, `[]` (one test per illegal case). Legal → the stance and side change, all three per-player flag pairs **keep** their values except `casus_belli`, which resets to `[false, false]`; one event `country_stance_changed` (`country`, `stance`, `side`, `previous_stance`, `previous_side`, `cause`, `by` – the player or −1).
- [ ] Example (test): strip, `set_stance(state, &"belarus", &"belligerent", 1, &"test", 0)` → belarus belligerent 1, `relation(0, belarus)` = enemy, `may_enter(0, (4, 0))` = true, one event with `previous_stance` aligned; then `set_stance(..., &"belarus", &"neutral", -1, ...)` → error, unchanged.
- [ ] The shipped operation: in `Operation.build("suwalki_gap", 7)` every formation stands on a hex open to its player and in the country of its group (Polish formations `poland`, Russian ones `russia` or `belarus`) (test).

Docs:

- [ ] docs/ARCHITECTURE.md "Two layers": `CountryDefinition`, `CountrySetup`, `CountryState`, `CountryRules` (relation, may_enter, may_strike, set_stance as the single change point); "Operational events": `country_stance_changed`.
- [ ] ADR (next free number – 0020 today): "Political state in the operational layer" – countries as data, stances and flags in `OperationalState`, every change through `CountryRules.set_stance` (later the trigger point for the ladder's reactions and allied formations), player-relative relations computed, never stored.

## Playtest (for the human)

None – no view yet (TASK-093). Review the start stances in GDD "Countries and stances".

## Player manual

None yet – not visible before TASK-093 / TASK-119. The manual's politics chapter (written with TASK-119) will describe: each country's stance seen from the player (own / hostile / enemy / neutral) and what it allows (entering, supply, strikes, battles on its soil), that a hostile or neutral country is closed, and that Russian soil is a sanctuary until the war is open or the NATO side has breached it (Polish and Lithuanian soil is not a sanctuary for Russia – the reason is given from GDD "Sides"), each written for both sides.

## Out of scope

- The escalation level and its ROE (TASK-115); closed hexes in route planning, order rejection, breach and casus belli incidents (TASK-116); the decisions that change stances (TASK-117); allied formations joining (TASK-118); supply through countries (TASK-096); hex control.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
