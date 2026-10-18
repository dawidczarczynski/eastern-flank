# Unit catalog

Reference data for every **real unit** in the game (e.g. "Leopard 2A4", "T-72B3", "BM-21 Grad") and every **faction** (real countries). Edited with the local web tool **`tools/unit_catalog.sh`** (TASK-037) – you normally don't edit these files by hand.

Who uses it:
- the **game-designer** derives unit stats (`data/units/<id>.tres`) from the real-world facts by the rules in the GDD ("Factions and units");
- the **`unit-modeler`** agent builds the 3D model (`src/presentation/models/<id>.gd`) from the dimensions, silhouette features and images (`/model-unit <id>`).

The game itself never reads this folder – game data lives in `data/`. `docs/.gdignore` keeps Godot from importing the images.

## Layout

```
docs/design/units/
  classes.json                  # unit classes: id, label, mobility, required views/pivots
  factions/<faction_id>.json    # name, ISO code, UI colour, camo palette (3), vest colour
  units/<unit_id>/
    unit.json                   # identity, real-world facts, dimensions, silhouette features, images, status, feedback
    side_1.jpg  front_1.png  drawing_1.png  …
    blueprint.md                # written by unit-modeler, shown read-only in the tool
```

`unit.json` omits empty values and is written by the tool with a fixed key order and 2-space indent, so git diffs stay small. `dimensions` (metres) is a nested object (`hull_length`, `overall_length`, `width`, `height`, `sources`), `armament` is `{main, secondary}`, and image names are `<view>_<n>.<jpg|png|webp>` (views: side, front, rear, top, three_quarter, detail, drawing). The tool also keeps a `revision` counter (concurrent-edit detection) and `updated` date in each `unit.json`. The JSON Schema is `tools/unit_catalog/unit.schema.json`. The tool also shows the latest `.screenshots/units/<id>_*_sheet.png` render sheet next to the side reference in its Model review section.

Ids: lowercase `a-z0-9_` (`poland`, `leopard_2a4`, `t72b3`). The unit id is also the name of the stats file and the model file.

## Workflow for a new unit

1. In the tool: create the unit, fill in the real name, class, operators (factions), real-world facts and dimensions with sources.
2. Add images: the best is a **side-view line drawing** or a clean side photo, then top / front, then three-quarter photos and details. Paste (Ctrl+V) or drag them in, set the view and the source.
3. List the **silhouette features** – the 3–5 things that make the vehicle recognisable from a distance (most important first).
4. When the readiness checklist is green, set the status to `ready_for_model`.
5. Run `/model-unit <id>` in Claude Code. Afterwards look at the render vs. photo in the tool's Model review screen and write remarks into **feedback**, then run `/model-unit <id>` again if needed.
6. The game-designer adds the stats (`data/units/<id>.tres`) and puts the unit into faction rosters → status `in_game`.

## Images and licences

Images are references only – they never go into `assets/` or the game build. Record the source URL and licence for each image. If the repository is ever made public, images without a free licence (public domain / CC) must be removed from the history first.
