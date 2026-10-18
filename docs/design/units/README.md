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

`unit.json` omits empty values and is written by the tool with a fixed key order and 2-space indent, so git diffs stay small. `dimensions` (metres) is a nested object (`hull_length`, `overall_length`, `width`, `height`, `sources`), `armament` is `{main, secondary}`, and image names are `<view>_<n>.<jpg|png|webp>` (views: side, front, rear, top, three_quarter, detail, drawing). The tool also keeps a `revision` counter (concurrent-edit detection) and `updated` date in each `unit.json`. AI research adds `provenance` (per field: `source`, `verified`, `suggested`) and `image_candidates`; the agent only writes a transient `research.json` that the tool validates and merges. The JSON Schema is `tools/unit_catalog/unit.schema.json`. The tool also shows the latest `.screenshots/units/<id>_*_sheet.png` render sheet next to the side reference in its Model review section.

Ids: lowercase `a-z0-9_` (`poland`, `leopard_2a4`, `t72b3`). The unit id is also the name of the stats file and the model file.

## Workflow for a new unit

1. In the tool: create the unit, fill in the real name, class, operators (factions), real-world facts and dimensions with sources.
   Faster: create it with just the name and class and keep **Research the unit with AI** checked (or click **Research with AI** on the unit screen). The tool runs `/research-unit <id>` through the Claude Code CLI; the Jobs screen shows the live log. From Claude Code you can run the skill yourself and then click **Apply research**. AI values are marked `AI` with their source until you verify them (click "✓ Verified" or edit the value); different values for fields you had filled appear as suggestions ("Use" / "Dismiss"); proposed images are listed as candidates to download after checking the licence. Unverified AI dimensions and silhouette features block `ready_for_model`.
2. Add images: the best is a **side-view line drawing** or a clean side photo, then top / front, then three-quarter photos and details. Paste (Ctrl+V) or drag them in, set the view and the source.
3. List the **silhouette features** – the 3–5 things that make the vehicle recognisable from a distance (most important first).
4. When the readiness checklist is green, set the status to `ready_for_model`.
5. Click **Build model** in the tool's AI panel (or run `/model-unit <id>` in Claude Code). Afterwards look at the render vs. photo in the tool's Model review screen and write remarks into **feedback**, then click **Rework model** (or run `/model-unit <id>` again) if needed.
6. The game-designer adds the stats (`data/units/<id>.tres`) and puts the unit into faction rosters → status `in_game`.

## Images and licences

Images are references only. They never go into `assets/` or the game build, and **the image files are not in git** (`.gitignore`). Git keeps `unit.json` with each image's `source_url` and `license`. On another computer or a fresh clone, click **Restore missing images** on the overview, or **Restore from source URLs** on a unit. That downloads the files again under the same names. For Wikimedia it takes the 1920 px version, which is also what **Download** of an AI image candidate stores. Images that were pasted or dropped without an https source URL exist only on the computer where they were added, and the tool marks them as such. Always record the source URL and licence; that also keeps non-free images out of the repository history.
