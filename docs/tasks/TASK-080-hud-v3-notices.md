# TASK-080: HUD v3 – turn banner, toast, targeting bar, loading screen

- **Status**: ready
- **Layers**: presentation (`BattleHud` notice widgets, new `Toast`, `TargetingBar`, `LoadingScreen`), localisation, tests. Role: **presentation-engineer**.
- **Depends on**: **TASK-076** (soft: TASK-077 – same file; TASK-082 uses the targeting bar and toast)
- **Model**: sonnet

## Goal

The transient notices from README section 06: turn banner, toast, targeting bar and loading screen, restyled; the first two replace today's banner, the latter two are new widgets with public APIs that later tasks call.

## Design

- **Turn banner** (top 36 %, 1.5 s): full-width horizontal fade band rgba(8,11,8,.88), 420 px wide-hatch bars above and below, `TURA 03 // RUCH`, faction name 40 px in faction colour. Same triggers as now (`on_turn_started`, result banner for victory/defeat keeps working).
- **Toast** `BattleHud.show_toast(text)`: bottom 130 centre, chamfer 8 top-left/bottom-right, `>>` in the active faction colour + mono 11.5, auto-hide 2.8 s (restart on a new toast). Use it for rejected commands that are currently silent, only where a reason string already exists (check `Command.validate()` reasons, do not invent rules).
- **Targeting bar** `BattleHud.show_targeting(title, unit_text, instruction)` / `hide_targeting()`: top 118 centre, 16 px amber hatch | amber block with title | unit · instruction · keycaps (`LMB`, `RMB`/`Esc`), 1 px border rgba(232,176,74,.6). No game mode yet – exposed for TASK-082 and exercised by a screenshot hook.
- **Loading screen**: `OPERACJA` amber / operation name 34 px / 220×6 hatch / status mono line; shown while the battle scene builds (map, models, textures) and freed on the first frame; uses `Scenario.operation_name` from TASK-079 (soft – fall back to the title).

## Acceptance criteria (testable)

- [ ] Scene tests: banner shows/hides with the 1.5 s timer and is replaced by the result banner; toast restarts its timer; targeting bar shows and hides and ignores the mouse.
- [ ] Banner/toast/targeting strings in en + pl via `tr()`, no raw keys.
- [ ] Loading screen does not delay the first frame measurably and never remains after load (test: freed after `ready`).
- [ ] `tools/check.sh` passes; screenshot hook for each widget (`tools/screenshot.gd`) so the agent can view them; README screenshot re-rendered.

## Playtest (for the human)

1. End a turn: banner with hatch bars and faction name; victory/defeat banner still appears.
2. Try an illegal action that raises a toast; it disappears after ~3 s.
3. Start the game: loading screen then battle. Compare with the HTML.

## Player manual

Nothing beyond banner naming; targeting bar documented with TASK-082.

## Out of scope

The targeting *mode* itself (TASK-081 / 082).

## Implementation notes

_Filled in by the agent when done._
