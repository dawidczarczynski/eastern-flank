# ADR 0008: The unit catalog tool runs Claude Code jobs; AI data is a proposal the human verifies

- **Status**: accepted
- **Date**: 2026-10-18

## Context

Typing real-unit facts into the catalog by hand is slow, and `/model-unit` had to be started from Claude Code. The human wants to type a unit name, let AI fill in the data from the web, and only verify it in the form. Model builds and reworks should also start from the UI. AI data can be wrong (mixed variants, invented numbers), and an agent spawned by a web server is a sensitive capability.

## Decision

- The catalog server (`tools/unit_catalog/jobs.py`) runs the **Claude Code CLI headless** (`claude -p`, stream-json). It uses the human's own login. The binary is found via `$UNIT_CATALOG_CLAUDE`, then `PATH`, then the binary bundled with the VS Code extension. There is no API key in the tool.
- Only two **fixed command templates** exist: `/research-unit <id>` and `/model-unit <id> [--faction=<id>]`. The browser sends only the kind and validated ids; argv is passed without a shell.
- Every job runs with `--permission-mode dontAsk` and a per-kind **allow-list**. File rules are absolute (`Edit(//<repo>/…)`), because a `cd` in the agent's shell moves the base of relative rules. Research may write only its unit's `research.json`. Model jobs may edit `src/presentation/models/**` and the unit's catalog folder, and may run only the listed scripts (`tools/check.sh`, `tools/render_unit.sh`, …). There is never an unrestricted `Bash`.
- **One job at a time** (FIFO, in memory), at most one queued or running job per unit, and a cancel that kills the process group. The unit form is read-only while a job works on that unit, and reloads when the job ends.
- **The agent never writes `unit.json`.** It writes `research.json`, and `catalog.apply_research` validates and merges it:
  - empty fields are filled, with `provenance.<path> = {source, verified: false}`;
  - a different value for a field the human filled becomes `suggested`;
  - invalid values are rejected and reported;
  - image candidates are listed, never downloaded automatically.
- Unverified AI values in dimensions or silhouette features block `ready_for_model`.
- The existing localhost-only binding, Host check and JSON/Origin CSRF check guard the job endpoints like every other mutating route.

## Consequences

- (+) A new unit takes a name, a few minutes of agent time and a verification pass. Every AI value carries its source.
- (+) The same skills still work from Claude Code. A `research.json` written there is applied with the "Apply research" button.
- (−) Jobs use the human's Claude subscription limits. Model jobs are long and costly.
- (−) Job history is lost when the tool restarts. The session id is shown so a run can be continued with `claude --resume`.
- (−) Model jobs edit the working tree while the human may be working too. Nothing is committed, and the job lists the `git status` changes.
