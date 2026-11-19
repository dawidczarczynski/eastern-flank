# TASK-185: Devtools page in the main menu (debug runs)

- **Status**: done
- **Layers**: presentation
- **Depends on**: TASK-184
- **Sections**: docs/TOOLS.md
- **Model**: sonnet

## Goal

With `--debug` the main menu has a DEVTOOLS page that opens the developer's benches (first: the arena), so they are one click away instead of a command line.

## Acceptance criteria (testable)

- [x] Without `--debug` the menu is unchanged (no button, no page).
- [x] With `--debug` a DEVTOOLS plate on the main page opens a page with an ARENA button (opens the arena scene) and Back; Esc goes back like the other pages.
- [x] Built from the existing menu plates (`MenuStyle`), English only (not translated).

## Playtest (for the human)

1. `tools/run_windows.sh --debug`: the menu shows DEVTOOLS under SETTINGS; ARENA opens the arena.
2. `tools/run_windows.sh` (no flag): no DEVTOOLS plate.
3. The arena's Leave (menu) returns to the main menu; check the page looks like Settings.

## Player manual

none (developer tool).

## Out of scope

- More content on the page: TASK-186a, TASK-186b.

## Implementation notes

`MainMenu.debug` (from the `--debug` user argument, settable by tests) adds the plate and the page; `_build_devtools` is the place to add further tools. docs/TOOLS.md describes it.
