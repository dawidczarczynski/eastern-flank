# TASK-184: Barrel-artillery barrage and the dev arena

- **Status**: done
- **Layers**: presentation (+ balance data)
- **Depends on**: –
- **Sections**: GDD "Stat derivation rules" (gun artillery attack)
- **Model**: sonnet

## Goal

Self-propelled howitzers (K9, 2S19) fire like artillery: the barrel lifts with the distance, a barrage of three fast shells lands with MLRS-style fire and smoke; a dev arena lets the human try it (and any unit) without playing a battle.

## Acceptance criteria (testable)

- [x] The gun elevation rises with the distance (15° … 65° by 8 tiles), limited by the model (`VolleyPlayback.barrage_elevation`).
- [x] Three shells (tracer flame only, 0.5 s apart, 0.6–1.0 s flight) land one after another; the gun recoils and flashes per shot; the target's HP steps down per impact; impacts use the MLRS effects (`SalvoFxPool.barrage_effects`).
- [x] Gun-artillery attack 5 → 6 (GDD rule, data, manual, tests): a howitzer deals 2 to a tank, 3 to infantry on plains.
- [x] Dev arena (`tools/run.sh --scene=arena`, devtools "Arena"): empty flat map, place / remove units of both sides, refill, hot seat, no AI, never ends; screenshot hook `SCREENSHOT_SCENE=arena`.

## Playtest (for the human)

Done by the human on 2026-11-19 ("now it's good").

## Player manual

Howitzer stats and barrage description (done).

## Out of scope

- A shell as its own attack roll (damage stays one strike with per-HP rolls; the shells only show its result).

## Implementation notes

Presentation only: `RocketVolley` got a `shells` mode (flame only, recoil and muzzle flash per shot), `VolleyPlayback.append_barrage`, `EventQueue.FX_BARRAGE`, `BattleController._play_barrage`. `ArenaController` extends `BattleController` (scenes/battle/arena.tscn); units are added and removed by editing the state directly (bench only, not recorded). The gun-artillery attack rule was raised after the human found the damage too low (asked before changing the approved rule).
