---
name: implement-task
description: Carries out a task from docs/tasks/ end to end – plan, delegation to subagents, tests, review, backlog update. Usage: /implement-task TASK-001
---

You are carrying out task `$ARGUMENTS` (if empty – take the first task with status `ready` from docs/tasks/BACKLOG.md).

1. **Understand**: read the task file in docs/tasks/ and the related sections of docs/GDD.md and docs/ARCHITECTURE.md. If the acceptance criteria are ambiguous – stop and ask the human (or have the `game-designer` agent clarify them).
2. **Status**: mark the task in BACKLOG.md as `in progress`.
3. **Plan**: split it into the logic part (core/ai) and the visual part (presentation). Logic first. Read the task's `- **Model**:` line (`sonnet` or `opus`; missing → `sonnet`).
4. **Logic**: delegate to the `gameplay-engineer` agent – pass it the task path and your plan, and set the Agent tool's `model` parameter to the task's Model. Delegate the visual part to `presentation-engineer` (same `model`) only once the logic and events are ready. Unit model tasks (the task's `- **Agent**:` line names `unit-modeler`) follow the `/model-unit` skill's steps (`.claude/skills/model-unit/SKILL.md`): check the unit's catalog entry in `docs/design/units/units/<id>/` first and ask the human for missing images or dimensions instead of delegating. Point agents to the specific parts of large references they need (e.g. a function in `docs/design/game_screen.scene.js` or a section of `docs/design/README.md`) instead of asking them to read whole files.
5. **Verification**: run `tools/check.sh` yourself – don't trust subagents' claims alone.
6. **Review**: delegate to the `reviewer` agent (always its default model, `sonnet` – don't pass the task's Model). Fix the reported problems (or justify why not) and repeat step 5.
7. **Wrap-up**: fill in "Implementation notes" in the task file, set status to `to playtest` (if there are visual changes) or `done`. Summarise for the human: what changed, test results, playtest steps. Don't commit unless asked.
