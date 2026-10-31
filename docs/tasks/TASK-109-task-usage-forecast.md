# TASK-109: Usage forecast per task – expected % of the 5-hour and weekly limit in the backlog view

- **Status**: done
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

- **Cost** (`tools/task_cost.py`): a session belongs to a task from its `/implement-task <arg>` command on; `/clear` or the next `/implement-task` ends the part (two old sessions held two tasks each). Responses are counted once per `message.id` (the transcript writes one line per content block with the same usage – about half the lines are such duplicates). A subagent file (`<session>/subagents/**/agent-*.jsonl`) goes to the part its first response falls into. Weights = API list prices per million tokens of the model family (opus 5 / 6.25 / 0.5 / 25, sonnet 3 / 3.75 / 0.3 / 15, haiku 1 / 1.25 / 0.1 / 5 for input / cache write / cache read / output), so the weighted cost reads as "API-equivalent $"; `<synthetic>` entries are skipped, unknown models weigh like opus with a warning. Scanning all ~850 MB of transcripts takes ~3 s (a substring filter skips tool-result lines before `json.loads`).
- **Kept history**: Claude Code deletes transcripts after `cleanupPeriodDays` (30 days by default), so `refresh` merges a scan with the existing `docs/tasks/task_costs.json` (per task the entry with the higher cost wins) and the file is **committed** as the record of past tasks. Run by devtools on start (background thread) and by the backlog view's **↻ Costs** button (`POST /api/costs/refresh`, JSON content type only).
- **Calibration** (`tools/devtools/chat.py`, fit in `tools/usage_forecast.py`): every turn of a task session (a message to an idle session, or a turn the agent opens itself) records the windows' utilization and the session's weighted cost from its transcript at start and end. Flags: `parallel` (another devtools session was busy or had a running subagent at the start, started a turn meanwhile, or was busy at the end), `stale` (the CLI reported no limits during the turn); a window's sample is unusable when its `resets_at` changed or passed. Samples are kept with their flags in `docs/tasks/usage_calibration.jsonl` – **committed** (only numbers, task IDs and chat IDs; slow to collect, can't be regenerated). Fit: usable samples are summed per chat session; sessions that raised the window by ≥ 2 points give Δ% / Δcost; median once there are 5 (`MIN_SAMPLES`). Per-turn Δ is too small for the weekly window, which is why turns are summed per session. Only the devtools instance that owns the chat history records samples. The live windows go to `.devtools/limits.json` (git-ignored) for the backlog view.
- **Forecast** (`usage_forecast.usage_rows`): comparable tasks = finished (`done` / `to playtest`) tasks with a cost and the same **Model** (missing → sonnet) × layer group (from **Layers**: logic = core/ai, view = presentation/scenes/shaders/HUD/UI/models, logic+view, tools, other). Fewer than 3 → all finished tasks, "low confidence" (also every idea without a task file). Range = 25th–75th percentile of their costs, point = median, scaled by the geometric mean of the checkbox-count ratio and the text-length ratio against the comparables' medians, clamped to 0.5–2×. `in progress` → minus what the transcripts say was spent, floored at 0. Size classes S/M/L/XL are the quartiles of the finished tasks' costs.
- **Orchestrator model** (added after the human locked `/implement-task` to Sonnet, ADR 0017 amendment): `task_costs.json` stores per task the `orchestrator` (model family that did most of the main session's weighted work, subagents excluded) and `main_cost`. Forecasts compare only with finished tasks whose orchestrator ran on Sonnet once there are `MIN_ORCHESTRATED` (10) of them – 24 at the time of writing; with fewer, all finished tasks (`history: "all"`, said in the tooltip / panel). Opus orchestrators took a median 57 % of a task's cost, Sonnet ones 28 %.
- **Backlog view**: sortable Usage column (class badge; `~a–b % · ~c–d % wk` once the 5-hour window is calibrated; actual cost / actual % for finished tasks, outlined badge; `?` for low confidence; ⚠ "may not fit before the reset at HH:MM" when the upper % exceeds what is left of a live 5-hour window), the side panel lists the comparable tasks with their costs, the estimate stands next to "▶ Implement with Claude". The page's version hash now covers task_costs.json, the calibration file and the live limits, so it refreshes when they change.
- **Review follow-ups**: a turn's start cost is the previous turn's end cost (consecutive samples chain, the transcript is read once per turn, outside the chat lock – only a session resumed from older history reads it once at its first turn); the sample is taken off the session in the same locked block that handles `result`, so a message sent right after can't steal it; `.devtools/limits.json` is rewritten at least once a minute while limits arrive and the backlog view ignores it after 30 minutes (no stale "may not fit" marker); `task_costs.json` writers use per-process temp files and malformed entries are dropped on load; `/implement-task TASK-089b some note` takes the first word; message ids are deduplicated across the whole scan. `resetsAt` from the CLI is epoch seconds (checked in `.devtools/chats.json`), as the reset check assumes.
- **Deviation from criterion 2**: the fit sums a chat session's usable samples before the ≥ 2 point floor (median over sessions, not over single turns) – one turn rarely moves a window by 2 points, the weekly one almost never. Even so a small task may add < 2 points to the week, so `seven_day` calibrates later than `five_hour`.
- **Limitations**: IDE sessions devtools can't see (like this one) make calibration samples noisy – the median and the ≥ 2 point floor damp that. Model lines are missing on most old tasks, so they count as sonnet although many ran on opus. The forecast is only as good as the history: size scaling is clamped, ideas without a file get the all-tasks range. `merge` keeps the higher of old and new cost per task, so if part of a task's transcripts were cleaned up and it then gets a new session, the new work may be under-counted (fix later by storing per-session costs). Cache writes use one weight although 1-hour-TTL writes cost more than 5-minute ones (small systematic error). If the CLI emits `rate_limit_event` only on status changes, most samples will be `stale` – check the calibration file during the playtest.
