# TASK-186a: Devtools: live effect tunables, Fire again and slow motion (arena)

- **Status**: ready
- **Layers**: presentation (+ a small `DevTunables` store)
- **Depends on**: TASK-185
- **Sections**: docs/TOOLS.md
- **Model**: sonnet

## Goal

The developer tunes barrage and rocket-salvo effects with sliders in the arena panel (live, remembered for the session) and replays an attack in slow motion, instead of editing constants and restarting. Split from TASK-186; switches and the unit editor are TASK-186b. No GDD change (developer tool, no rules or balance data touched).

## Acceptance criteria (testable)

- [ ] `DevTunables` (static store, `src/presentation/`, no disk saving, resets on restart) holds the keys below; `get_value(key)` returns the override or the default; `set_value`, `reset(key)`, `reset_all()`.
- [ ] Defaults equal today's constants (one test per group reads the old constant and the default): barrage elevation min 15.0 / max 65.0 / full distance 8.0 (`VolleyPlayback`); barrage shell count 3, interval 0.5, flight base 0.4, flight per distance 0.04 (`SalvoTiming`); tracer size 0.04 (`RocketVolley.SHELL_GLOW_SIZE`); landing disc radius 0.45; MLRS salvo count (profile, default 6), interval (0.35), flight base 1.0, apex base 0.7 (`RocketVolley`); impact amounts fireball 8, smoke 5, debris 7, dust ring 8 (`SalvoFxPool`); muzzle flash size 0.16; camera shake (existing value, if the code has one; otherwise leave it out and say so in the notes).
- [ ] `VolleyPlayback`, `SalvoTiming`, `RocketVolley`, `SalvoFxPool` read the store at use (no cached copy), so a slider change affects the next attack. Test: setting shell count 5 gives 5 barrage shells; elevation min 30 gives 30° at distance 0.
- [ ] Overrides apply only while `DevTunables.active` is true; the arena sets it on enter and clears it on leave. Test: with `active = false` a set override is ignored (normal battle and unit catalog unchanged).
- [ ] Each slider has min / max clamping (store clamps: counts 1..12, intervals 0.05..2.0, flights 0.2..4.0, elevations 0..85, sizes 0.01..1.0, radius 0..2.0, impact amounts 0..30). Test: `set_value` outside the range is clamped.
- [ ] Arena panel gets a collapsible "Effects" section: one labelled slider with a value readout per key, a per-value reset button, and a "Reset all" button; same look as the existing panel (plain Godot controls).
- [ ] "Fire again" button repeats the last attack: same shooter and target, same attack visuals, game rules unchanged (all state changes through normal commands and `GameSimulation.execute()`). Implementation choice is recorded in the notes; if a fresh attack is needed, attacks are refilled with the existing refill tool path (state edit, bench only). Disabled with no previous attack or if either unit is gone; no crash when the target died (shows nothing, button greys out).
- [ ] Slow-motion slider 0.1..1.0 (default 1.0, step 0.05) scales effect playback via `Engine.time_scale` or tween speed scale (whichever the code supports cleanly); it is restored to 1.0 when leaving the arena. Test: leaving the arena resets the scale to 1.0.

## Playtest (for the human)

1. `tools/run_windows.sh --debug`, DEVTOOLS, ARENA; place a K9 and a tank 6 tiles apart; attack once.
2. Open Effects: set shell count to 6, interval 0.3, elevation min 40; Fire again: 6 faster shells with a steeper barrel.
3. Reset one value, then Reset all: the barrage looks like the original again.
4. Slow motion 0.2: Fire again shows the impacts in slow motion; Leave the arena: a normal battle plays at normal speed.
5. Place an MLRS and change rocket count and apex; Fire again.

## Player manual

none (developer tool).

## Out of scope

- Look / performance switches, FPS overlay, unit editor: TASK-186b.
- Saving tunables to disk; changing game rules or balance data.

## Implementation notes

_Filled in by the agent when done._
