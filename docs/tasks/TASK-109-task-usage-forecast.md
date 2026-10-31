# TASK-109: Usage forecast per task – expected % of the 5-hour and weekly limit in the backlog view

- **Status**: ready
- **Layers**: tools (Python stdlib: `tools/task_cost.py`, `tools/devtools/`, `tools/backlog_view/`; tested with `unittest`, wired into `tools/check.sh`). No game code changes.
- **Depends on**: – (builds on the devtools chat's limit tracking, `tools/devtools/chat.py`, and the backlog view)
- **Model**: sonnet

## Goal

Before starting a task, the human sees roughly how much of the subscription's 5-hour session and weekly limit `/implement-task` will use on it (e.g. "~15–30 % session · ~3–6 % week"), and whether it fits in what is left of the current 5-hour window – so they can pick what to implement now and what to leave for after the reset.

## Background (what data exists)

- Claude Code transcripts in `~/.claude/projects/<project-slug>/<session>.jsonl` (subagents in `<session>/subagents/agent-*.jsonl`) record per API response the `model` and `usage` (`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`). About 130 past `/implement-task` sessions exist; the task is in `<command-args>` of the first user message (`TASK-089b`, but also bare `057` or `TASK 001` – normalise).
- The CLI's stream reports the limit windows (`rate_limit` → `unifiedWindows.five_hour` / `seven_day` `.utilization`, 0–1); devtools already keeps the latest value (`ChatManager.limits`). Historical transcripts contain only a handful of these snapshots.
- Anthropic does not publish how many tokens 1 % of a window is. The token → % ratio must be **measured**: utilization at the start and end of devtools-run task sessions.

## Acceptance criteria (testable)

### 1. Historical cost per task (`tools/task_cost.py`)

- [ ] `tools/task_cost.py [--projects-dir=…] [--out=docs/tasks/task_costs.json]` scans the project's transcripts, finds `/implement-task` sessions, normalises the argument to a task ID (`57`, `057`, `TASK 057`, `task-057` → `TASK-057`; `TASK-089b` kept with its suffix) and sums usage of the main session **plus its subagents**.
- [ ] Cost is a single weighted number per task: tokens weighted by model and token kind (input / cache write / cache read / output), weights from a small table in the script (relative API prices per model family; unknown model → the opus weights + a warning). Also stored: raw token sums per kind, models used, number of sessions, wall-clock span.
- [ ] Several sessions of the same task (resumed, playtest fixes) are summed into one entry; free chats without a task are ignored.
- [ ] Output is deterministic (sorted keys / IDs) so re-running on unchanged transcripts gives no diff. The JSON contains no prompts or message text – only IDs, numbers and model names.
- [ ] Unit tests on small fixture transcripts in a temp dir: argument normalisation, subagent inclusion, multi-session summing, weighting, malformed lines skipped.

### 2. Calibration: cost → % of each window (devtools)

- [ ] For every devtools session started from a task (`/implement-task`), devtools records the latest `five_hour` and `seven_day` utilization at the start and at the end of each turn, together with the session's weighted cost so far (same weights as `task_cost.py`, shared code – no second copy of the table).
- [ ] Samples are appended to a calibration file (e.g. `docs/tasks/usage_calibration.jsonl`; the human may choose to keep it out of git – decide and document). A sample is dropped when a window reset (`resets_at` changed) falls inside it, or when other sessions ran in parallel during it (utilization is account-wide; devtools knows its own concurrent sessions – note that IDE sessions it can't see make the data noisy).
- [ ] From the samples, compute `percent_per_cost` for each window (robust fit, e.g. median of Δutilization / Δcost over samples with Δutilization ≥ 2 percentage points). With fewer than N usable samples (N in one constant, e.g. 5) the ratio is "uncalibrated".
- [ ] Tests: reset inside a sample → dropped; parallel session → dropped; fit on synthetic samples recovers the ratio within 10 %.

### 3. Forecast per open task

- [ ] For each task with status `ready`, `blocked`, `idea` or `in progress`, estimate the weighted cost from finished tasks' costs: features are at least the **Model** line (sonnet / opus), the **Layers** line (core / ai / presentation / tools), and the task file's size (number of acceptance-criteria checkboxes and length). The method is simple and explainable (e.g. median cost of tasks with the same model × layer group, scaled by checkbox count relative to the group median) – record the choice in the implementation notes.
- [ ] Output is a **range** (e.g. 25th–75th percentile of the comparable tasks, scaled), not one number; with fewer than 3 comparable tasks the group falls back to all finished tasks and the result is marked "low confidence".
- [ ] `in progress` tasks show the forecast minus what is already spent (from transcripts), floored at 0.
- [ ] Tests: deterministic forecast on a fixture set of costs + task files; fallback and low-confidence paths.

### 4. Backlog view

- [ ] `tools/backlog_view.sh` table gets a sortable **Usage** column: with calibration `~15–30 % · ~3–6 % wk`; without calibration the relative cost (e.g. `S` / `M` / `L` / `XL` by quantiles of finished tasks, tooltip with the weighted cost range) and a hint "uncalibrated – run tasks from devtools to calibrate".
- [ ] Finished tasks show their **actual** cost (and actual % when calibrated) in the same column, so forecasts can be compared with reality.
- [ ] The side panel of a task shows the forecast basis: comparable tasks used (IDs with their actual cost), the range, confidence.
- [ ] When the view can read the current limits (devtools running, or the latest values stored by devtools), a task whose upper estimate exceeds the remaining 5-hour window gets a warning marker ("may not fit before the reset at 14:20"). Without live limits no marker is shown.
- [ ] The devtools backlog tab's "▶ Implement with Claude" shows the same estimate next to the button.
- [ ] Data refresh: the view recomputes from `task_costs.json`, calibration and task files (cheap); `task_cost.py` (transcript scan) is run by a button / on devtools start, not on every poll.

### General

- [ ] `tools/check.sh` passes; new Python tests are run by it.
- [ ] `CLAUDE.md` command list mentions `tools/task_cost.py` and the Usage column.

## Playtest (for the human)

1. Run `tools/task_cost.py`, open `tools/backlog_view.sh`: finished tasks show an actual cost, open tasks a size class (uncalibrated). Spot-check two tasks you remember as big / small – does the order make sense?
2. Run 5+ tasks via devtools "▶ Implement with Claude" without other sessions in parallel. The column switches to percentages; compare a forecast with the real change of the 5-hour bar in the devtools sidebar.
3. With the 5-hour window mostly used, a large task shows the "may not fit" marker.

## Player manual

None (internal tooling).

## Out of scope

- Predicting cost for `/model-unit` / `/research-unit` jobs (same machinery could be reused later).
- Exact per-message limit accounting – Anthropic's limit formula is not public; this is an empirical estimate.
- Changing how tasks are written to make them cheaper.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
