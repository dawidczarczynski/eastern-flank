# Night run report

Run 2026-11-11 21:19 - 23:03 (logs and patches of failed tasks: `/home/dawid/night_runs/20261111_2119`).

| Task | Result | Status | Note |
|---|---|---|---|
| TASK-102a | failed | in progress | session ended with status 'in progress': The implementation agent is still running, so I have no results to report yet. |
| TASK-099a | failed | in progress | session ended with status 'in progress': The gameplay-engineer agent is still working on TASK-099a, and I'm waiting for its completion notice. I haven't seen any of its results yet. |
| TASK-101 | ok | to playtest |  |
| TASK-119a | ok | done |  |
| TASK-121 | failed | in progress | session ended with status 'in progress': I'm waiting for the core-logic agent to finish. Its completion will wake me, so I'm not polling. |
| TASK-081a | ok | done |  |
| TASK-128 | ok | done |  |

## To playtest

### TASK-101: Deep strike forecast – expected hits and damage of a planned salvo in the confirm card

1. Operation (`--debug`, F9 to Open war): S -> `jassm_er` -> click a Russian airfield in Kaliningrad: the card shows the interception row, "Expected hits ... of N - at least one hit ...%" and "Expected integrity 100 -> X, destroyed ~Y%".
2. Change the salvo with the salvo control: the numbers update at once; a larger salvo raises expected hits and destroyed %.
3. Pick a formation target: the card shows "Expected loss ~N strength".
4. Strike an air-defence site first (SEAD), then the airfield: the interception row drops to "Air defence suppressed" and the expected hits rise.
5. Pick a weapon whose stock is lower than the salvo: the card shows the capped count; a target out of range shows no forecast rows.
6. Confirm a few strikes: the real results scatter around the forecast (it is an average, not a promise).
7. `--side=russia`: the same against Polish targets.

