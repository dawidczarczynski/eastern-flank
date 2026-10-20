# Unit catalog

Reference data for every **real unit** in the game (e.g. "Leopard 2A4", "T-72B3", "BM-21 Grad") and every **faction** (real countries). Edited with the local web tool **`tools/unit_catalog.sh`** (TASK-037) – you normally don't edit these files by hand.

Who uses it:
- the **game-designer** derives unit stats (`data/units/<id>.tres`) from the real-world facts by the rules in the GDD ("Factions and units");
- the **`unit-modeler`** agent builds the 3D model (`src/presentation/models/<id>.gd`) from the dimensions, silhouette features and images (`/model-unit <id>`).

The game itself never reads this folder – game data lives in `data/`. `docs/.gdignore` keeps Godot from importing the images.

## Layout

```
docs/design/units/
  classes.json                  # unit classes: id, label, mobility, required views, default mechanisms
  mechanisms.json               # registry of animation mechanisms (parameters, pivot contract)
  factions/<faction_id>.json    # name, ISO code, UI colour, camo palette (3), vest colour
  units/<unit_id>/
    unit.json                   # identity, real-world facts, dimensions, silhouette features, images, status, feedback
    side_1.jpg  front_1.png  drawing_1.png  …
    blueprint.md                # written by unit-modeler, shown read-only in the tool
```

`unit.json` omits empty values and is written by the tool with a fixed key order and 2-space indent, so git diffs stay small. `dimensions` (metres) is a nested object (`hull_length`, `overall_length`, `width`, `height`, `sources`), `armament` is `{main, secondary}`, and image names are `<view>_<n>.<jpg|png|webp>` (views: side, front, rear, top, three_quarter, detail, drawing). The tool also keeps a `revision` counter (concurrent-edit detection) and `updated` date in each `unit.json`. AI research adds `provenance` (per field: `source`, `verified`, `suggested`) and `image_candidates`; the agent only writes a transient `research.json` that the tool validates and merges. The JSON Schema is `tools/unit_catalog/unit.schema.json`. The tool also shows the latest `.screenshots/units/<id>_*_sheet.png` render sheet next to the side reference in its Model review section.

Ids: lowercase `a-z0-9_` (`poland`, `leopard_2a4`, `t72b3`). The unit id is also the name of the stats file and the model file.

## Mechanisms

How a unit animates is a property of the **real vehicle**: the Homar-K and the 9K57 Uragan are both class `mlrs`, but one stows the launcher facing the rear and has full traverse, the other has limited traverse and blast shields. So the animations are declared **per unit** in `unit.json`; the entry is **authoritative**. `classes.json` only suggests defaults (`default_mechanisms`, e.g. `["wheels", "launcher", "stabilisers"]` for `mlrs`), which are pre-filled when a unit is created and then corrected from the real vehicle.

`mechanisms.json` is the **registry** of every known mechanism, read by the tool, the schema, the skills and the Godot contract test (TASK-043). One entry has:

- `id`, `label`, `description`, and `status` – `implemented` (the game animates it) or `planned` (can already be declared; the contract test checks pivots only for implemented ones);
- `params` – the parameters, each with a `type` (`number` with `min`/`max`, `enum` with `values`, `angle_range` = `[lo, hi]` with `min <= lo <= 0 <= hi <= max`, or `"full"` where `allow_full`), a `default` and a `help` text (`unit` optional);
- `pivots` – the node paths the model must provide below its root (`{i}` = contiguous index run from 0, `min` = minimum count, `with` = paths that must exist for the same index, `meta` = metadata keys the pivot carries);
- `owns` – top-level pivots only this mechanism may create (a model with such a pivot must declare the mechanism).

In `unit.json`, `mechanisms` is an object from mechanism id to its parameters, e.g. `"launcher": {"traverse_deg": [-30, 30], "max_elevation_deg": 55, "stowed": "front"}` (`"wheels": {}` has none). On save the tool validates ids, parameter names and values (errors name `mechanisms.<id>.<param>`), fills missing parameters with the registry defaults and writes everything in registry order. Defaults filled by the tool and the class pre-fill carry `provenance` entries `mechanisms.<id>` / `mechanisms.<id>.<param>` with source `default` / `class default` and `verified: false`; AI research (`/research-unit`) proposes mechanisms and parameters with sources the same way as other fields. Removing a mechanism removes its provenance.

