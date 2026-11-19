# TASK-186: Devtools content: live tunables and test benches

- **Status**: idea
- **Layers**: presentation (+ a small tunables store)
- **Depends on**: TASK-185
- **Sections**: docs/TOOLS.md
- **Model**: sonnet

## Goal

Everything the developer tunes by editing constants and restarting becomes a switch or slider on the DEVTOOLS page (and in the arena), changed live and remembered for the session.

## Candidates (analysis, 2026-11-19; the human picks what goes into the first version)

**A. Arena and effect tuning** (live in the arena panel)
- Barrage: elevation min / max / full-distance, shell count, interval, flight base and per-distance, tracer size, landing disc radius (now constants in `VolleyPlayback` / `SalvoTiming` / `RocketVolley`; they would move to one `DevTunables` store read at use).
- MLRS salvo: interval, flight, apex, rocket count; impact effect amounts (`SalvoFxPool` consts), muzzle flash size, camera shake.
- "Fire" buttons: select shooter and target and replay the same attack without ending the turn; repeat the last attack; slow motion (tween speed scale) for effects.
- Terrain brush (plains / forest / hills / water / urban) to test line of sight, cover and hit marks; map size.
- Unit editor: HP, moves, dug-in / ambush flags of the selected unit.

**B. Look and performance switches** (all exist as statics or env variables today)
- Graphics quality LOW / HIGH override (now `--quality=`), `VisualScale` preset (current / true size), `LookPreset` (4 looks), grid on / off, FPS and frame-time overlay (what `tools/perf.sh` measures), unlock the camera's min / max distance.

**C. Battle bench**
- Scenario + seed picker (all `Scenario.NAMES`, `contact_battle`), start with a chosen faction pair.
- Watch AI vs AI (speed x1/x4/skip), pause / step one event, god mode (no counters, refill every turn), fog / line-of-sight off (reveal all), force end turn / force win, command points and fire support refill, damage forecast dump.
- Replay: load a saved `MatchRecord` and step through it (the replay fixture tool already exists).

**D. Operational bench**
- Open the staff map as NATO or Russia; buttons for the keys that need `--debug` today (F9 politics / contact panels, F10 quick contact), jump to a formation, skip turns, give supply / fuel, reveal recon, trigger a strike.

**E. Tools launched from the page**
- Unit catalog (already on the menu), screenshot of the current scene to `.screenshots/`, copy the current seed / scenario / camera as a `SCREENSHOT_*` command line so the agent can reproduce a view.

Suggested first version: A (barrage and salvo sliders + Fire / slow motion + terrain brush) and B (quality, scale, look, FPS overlay); C and D as separate tasks.

## Acceptance criteria (testable)

- [ ] To be written after the human picks the first version (use `/refine-task TASK-186`).

## Playtest (for the human)

To be written with the criteria.

## Player manual

none (developer tool).

## Out of scope

- Anything that changes game rules or balance data (that stays in resources and the GDD).

## Implementation notes

_Filled in by the agent when done._
