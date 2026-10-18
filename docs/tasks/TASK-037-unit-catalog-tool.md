# TASK-037: Unit catalog – local web tool for collecting unit references (`tools/unit_catalog.sh`)

- **Status**: to playtest
- **Layers**: tools (Python stdlib server + static HTML/JS UI; catalog logic tested with `unittest`, wired into `tools/check.sh`). No game code changes.
- **Depends on**: – (can start any time). Data layout: `docs/design/units/README.md`. GDD: "Factions and units".
- **Model**: sonnet

## Goal

The human can collect everything needed to add a real unit to the game – real name, faction(s), class, real-world facts, dimensions, silhouette features and reference images – in a comfortable browser UI, and the data lands directly in the repo where the game-designer (stats) and the `unit-modeler` agent (3D model) read it. Built for dozens of units and many factions.

## Data (source of truth: files in the repo)

```
docs/design/units/
  classes.json                      # list of unit classes (id, label, mobility default, model contract)
  factions/<faction_id>.json
  units/<unit_id>/unit.json
  units/<unit_id>/<view>_<n>.<jpg|png|webp>
  units/<unit_id>/blueprint.md      # written by unit-modeler, shown read-only in the UI
```

- Ids: `^[a-z0-9_]{2,48}$` (e.g. `poland`, `leopard_2a4`, `t72b3`, `bm21_grad`). The unit id is also the future `data/units/<id>.tres` and `src/presentation/models/<id>.gd` name.
- **`classes.json`** (seeded by this task): `infantry` (foot), `mech_infantry` (foot + carrier), `tank` (tracked), `ifv` (tracked/wheeled), `apc`, `recon`, `sp_artillery`, `mlrs`, `air_defense`, `atgm`, `engineer`; each `{id, label, mobility: "tracked"|"wheeled"|"foot", required_views: [...]}`. Editable in the UI (add a class).
- **Faction** `{id, name, iso_code, color, camo: [hex, hex, hex], vest_color, notes}`; `name` in English (UI translations happen in the game).
- **Unit** `unit.json`:
  - identity: `id`, `real_name` (shown in game as-is, e.g. "Leopard 2A4"), `variant_note`, `class`, `mobility`, `operators` (faction ids), `in_service` (years text), `country_of_origin`;
  - real-world facts (all optional, free-text or number + unit): `crew`, `weight_t`, `armament` (main / secondary), `protection`, `speed_road_kmh`, `speed_offroad_kmh`, `range_km`, `fire_range_km` (artillery), `notes`;
  - **dimensions** (metres): `hull_length`, `overall_length`, `width`, `height`, plus `sources` (list of URLs);
  - for the modeler: `silhouette_features` (ordered list, most recognisable first), `details` (nice to have), `skip`, `camo_note`;
  - `images`: `[{file, view: "side"|"front"|"rear"|"top"|"three_quarter"|"detail"|"drawing", source_url, license, note}]`;
  - `status`: `draft` → `ready_for_model` → `modeled` → `in_game`; `feedback` (the human's comments on the latest render for the modeler); `updated` (ISO date).
- A JSON Schema file `tools/unit_catalog/unit.schema.json` documents the format; Python validates against the same rules (no third-party packages).

## Tool

- `tools/unit_catalog.sh [--port=8765]` → `python3 tools/unit_catalog/server.py`, **Python 3.8 stdlib only** (`http.server.ThreadingHTTPServer`, `json`, `cgi`-free multipart or base64 uploads). Binds **127.0.0.1 only**, prints `Unit catalog: http://localhost:8765` and opens it with `wslview`/`explorer.exe` if available (WSL → Windows browser via localhost forwarding).
- Static UI `tools/unit_catalog/index.html` + `app.js` + `style.css`, no build step, no CDN (works offline). Style: the game's HUD palette (`docs/design/README.md` – dark panels `#11130f`, text `#ebe8df`, accent `#e2c069`), IBM Plex if available locally (`assets/fonts/ibm_plex/` served by the server), system fallback.
- **API** (JSON): `GET /api/catalog` (classes, factions, unit summaries with completeness), `GET/PUT /api/units/<id>`, `POST /api/units` (create, id from real name slug, editable), `POST /api/units/<id>/images` (base64 body `{view, data, ext, source_url, license}`), `DELETE /api/units/<id>/images/<file>`, `PUT /api/factions/<id>`, `PUT /api/classes`, `GET /files/...` (serves `docs/design/units/**` and `.screenshots/units/**` read-only). Every write goes through `catalog.py` (pure module: validation, id/slug rules, safe paths, atomic write via temp file + rename, stable key order and 2-space indent so git diffs stay small).
- **Screens**:
  1. **Overview**: units table – real name, class, operators (faction colour chips), image count, completeness bar, status; filters by faction / class / status, text search; "New unit" button. Factions list with colour swatch and camo chips; "New faction".
  2. **Unit editor**: form sections (Identity, Real-world facts, Dimensions, For the modeler, Images, Status & feedback). Operators as a multi-select of factions; silhouette features as a reorderable list. Autosave (debounced PUT) with a visible "saved" state.
  3. **Images**: drop zone for drag & drop, **paste from clipboard** (Ctrl+V of a copied image), file picker; each image card has a view selector, source URL, license, note, delete; images grouped by view; click → large preview.
  4. **Readiness checklist** (live): `ready_for_model` can only be set when `real_name`, `class`, `operators` (≥ 1), `height`, `width`, `hull_length`, ≥ 3 `silhouette_features`, and ≥ 1 `side` or `drawing` image exist; missing items are listed. Changing status back is always allowed.
  5. **Model review** (when files exist): shows `blueprint.md` and the latest render sheet `.screenshots/units/<unit_id>_*_sheet.png` next to the side reference; the `feedback` box goes back to the modeler on the next `/model-unit` run.
  6. **Faction editor**: name, ISO code, UI colour, three camo colours and vest colour with colour pickers and a live camo swatch preview.
- Images: accepted `jpg`, `png`, `webp`, checked by magic bytes, max 15 MB, stored with names `<view>_<n>.<ext>`; never inside `assets/` (`docs/.gdignore` keeps Godot from importing them).

## Acceptance criteria (testable)

- [x] `tools/unit_catalog/test_catalog.py` (`unittest`, run by `tools/check.sh` via `python3 -m unittest discover -s tools/unit_catalog`):
  - id rules: `leopard_2a4` ok; `Leopard 2A4` → slug `leopard_2a4`; `../x`, `a`, empty → rejected;
  - safe paths: an image file name or id with `/`, `..` or absolute paths is rejected;
  - unit validation: unknown class / unknown operator faction → error listing the field; negative dimension → error;
  - readiness: a unit missing `height` and side images reports exactly those two items and can't be saved as `ready_for_model`; a complete one can;
  - save/load round trip keeps data and produces byte-identical output when saved twice (stable formatting);
  - image upload: PNG/JPEG magic bytes accepted, a text file renamed `.png` rejected; file names `side_1.png`, `side_2.png` increment.
- [x] Server smoke test in the same suite: start on a free port in a thread, `GET /api/catalog` returns the seeded classes; `PUT` a unit then `GET` returns it; `GET /files/../../project.godot` → 403/404.
- [x] The server refuses non-localhost binds (no flag to change it).
- [x] `docs/design/units/` is seeded with `classes.json`, the factions `poland` (`PL`, `#5b93d6`) and `russia` (`RU`, `#d76a52`) with starting camo palettes (Poland vehicles `#4b5320` / `#3b2f22` / `#1e1f1a`, Russia vehicles `#4d5a3a` / `#23221d` / `#8a8466` – the human adjusts them), and **draft entries for the six first-roster units** with id, real name, class, operators and status `draft` (`m1a2_sepv3` "M1A2 SEPv3 Abrams", `homar_k` "Homar-K", `pl_mech_infantry` "Mechanised Infantry Squad", `t72b3` "T-72B3", `bm27_uragan` "9K57 Uragan", `ru_motor_rifle` "Motor Rifle Squad") – facts, dimensions and images are filled in by the human in the tool.
- [x] `CLAUDE.md` "Commands" and `docs/AGENTIC_WORKFLOW.md` mention `tools/unit_catalog.sh`; `docs/design/units/README.md` describes the layout above (replacing the old `<faction>/<unit>/specs.md` layout).

## Playtest (for the human)

1. Run `tools/unit_catalog.sh` and open the printed URL in your Windows browser.
2. Open the faction "Poland", adjust the three camo colours; check the swatch preview.
3. Open the draft "M1A2 SEPv3 Abrams": fill dimensions and facts; paste a side-view image from the clipboard (Ctrl+V) and drag in a front photo; set their views and source URLs.
4. Watch the readiness checklist until it allows `ready_for_model`.
5. Check in git: `docs/design/units/units/m1a2_sepv3/unit.json` and the images exist; `git diff` of a small edit is small.
6. Refresh the page – everything is still there; filter the overview by faction and class.

## Out of scope

- Fetching data or images from the web automatically (the agent can fill facts with WebSearch on request), editing game stats (`data/units/*.tres` stay the game-designer's), authentication / remote access.
- **Image licensing**: the tool records `source_url` and `license`; if the repo ever becomes public, images without a free licence must be removed from history – noted in the README, not enforced.

## Implementation notes

- **Files**: `tools/unit_catalog/` (`catalog.py` pure logic, `server.py` HTTP API, `index.html`/`app.js`/`style.css` vanilla UI with no CDN, `unit.schema.json`, `test_catalog.py`, `.gdignore`) and `tools/unit_catalog.sh`. `tools/check.sh` gained a `== catalog tests ==` step: 51 `unittest` tests on Python 3.8, including a server smoke test on a free port.
- **Data format decisions**: `dimensions` is a nested object (`hull_length`, `overall_length`, `width`, `height`, `sources`) and `armament` is `{main, secondary}`. Unknown keys are rejected in both `validate_unit` and the schema. `unit.json` has an integer `revision`, bumped only when the content changes, so saving twice gives byte-identical files. Files are written atomically with mode 0644.
- **Concurrency (after review)**: one lock covers every write. The client sends `revision`, and a stale PUT gets 409 (the UI then reloads the unit). Saves, uploads and deletes run through one client-side queue. An upload picks the file name and saves `unit.json` under the lock, and removes the file if the save fails. A delete saves `unit.json` before unlinking, and refuses to remove the last side or drawing image of a `ready_for_model` unit.
- **Security**:
  - The server binds to 127.0.0.1 only and rejects foreign `Host` headers.
  - Writes need `Content-Type: application/json` and a localhost `Origin` when one is sent, which blocks CSRF.
  - Ids and file names are matched with fullmatch, and paths must resolve inside the allowed folders.
  - `/files/` is read-only with an extension allowlist.
  - Uploads are checked by magic bytes, with a 15 MB image limit and a 25 MB body limit.
- **API notes**:
  - Factions are created with `POST /api/factions` (409 if the id exists) and edited with `PUT /api/factions/<id>`.
  - `PUT /api/classes` takes `{"classes": [...]}` and refuses to remove a class that units still use.
  - `PUT /api/units/<id>` edits only existing images' metadata; images are added and removed via the image routes.
  - Only `ready_for_model` is gated by readiness.
- **Extras**: a Classes screen (`#/classes`), a warning when leaving with unsaved edits, and up/down reordering of silhouette features.
- **Seed**: `classes.json` (11 classes), `factions/poland.json`, `factions/russia.json`, and six draft units (`m1a2_sepv3`, `homar_k`, `pl_mech_infantry`, `t72b3`, `bm27_uragan`, `ru_motor_rifle`).
- **Verification**: the orchestrator rendered the overview, the unit editor and the faction editor with headless Edge from Windows against a scratch copy of the data; they display correctly. Drag & drop, Ctrl+V paste and the image flow were exercised only through the API (curl), not in a real browser.
