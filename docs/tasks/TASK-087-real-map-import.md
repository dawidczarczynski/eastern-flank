# TASK-087: Maps from real geography – data sources, hex scales, offline import tool (study + v1)

- **Status**: ready
- **Layers**: tools (Python, offline) + core (map loading) + docs (ADR, credits)
- **Depends on**: – (soft: TASK-086)
- **Model**: opus (geodata, projection, determinism)

## Goal

Operational and tactical maps are generated from real map data of the eastern flank (GDD "Vision decisions"), so a battle is fought on the real terrain where formations met.

## Step 1 – study (decide with the human, write into the ADR)

- **Sources and licences**: OpenStreetMap land use / natural / roads / waterways (ODbL – attribution, share-alike of the derived database), elevation: Copernicus GLO-30 DEM (attribution) or Poland's GUGiK NMT (free, very detailed; check licence). Extends ADR 0011 and the credits manifest (`assets/third_party/` test or a `data/maps/CREDITS` equivalent).
- **Scales**: proposed operational hex ≈ 5 km, tactical hex ≈ 250 m (a company frontage); tactical map size per battle (e.g. 30×24 hexes ≈ 7.5×6 km) vs. TASK-072 performance. Show 2–3 options with numbers.
- **Projection**: one local metric projection per theatre (e.g. UTM 34N for the Suwałki Gap); hex ↔ lat/lon mapping stored with the map.
- **Classification**: OSM tags → today's terrain types (plains, forest, hills, water) and the new ones TASK-108 will add (fields, urban, marsh, roads, rivers); dominant-cover rule per hex; elevation per hex from the DEM mean, hills from local relief.
- **Workflow**: data downloaded once (cache outside git), generated maps committed as data, the game never goes online.

## Step 2 – v1 tool (after approval)

- [ ] `tools/import_map.py <bbox> --hex=<m> --out=data/maps/<name>.tres` (stdlib + documented optional deps), deterministic: the same input gives byte-identical output (test).
- [ ] The core loads such a map into `HexGrid` with per-hex terrain and elevation; `TerrainSurface` works with `field == null` (authored elevation) – test with a small committed sample map.
- [ ] One real tactical sample (a few km around Suwałki or another spot the human picks) playable via a debug option, with a screenshot in the implementation notes.
- [ ] Python tests run in `tools/check.sh`.

## Playtest (for the human)

1. Start the sample battle; compare forests, lakes and villages with a real map of the area.

## Player manual

Note that maps follow real terrain (credits / attribution in the manual or credits screen).

## Out of scope

New terrain types' rules (TASK-108), the operational map itself (TASK-092), map editor.

## Implementation notes

_Filled in by the agent when done._