**Readiness:** `ready_for_model` needs a non-empty `mechanisms` and no unverified mechanism value (AI, default or class default) – the model and its animations are built from them. The game never reads this folder: the parameters reach it through the model file (TASK-043). Hull rocking on slopes is not a mechanism; every vehicle gets it from its mobility.

## Foot units (squads)

A squad (class `infantry`, `engineer`, a dismounted `atgm` team) has no hull, so the entry describes **one soldier in full kit plus the squad's make-up** – the model is a few soldiers built from one parameterised soldier kit (TASK-032). The fields mean:

| Field | For a squad |
|---|---|
| `real_name` | descriptive English name ("Mechanised Infantry Squad"), no designation |
| `class` | `infantry` while the carrier is not modelled (`mech_infantry` is reserved for a squad with its vehicle) |
| `crew` | number of dismounts in the squad |
| `armament.main` | the service rifle (model, calibre) |
| `armament.secondary` | squad MG, grenade launchers, AT weapons carried by the squad |
| `protection` | helmet and body armour models |
| `dimensions.height` | one soldier standing, with helmet |
| `dimensions.width` | one soldier across the shoulders with vest and pouches |
| `dimensions.hull_length` | one soldier front to back, with vest and pack |
| `silhouette_features` | what tells this soldier apart at a distance: helmet shape, vest / plate carrier, rifle profile, the AT launcher on one soldier, pack |
| `camo_note` | uniform camouflage pattern (the colours themselves are in the faction file) |
| `details` / `skip` | kit worth modelling (launcher, optics, MG) / kit to leave out (radios, insignia, small pouches) |
| images | soldiers in full kit of that army: side, front, and a photo showing the AT weapon |

The tool knows foot units by `mobility: foot`. **Readiness** for them needs only the soldier's **height** (width and depth are optional) and **any photo of a soldier** – side, front or three-quarter, since there are no line drawings of soldiers. The form relabels the fields ("Dismounts in the squad", "Soldier height (with helmet)" …) and hides weight, speeds and ranges. `tools/render_unit.sh` compares only the soldier height with the model ("Real: soldier height 1.8 m"), because the model's footprint is the whole squad. The height comes from the kit (helmet) more than from anthropometry: a photo with a known reference or the army's anthropometric data – say which in `dimensions.sources`.

## Workflow for a new unit

1. In the tool: create the unit, fill in the real name, class, operators (factions), real-world facts and dimensions with sources.
   Faster: create it with just the name and class and keep **Research the unit with AI** checked (or click **Research with AI** on the unit screen). The tool runs `/research-unit <id>` through the Claude Code CLI; the Jobs screen shows the live log. From Claude Code you can run the skill yourself and then click **Apply research**. AI values are marked `AI` with their source until you verify them (click "✓ Verified" or edit the value); different values for fields you had filled appear as suggestions ("Use" / "Dismiss"); proposed images are listed as candidates to download after checking the licence. Unverified AI dimensions, silhouette features and mechanisms block `ready_for_model`.
2. Add images: the best is a **side-view line drawing** or a clean side photo, then top / front, then three-quarter photos and details. Paste (Ctrl+V) or drag them in, set the view and the source.
3. List the **silhouette features** – the 3–5 things that make the vehicle recognisable from a distance (most important first).
4. When the readiness checklist is green, set the status to `ready_for_model`.
5. Click **Build model** in the tool's AI panel (or run `/model-unit <id>` in Claude Code). Afterwards look at the render vs. photo in the tool's Model review screen and write remarks into **feedback**, then click **Rework model** (or run `/model-unit <id>` again) if needed.
6. The game-designer adds the stats (`data/units/<id>.tres`) and puts the unit into faction rosters → status `in_game`.

## Images and licences

Images are references only. They never go into `assets/` or the game build, and **the image files are not in git** (`.gitignore`). Git keeps `unit.json` with each image's `source_url` and `license`. On another computer or a fresh clone, click **Restore missing images** on the overview, or **Restore from source URLs** on a unit. That downloads the files again under the same names. For Wikimedia it takes the 1920 px version, which is also what **Download** of an AI image candidate stores. Images that were pasted or dropped without an https source URL exist only on the computer where they were added, and the tool marks them as such. Always record the source URL and licence; that also keeps non-free images out of the repository history.
