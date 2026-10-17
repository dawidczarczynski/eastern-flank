# TASK-008: Sequential event animation playback

- **Status**: to playtest
- **Layers**: presentation (pure queue class tested in `tests/unit/`)
- **Depends on**: TASK-001 (events `unit_attacked`, `unit_died`, `game_over`). Not required by later tasks, but makes TASK-009/-004/-003/-010 visuals easier to read.
- **Model**: opus

## Goal

AI turns become readable: instead of every AI unit moving and attacking in the same frame, the view plays events one after another (move → hit → death), quickly enough that long turns don't drag. The simulation stays synchronous – only the view lags behind.

## Acceptance criteria (testable)

- [x] New pure class `EventQueue` (`src/presentation/event_queue.gd`, `extends RefCounted`, no nodes/tweens) with:
  - `push(event: Dictionary) -> void`, `pop() -> Dictionary` (FIFO; `{}` when empty), `is_empty() -> bool`, `size() -> int`;
  - `static func base_duration(event: Dictionary) -> float` – `unit_moved` **0.25**, `unit_attacked` **0.25**, `unit_died` **0.4**, every other type (`turn_started`, `turn_ended`, `game_over`, unknown) **0.0**;
  - `pending_duration() -> float` – sum of `base_duration` of all queued events;
  - `begin_burst() -> float` – returns the playback speed for the burst that is about to play: `max(1.0, pending_duration() / MAX_BURST_SECONDS)` with `MAX_BURST_SECONDS = 3.0`; the speed stays fixed until the queue is empty again (so a burst never takes noticeably longer than 3 s).
- [x] Tests `tests/unit/test_event_queue.gd`:
  - FIFO: push `unit_moved`, `unit_attacked`, `unit_died` → `pop()` returns them in that order, then `{}`.
  - `pending_duration()` for `[unit_moved, unit_attacked, unit_died, turn_started]` == **0.9** (compare with tolerance 0.0001).
  - 12 × `unit_moved` (3.0 s) → `begin_burst() == 1.0`; 24 × `unit_moved` (6.0 s) → `2.0`; empty queue → `1.0`.
  - Only `turn_ended` + `turn_started` → `pending_duration() == 0.0`, speed `1.0`.
- [x] `BattleController._on_event` only pushes events into the queue. Playback starts **deferred** (next frame), so a whole synchronous AI turn (all `AiPlayer.take_turn` calls in `_end_human_turn`) is queued before the burst starts and its speed is computed.
- [x] Events play strictly one at a time in emission order: the next event starts only when the previous one's animation has finished (move tween, hit tween, death shrink). All tweens of a burst are scaled by the burst speed (e.g. `Tween.set_speed_scale`).
- [x] Event handlers use only event fields (`to`, `target_hp`, `unit_id`, …) plus immutable definition data (`max_hp`) – never the current `Unit.coord` / `Unit.hp` from `GameState`, which may already be ahead of the animation.
- [x] The `delay` workaround from TASK-001 is removed: `UnitView.play_hit` no longer takes a delay and `remaining_move_time()` is deleted (sequencing makes them unnecessary).
- [x] While the queue is non-empty or an event is playing: left clicks and Enter are ignored (not buffered); camera controls keep working.
- [x] Movement highlights, selection and the status label are refreshed when the queue drains; the "Victory!"/"Defeat!" text appears only after the last animation of the burst.
- [x] Headless smoke run (scene driven by script until `game_over`) still finishes without script errors.

## Playtest (for the human)

1. Move a unit – it animates as before (no noticeable delay for a single action).
2. Press Enter – AI units move **one after another**; an AI attack shows the attacker arriving first, then the target flashing and its HP label changing.
3. When a unit dies: the hit plays, then the unit shrinks and disappears, then the next AI unit moves.
4. A long AI turn (many units) finishes in about 3 seconds – animations speed up instead of dragging.
5. Clicking tiles or pressing Enter during AI playback does nothing; WASD/QE/wheel still move the camera.
6. After the AI finishes, it is your turn and clicks work again; "Victory!"/"Defeat!" shows only after the final death animation.

## Out of scope

- Moving along the actual path (needs a `path` field in `unit_moved`; see TASK-004 follow-up).
- Camera following the acting unit, a "skip animations" key, user-configurable speed.
- Floating damage numbers.

## Implementation notes

- `EventQueue` (`src/presentation/event_queue.gd`): pure FIFO with duration constants (`MOVE_DURATION`, `ATTACK_DURATION`, `DEATH_DURATION`) and `begin_burst()`; it stores nothing – `BattleController` keeps `_burst_speed` until the queue drains. 6 tests in `tests/unit/test_event_queue.gd`.
- `BattleController`: `_on_event` only pushes; `_start_burst` is `call_deferred` (guarded by `_playback_scheduled`/`_playing`), so a whole AI turn is queued before the speed is computed. `_play_next_event` loops over instant events (turn/game_over, or events for a missing view) and stops at the first one that returns a Tween; it sets `set_speed_scale(_burst_speed)` and chains on `finished` (one-shot) – signal callbacks, no `await`.
- Handlers use event fields only; `UnitView` stores `_max_hp` from the definition (`play_hit(hp)`, `set_hp(hp)` lost the `max_hp` arg). `move_to`/`play_hit`/`play_death` return their Tween (null if nothing animates). `UnitView` durations come from the `EventQueue` constants (death = 0.1 s darken + 0.3 s shrink), so the speed estimate matches the real tweens.
- Removed: `remaining_move_time()`, `_hit_delay`, the `delay` param; hit and death no longer overlap.
- Input: `_is_playing_events()` drops left clicks / Enter and hides the path preview; camera (`CameraRig`) unaffected. During a burst the status label shows the turn from `turn_started` event data; `_on_queue_drained` deselects dead units, refreshes highlights/selection/info panel and shows Victory/Defeat.
- Smoke run: a scratch script drove the scene headless (`Engine.time_scale = 10`) to `game_over` (turn 13), 0 script errors, view positions/HP matched state after every drain. Not added to the repo (`tests/integration/` is still empty) – a candidate follow-up.
- Known limitations: highlights are hidden for the ~0.25 s of the player's own move (refresh happens on drain); the info panel updates only on drain.
