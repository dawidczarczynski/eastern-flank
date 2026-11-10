# TASK-112: Place names on the staff map

- **Status**: done
- **Layers**: tools (importer), core data, presentation
- **Depends on**: TASK-126 (done); soft: TASK-113 (done, country names)
- **Sections**: GDD "Operational map", GDD "Operational map view (TASK-093a ...)" (Lines bullet); docs/design/operational_map/README.md (zoom levels, typography)
- **Model**: sonnet

## Goal

The player reads the staff map like a paper map: cities, towns and large villages appear as labels as they zoom in, and **N** hides them. Labels are view data only; hexes stay mechanics.

## Acceptance criteria (testable)

Importer (`tools/import_map.py`, `tools/test_import_map.py`):
- [ ] Reads OSM `place=city|town|village` nodes with a `name` and writes `places`: name (OSM local `name`, diacritics kept, no transliteration, no `name:en`), position in the same units as `border_lines`, rank 0 = city, 1 = town, 2 = village.
- [ ] Villages are kept only with `population` >= 1000 [ASSUMPTION]; villages without the tag are dropped; after that the village list is capped so the total is <= 400 [ASSUMPTION] (largest population first, then name, then OSM id). Cities and towns are never dropped.
- [ ] Deterministic: sorted iteration, two runs give byte-identical output.
- [ ] Golden tests on the fixture cache: Suwałki, Białystok, Kaunas, Vilnius, Kaliningrad, Grodno are present with the right rank; a village below the threshold is absent; name keeps `ł`, `ą`, `ń` unchanged.
- [ ] `suwalki_theatre` is re-imported offline from the cache; `data/maps/` .tres now holds a few hundred places (state the count in the notes).

Core data (`src/core/data/imported_map.gd`, `tests/unit/`):
- [ ] `ImportedMap` gets `places` (name, position, rank) saved in the map .tres; save/load round trip keeps all entries and their order.
- [ ] Validation rejects an empty name, a rank outside 0..2, a non-finite position, a position outside the map rect (reason string like `_border_lines_problem`).
- [ ] A map .tres without `places` loads fine (empty list, no labels, no error).

Presentation (`src/presentation/operational/`, new label overlay in screen space like StaffMapCounters; not Label3D):
- [ ] Pure helper (RefCounted, no nodes): `visible_places(places, screen_positions, sizes, zoom_level)` returns the shown labels. Ranks shown: zoom level 0 = cities, 1 = + towns, 2 = + villages (level from the existing `StaffMapCameraMath.zoom_level`, with its hysteresis).
- [ ] Overlapping label rects are dropped; the higher rank (lower number) wins; equal rank: larger population/list order first (list order is the importer's sorted order) - same input always gives the same output.
- [ ] A label whose anchor is off-screen or on the far side of the view is not shown; labels keep a fixed screen font size at every zoom and tilt (city 13, town 11, village 10 px [ASSUMPTION], from the mockup typography).
- [ ] The visible set is rebuilt only when zoom, pan, tilt or the toggle changes (test: a second call with unchanged camera does not recompute).
- [ ] **N** toggles all place labels, default on; the key is not used elsewhere in the staff map (checked: no `KEY_N`); the hint line lists it.
- [ ] Labels sit below counters, orders and cards, and do not hide the faint large country names (labels only inside the screen, name layer unchanged).
- [ ] 60 FPS kept at the closest zoom with villages on (no per-frame rebuild).

## Playtest (for the human)

1. Open Operation, zoom out fully: only the big cities (Kaliningrad, Vilnius, Kaunas, Białystok) are labelled.
2. Scroll in over the Suwałki Gap: towns appear (Suwałki, Marijampolė, Grodno), then at the closest zoom villages; none overlap, a city never loses its label to a village.
3. Zooming does not change the text size; tilting and panning keep labels glued to their places.
4. Press N: all labels vanish; press N again: they return. Select a formation, open the order ring: labels stay under counters and cards.
5. Look: restrained light text with a dark halo [ASSUMPTION, per the operational_map mockup], readable on land and over the sea.

## Player manual

docs/MANUAL.md section 12b: in "What you see" add one sentence on place names (cities from far away, towns closer, large villages close in; names in the local language); add a controls row "Place names on / off | N".

## Out of scope

- Country names and borders (TASK-113), water / land cover / relief (TASK-126), river and lake names, capitals styling, distance-to-cursor tie-break, trying alternative label positions near counters (mockup E/W/NE/SW), name:en or transliteration, using places in rules or the formation panel location text.

## Implementation notes

- Importer reads `place=city|town|village` nodes from new cached `pl1_*` tiles; `suwalki_theatre.tres` now holds **400 places** (10 cities, 270 towns, 120 villages). The 400 cap leaves a thin village layer. Names are local-language (Belarus, Kaliningrad in Cyrillic), so the label font is a FontVariation of Plex Condensed with JetBrains Mono fallback for Cyrillic.
- `ImportedMap`: parallel arrays `place_names/place_positions/place_ranks`, `place_at()`, `hex_world_rect()`, validation in `_places_problem()`.
- Presentation: `StaffMapPlaceFilter.visible_places` takes a `ranks` array instead of a places array (avoids per-place dictionaries); `StaffMapPlaceLayer` draws labels, rebuilt only on camera/zoom/toggle change; N toggles. The staff map projection is orthographic, so there is no behind-camera case.
- Deviation: the hint line was too wide; "F5: save" was dropped from it (the Save button shows F5) and "Right-click" shortened to "RMB" in English. It may still clip at the end.
- Not done: `data/maps/CREDITS` does not mention the new `pl1` tiles yet.
- Playtest changes: cities 17 px SemiBold; the 30 largest towns also show at the widest zoom; labels avoid unit counters (cities and towns slide aside, villages drop); Cyrillic names get a Latin line under them (`PlaceTransliteration`, with a small table of Polish names such as Grodno); the place zoom level has no hysteresis so zooming in and out switches at the same step.
