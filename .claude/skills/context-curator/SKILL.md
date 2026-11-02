---
name: context-curator
description: Keeps the session context as small as possible – decides what to read, what to delegate, what to drop, and when to suggest /compact or /clear. Usage: /context-curator [audit]
---

Goal: finish the work with the fewest tokens in context. Apply these rules for the rest of the session; with `audit` (or when the context already feels heavy), report where the weight is and what to do about it.

## Before reading

- Search first (Grep/Glob), then Read only the needed range (`offset`/`limit`). Never Read a whole large file "to get oriented": docs/GDD.md, docs/ARCHITECTURE.md, docs/design/*, `.tscn`/`.tres` maps, `tools/*.py` big files – open the section by heading or line range.
- Don't re-read a file already in context or one you just edited (Edit/Write errors if it failed).
- Skip generated or bulky paths: `.godot/`, `.test.log`, `.screenshots/`, `data/maps/*.tres`, `tools/import_map_fixtures/`, `docs/tasks/*.jsonl`, `docs/tasks/task_costs.json`.
- Images (screenshots) are expensive: render and Read one only when the visual result is the thing being checked; use the multi-state `SCREENSHOT_SHOTS` run instead of several runs.

## Big docs

`docs/GDD.md` (~120 KB), `docs/ARCHITECTURE.md` and `docs/tasks/BACKLOG.md` are never read whole: `tools/doc.py gdd|architecture ["<heading>"]` prints one section, `tools/backlog.py --ready` lists ready tasks. Pass subagents section headings, not pasted text.

## Command output

- Use the quiet tools: `tools/test.sh <filter>` (failures + summary only), `tools/check.sh` once at the end, not after every edit. Run a filtered test while iterating.
- Pipe noisy commands through `tail -n 40`, `grep`, `head`, `wc -l`; for `git` prefer `--stat`, `--name-only`, `-n 10`, `--oneline`. Write long output to the scratchpad and grep it.
- Never paste logs back into your replies; quote only the failing lines.

## Delegation

- Move exploration that would pull many files into context to a subagent (`Explore` for "where is X", `general-purpose` for multi-step research) – only its conclusion comes back. Ask for a short answer: file:line references and a few sentences, no code dumps.
- Don't spawn agents for a lookup you can do with one Grep, and don't fork for work whose output you need in full anyway.
- Implementation of a larger task: follow `/implement-task` (cold-start agents get headings and paths, not whole documents).

## Replies and notes

- Short answers: result first, no recap of the diff the user can see, no restating the request. Reference `file:line` instead of pasting code.
- Don't narrate options you won't pursue; give one recommendation.
- Keep durable facts in the right place instead of re-deriving them: task state in the task file's "Implementation notes", decisions in docs/adr/, user preferences in memory. Then they can be dropped from the conversation safely.

## When to compact or clear

You cannot run `/compact` or `/clear` yourself – tell the user to. Suggest it, once, briefly, when:
- a task is done and committed (or its state is saved in the task file) and the next one is unrelated → `/clear`;
- the session has grown large (many big reads, long logs, screenshots) but the work continues → `/compact` with a focus hint, e.g. `/compact keep: current task id, changed files, failing tests, open decisions`;
- you notice you are re-reading things or losing earlier details.

Before suggesting it, make sure nothing is only in the conversation: write the current state (task, changed files, what's left, how to resume) into the task file or a short note, so the compacted/cleared session can continue from it.

## `audit` output

Reply with at most 10 lines: (1) the biggest context consumers so far (files read, outputs, images, subagent reports), (2) what can be dropped or replaced by a narrower read, (3) a recommendation: continue / `/compact <focus>` / `/clear`, plus the state to save first.
