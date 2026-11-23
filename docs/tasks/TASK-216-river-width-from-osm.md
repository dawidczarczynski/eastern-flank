# TASK-216: Real-scale look: river widths from OSM (class and `width` tag)

- **Status**: ready
- **Layers**: importer (`tools/import_map.py`, python tests) + data (map `.tres` / loaders of the river links) + presentation (`FeatureRibbonPlanner` per-river water width, `RiverShape`)
- **Depends on**: TASK-108c
- **Sections**: ARCHITECTURE "River water and bridges" (and the line-link data section; `tools/doc.py architecture` lists headings)
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Rivers keep their real character: a small named stream is a few metres wide, a lowland river about 8 m, a large river or canal wider – instead of one 8 m width for every river (TASK-108c).

## Design

- Importer: for every river way keep the OSM `waterway` class (`river` / `canal` / named `stream`) and the `width` tag when present (metres; accept `"12"`, `"12 m"`, `"12.5"`, ignore junk). Store a per-river **water width in metres** with the river links: `width` tag if valid (clamped 1–60 m), else by class: stream 3 m, river 8 m, canal 10 m. Tactical maps from older data fall back to 8 m (loader default, no re-import required).
- Optional second source (only if cheap, else leave as note): rivers that have a `waterway=riverbank` / `natural=water + water=river` polygon along them – measure the polygon width across the centreline (median over samples) and prefer it over the class default.
- Presentation: `FeatureRibbonPlanner` uses the stored width of the chain as the base water width (the ± noise, bank band 3 m, source taper and bridge span all follow it); a chain's width is constant along it; at a confluence the tributary keeps its own width (the 9 m fade of TASK-108c stays). Everything in metres via `MapScale`.
- Bridge span, riparian belt distances and reed band follow the real width / edge automatically (they use the planner's edge).

## Acceptance criteria (testable)

- [ ] Importer (python tests): `width="12"` → 12 m; `"12 m"` → 12; `"abc"` / `-3` ignored; clamp 1–60; class defaults stream 3 / river 8 / canal 10; same input twice → identical output.
- [ ] Loader: a map without width data loads with 8 m for every river; with data, the planner's water width of a chain equals the stored width (± noise bounds ±25 %).
- [ ] A 3 m stream and a 25 m river in one hand-made grid: cross-sections 3 m and 25 m (± noise) of water, bank band stays 3 m, `water_edge` consistent with the shader.
- [ ] Bridge `span_m` over the wide river = its water width / |sin| + 8 m, capped at 40 m.
- [ ] Re-import Suwałki: rivers get classes/widths; the number and course of river links is unchanged.
- [ ] Screenshots Read by the agent: Suwałki river stretch with a stream and a river of different widths, at default and true-size scale.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle`: small streams are visibly narrower than the main river; after a confluence the larger river is wider.
2. Bridges over the wider river are longer.

## Player manual

"Roads and rivers": river width follows the real river (small streams narrow, big rivers wide).

## Out of scope

- Fords, depth, movement rules by river width (rules stay as TASK-108).
- Bridges over wide rivers beyond the 40 m cap, valley carving.

## Implementation notes

_Filled in by the agent when done._
