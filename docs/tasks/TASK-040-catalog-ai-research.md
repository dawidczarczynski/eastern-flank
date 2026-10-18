# TASK-040: Unit catalog – AI research and agent jobs from the UI

- **Status**: to playtest
- **Layers**: tools (unit catalog, `.claude/skills/`)
- **Depends on**: TASK-037 (soft: TASK-036 for model jobs)
- **Model**: sonnet

## Goal

The human types a unit name and the data comes from the web via AI. The catalog form is then used to verify and correct it, not to type everything in. `/research-unit` and `/model-unit` can be started from the tool's UI.

## Acceptance criteria (testable)

- [x] `/research-unit <id>` skill writes `docs/design/units/units/<id>/research.json` (fields with a source URL each, image candidates, summary) and touches nothing else.
- [x] `catalog.apply_research` merges it: empty fields are filled and get `provenance.<path> = {source, verified: false}`; a different value for a field the human filled becomes `suggested`; invalid values, unknown fields, `class`/`mobility` are rejected and reported; dimension sources go to `dimensions.sources`; image candidates are validated (https, view) and deduplicated; the file is deleted after a successful merge.
- [x] `ready_for_model` is refused while `dimensions.hull_length/width/height` or `silhouette_features` hold an unverified AI value.
- [x] Image candidates can be downloaded (server-side, https only, ≤ 15 MB, image sniffed) into `<view>_<n>` with source URL and licence, or dismissed.
- [x] UI: AI-filled fields are marked until verified ("✓ Verified" or editing the value); suggestions show "Use" / "Dismiss"; "Apply research" button when `research.json` is pending; candidate list with Download / Dismiss.
- [x] Job queue in the server running `claude -p` (one job at a time, `--permission-mode dontAsk` with an allow-list per job kind, live log, cancel), buttons "Research with AI" (also in the New unit dialog) and "Build / Rework model", Jobs screen.

## Playtest (for the human)

1. Start `tools/unit_catalog.sh` from a WSL terminal. The console prints `AI jobs: <path to claude>`.
2. Click New unit, enter "K2 Black Panther", leave "Research the unit with AI" checked, and create it. The form is greyed out, and the AI panel shows a running job with a "Live log" link.
3. Open Jobs, then the job. Searches and page fetches appear live. After a few minutes the job is `done`, with the agent's summary and the merge report.
4. Back on the unit: filled fields have a yellow left border and an `AI` tag with a source link. The checklist asks you to verify the dimensions. Click "✓ Verified" or edit a value, and the marker disappears.
5. For a suggestion, fill a field by hand and run "Research with AI" again. The field shows "AI suggests …" with "Use" and "Dismiss".
6. Download an image candidate. It appears under Images with its source and licence.
7. (After TASK-036) On a `ready_for_model` unit, click "Build model". Later, on a `modeled` unit with Feedback filled in, click "Rework model".

## Player manual

None (developer tool).

## Out of scope

- Automatic download of images (licences must be checked by the human).

## Implementation notes

- `catalog.py`: `RESEARCH_FIELDS`, `MODEL_CRITICAL_FIELDS`, `provenance` and `image_candidates` validation/normalisation, `merge_research`, `apply_research`, `add_image_bytes` (shared by uploads and candidate downloads), `dismiss_candidate`; `unit_detail` reports `pending_research`. Schema: `unit.schema.json`. Tests: `tools/unit_catalog/test_research.py`.
- `server.py`: `POST /api/units/<id>/research/apply`, `POST /api/units/<id>/candidates {action: download|dismiss, url}`; `fetch_image` (injectable for tests).
- The agent never writes `unit.json` itself: it writes `research.json`, and the tool validates and merges it (stable formatting, `revision` bump, so an open editor gets a 409 instead of silently overwriting).
- `jobs.py` + `server.py` (`GET /api/ai`, `GET/POST /api/jobs`, `GET /api/jobs/<id>?since=N`, `POST /api/jobs/<id>/cancel`; unit detail carries the unit's active `job`); decision record: ADR 0008. Tests: `test_jobs.py` with a fake `claude` script.
- Verified end to end on `homar_k`: about 6 min, $0.73, 13 fields filled, 5 Commons candidates. The first run showed that relative `Edit(...)` rules break after the agent `cd`s in Bash, so the rules are now absolute.
- The CLI prints "Ignoring permissions.allow entries from .claude/settings.json: this workspace has not been trusted". This is harmless, because jobs pass their own allow-list. Running `claude` interactively once in the repo (from WSL) and accepting the trust prompt silences it.
- Reference images are no longer meant for git (`.gitignore` on `docs/design/units/units/*/*.{jpg,jpeg,png,webp}`), because of repository size and licences. `unit.json` keeps `source_url` and `license`. `POST /api/units/<id>/images/restore` and `POST /api/images/restore` re-download missing files under their recorded names, and refuse if the source now serves a different format. Candidate downloads and restores use a Wikimedia original's 1920 px thumbnail, falling back to the original. The UI marks missing files and local-only images (no https source).
- Model jobs are wired but untested for real: they need `tools/render_unit.sh` and the contract test from TASK-036.
