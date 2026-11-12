# Night run report

Run 2026-11-11 21:19 - 01:14 (logs and patches of failed tasks: `/home/dawid/night_runs/20261111_2119`).

| Task | Result | Status | Note |
|---|---|---|---|
| TASK-102a | failed | in progress | session ended with status 'in progress': The implementation agent is still running, so I have no results to report yet. |
| TASK-099a | failed | in progress | session ended with status 'in progress': The gameplay-engineer agent is still working on TASK-099a, and I'm waiting for its completion notice. I haven't seen any of its results yet. |
| TASK-101 | ok | to playtest |  |
| TASK-119a | ok | done |  |
| TASK-121 | failed | in progress | session ended with status 'in progress': I'm waiting for the core-logic agent to finish. Its completion will wake me, so I'm not polling. |
| TASK-081a | ok | done |  |
| TASK-128 | ok | done |  |
| TASK-131b | ok | to playtest |  |
| TASK-146 | failed | ready | session ended with status 'ready': TASK-146 is blocked, so I wrote no code. The status stays `ready`, and the blocker is in the task's "Implementation notes".  The mockup check failed. `docs/design/operational_map/strike_panel.html` has no  |
| TASK-108h | ok | to playtest |  |
| TASK-108c | failed | in progress | session ended with status 'in progress': Implementation is running in the background; I'll wait for its completion notification. |
| TASK-108d | failed | in progress | session ended with status 'in progress': The implementation agent is running in the background. I'm waiting for its completion notification before verifying. |
| TASK-063 | failed | in progress | session ended with status 'in progress': The implementation agent is still running. I'll verify its work when it reports back. |
| TASK-108g | failed | in progress | session ended with status 'in progress': The first agent (importer and `LandCover`) is still running. I'm waiting for it to finish before starting the presentation half, which needs its API. |
| TASK-111 | failed | in progress | session ended with status 'in progress': The implementation agent is still running; I'll wait for its completion notification before verifying. |
| TASK-134 | failed | in progress | session ended with status 'in progress': The implementation agent is running; I'll wait for it to finish. |
| TASK-135 | failed | in progress | session ended with status 'in progress': I've delegated TASK-135 to an opus presentation agent, and it is still running. I'll verify its work with `tools/check.sh` once it reports back. |

## To playtest

### TASK-101: Deep strike forecast – expected hits and damage of a planned salvo in the confirm card

1. Operation (`--debug`, F9 to Open war): S -> `jassm_er` -> click a Russian airfield in Kaliningrad: the card shows the interception row, "Expected hits ... of N - at least one hit ...%" and "Expected integrity 100 -> X, destroyed ~Y%".
2. Change the salvo with the salvo control: the numbers update at once; a larger salvo raises expected hits and destroyed %.
3. Pick a formation target: the card shows "Expected loss ~N strength".
4. Strike an air-defence site first (SEAD), then the airfield: the interception row drops to "Air defence suppressed" and the expected hits rise.
5. Pick a weapon whose stock is lower than the salvo: the card shows the capped count; a target out of range shows no forecast rows.
6. Confirm a few strikes: the real results scatter around the forecast (it is an average, not a promise).
7. `--side=russia`: the same against Polish targets.

### TASK-131b: Weapon range in the battle UI – range overlay, LoS marks, forecast distance, manual

1. Start the default battle, select a T-72B3: an outline appears out to 8 hexes, a paler band to 12 hexes; forest and hill hexes behind blockers are dimmed.
2. Select Homar-K: the whole map is outlined except a small hole of 2 hexes around the unit.
3. Hover an enemy at 10 hexes with the tank selected: tag shows `DIST` and `-25 %`.
4. Hover an enemy hidden behind a forest: no crosshair; RMB says no line of sight.
5. Open the unit card and the catalog: ranges in km / m shown, same as the manual.
6. Watch the frame rate with Homar-K selected (60 FPS).

### TASK-108h: Real-terrain look v2 – `soil` ground layer and URBAN farmyards

1. `tools/run.sh --scenario=suwalki_battle`: villages read as farmyards (gravel + bare soil + grass). 2. Default battle unchanged. 3. `--quality=low` still shows it.

