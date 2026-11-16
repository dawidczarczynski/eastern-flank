# TASK-165: Operation objectives: make hold-condition readable (held for N turns vs at the end)

- **Status**: idea
- **Layers**: presentation
- **Depends on**: TASK-164
- **Sections**: to be filled when specified
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The objectives panel states the rule explicitly (e.g. 'Hold the corridor open on turn 30' vs 'for 30 consecutive turns'), shows current status and a counter/progress where applicable.

## Notes for the later specification

Source: the human's notes after a full operation playthrough (2026-11-16). Unclear whether the gap must be held open for 30 turns or only open on the last turn. The player cannot tell.

- First confirm in the GDD what the actual rule is; if ambiguous, decide it with the human.
- Objective text per objective type: rule, current status, turns left, what resets the counter.
- Include a toast/journal entry when an objective flips state.
- Acceptance criteria and playtest steps to be written (`/refine-task TASK-165`).

## Player manual

To be decided when specified.

## Out of scope

- To be decided when specified.

## Implementation notes
