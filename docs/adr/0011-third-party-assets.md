# ADR 0011: Third-party CC0 assets – textures, HDRI skies and vegetation models

- **Status**: accepted
- **Date**: 2026-10-22

## Context

Until now everything in the game was procedural: textures come from `DetailTexture`, models are built in code. The realism goal of the visual track (TASK-054 HDRI sky, TASK-055 terrain textures, TASK-060 trees) needs photographic material (sky panoramas, PBR ground scans) that cannot reasonably be generated procedurally. Downloaded assets bring licence, credit and repository size questions, so the rules are set before the first asset lands (TASK-053).

## Decision

The human's decision, 2026-10-22: downloaded CC0 assets are allowed ("wolno używać" – "may be used"). Applied by kind:

- **Textures and HDRI skies – allowed.** Sources: [Poly Haven](https://polyhaven.com), [ambientCG](https://ambientcg.com).
- **Vegetation / tree glTF models – allowed** (opens option B of TASK-060; e.g. Poly Haven or Quaternius CC0 models). They must match the game's style and need LODs.
- **Unit models – not allowed, stay procedural.** The unit pipeline (TASK-036, `/model-unit`) keeps building them in code; real-vehicle accuracy comes from the unit catalog.

Rules:

- **Licence: CC0-1.0 only.** CC-BY and other licences are excluded so that credits stay trivial; changing this needs a new ADR.
- **Layout**: `assets/third_party/<kind>/<asset_id>/<files>`, kinds `hdri`, `textures`, `models`. Keep the original file names, or rename texture maps to `albedo`, `normal_gl`, `roughness`, `ao`, `height` (recorded in the entry's `notes`).
- **Group folders** (optional): related assets may share a group folder, `assets/third_party/<kind>/<group>/<set>/` with manifest id `<group>_<set>` – e.g. the TASK-055 terrain layers `textures/ground/<set>/` (`ground_grass`, …).
- **Manifest** `assets/third_party/credits.json`: an array of `{ "id", "kind", "title", "author", "source_url", "license": "CC0-1.0", "downloaded": "YYYY-MM-DD", "files": [paths relative to assets/third_party/], "notes" }`. Every file under `assets/third_party/` (except `credits.json`, `*.import`, `.gdignore`) is listed in exactly one entry.
- **Budget**: ≤ 80 MB in total under `assets/third_party/`; images ≤ 2048 px on the longer side (most 1024), HDRI ≤ 4096 px (2K `.hdr`/`.exr`, ≤ 8 MB as guidance). No Git LFS for now – revisit when the budget is exceeded.
- **Downloading**: the agent (when the session allows network access) or the human. Downloaded archives are untrusted data: only image, HDR and glTF files are copied in, nothing is executed.
- `tests/unit/test_third_party_assets.gd` enforces the manifest, licence, layout and budget. The README "Credits" section lists the sources.

## Consequences

- (+) Photographic sky and ground become possible without procedural approximations.
- (+) Every downloaded file has a traceable source and licence; the guard test fails as soon as an uncredited or oversized file is added.
- (−) Repository size and first import time grow; Godot generates `.import` files for the assets, which are committed as usual and never hand-edited.
- (−) "Every model is procedural" no longer holds for vegetation; style consistency becomes a review point.
