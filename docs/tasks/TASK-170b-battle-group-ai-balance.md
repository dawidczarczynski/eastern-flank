# TASK-170b: Battalion battle groups – tactical AI for artillery, balance and performance

- **Status**: done (playtested 2026-11-17)
- **Layers**: ai
- **Depends on**: TASK-170a
- **Sections**: GDD "Balance of the default battle", GDD "Battle hand-off and auto-resolve", GDD "Formations"
- **Model**: opus (AI behaviour across the new role plus an iterative balance loop; a wrong tune silently skews both layers)
- **Topic**: Two-layer game

## Goal

The tactical AI plays the new 7-company battalions sensibly (artillery stays back and shells from range) and mirrored/default battles stay fair and smooth. Part 2 of TASK-170.

## Decisions (2026-11-17, human)

- Balance target 40–60 % win rate on mirrored / default setups; 7 v 7 must hold 60 FPS with an acceptable AI turn time. Numbers go to `data/**/*.tres`, not code.

## Acceptance criteria (testable)

- [ ] The AI never moves an `mlrs` company closer to the nearest enemy than its own `min_range_m` allows firing, and never ends its move nearer the enemy than the nearest own non-artillery company when it has a free tile farther back.
- [ ] An AI `mlrs` company with an enemy in range fires instead of moving when it can; if none is in range, it advances only to the first tile that puts an enemy in range, staying ≥ 2 hexes behind the front-most own direct-fire company.
- [ ] Direct-fire companies still head for the objective (existing objective tests green); no AI command is rejected in a 7 v 7 AI-vs-AI game over 20 seeds (zero rejected commands).
- [ ] `tools/simulate.sh 200` on the mirrored Poland v Poland and Russia v Russia setups: each seat wins 40–60 % of decided games.
- [ ] `tools/simulate.sh 200` on the default Poland v Russia contact setup (both attacker roles): each side wins 40–60 %; if not, tune `data/units/*.tres` or `data/formations/*.tres` only, and record the final numbers in the Implementation notes.
- [ ] AI turn time of a 7 v 7 battle (all 14 companies) stays at or under the pre-170 4 v 4 AI turn time × 2.5 on `tools/simulate.sh` timing output; no game exceeds 60 turns.
- [ ] Operation-level balance re-measured (`--mode=operation`, seeds 1..200): each side holds 40–60 % of decided operations with the new order of battle; update the numbers in GDD "Operational AI".
- [ ] A 7 v 7 battle scene renders at 60 FPS (HIGH) – measured and noted (see playtest).

## Playtest (for the human)

1. Play a contact battle as attacker and as defender: your rocket-artillery company is placed behind your line; the enemy's stays back and fires at your units in range.
2. Watch 3 AI turns: no artillery rushes the front; no long freeze while the AI thinks.
3. Check the frame rate during a full 7 v 7 fight (FPS counter in the debug overlay stays at 60).

## Player manual

docs/MANUAL.md (game-designer): add a short note that rocket artillery is used from behind the front and the enemy AI does the same; update any win-rate or difficulty wording if numbers changed in `data/`.

## Out of scope

- v2: air defence, helicopters; new unit models; a dedicated anti-tank unit; ammunition and morale.
- Changing the deployment rules or the order of battle (TASK-170a).

## Implementation notes

2026-11-17 (gameplay-engineer):

- **AI** (`src/ai/ai_player.gd`): rocket artillery (indirect fire) ignores objectives and plays from behind the line (`_artillery_destination`, `ARTILLERY_STANDOFF` = 2): an enemy in range → fires from where it stands (moves first only to a reachable firing tile out of every enemy's reach when an enemy can fire back where it stands – keeps TASK-131a's behaviour); otherwise the nearest reachable tile that puts an enemy in range, never inside `min_range_m`, ≥ 2 hexes farther from the enemy than the front-most own direct-fire company; with none it closes up to that line or falls back to it. A side that only defends (HOLD_HEXES, no TAKE_HEXES = the contact defender) waits: a company with no reachable firing tile closes on its objective instead of marching out (without this the attacker won 69–74 % of the mirrors). Line of sight is cached per grid in the AI (turn time).
- **Harness**: `Scenario.SIMULATION_NAMES` = `contact_battle` (not in the menu): player 0's faction battalion attacks player 1's at Suwałki (operational hexes (16, 34) → (17, 34)), deployed by `ContactMap`. `MatchRunner` reports `rejected` and AI turn timing (`TIMING_KEYS`); `tools/simulate.sh` prints rejected commands, longest game, average / slowest AI turn.
- **Tests**: `test_ai_artillery.gd` (7), `test_ai_holding.gd` (3), `test_match_runner.gd` (+3: 7 v 7 scenario, 20 seeds zero rejected commands and ≤ 60 turns, timing).
- **Balance (seeds 1..200, data unchanged)** – numbers in GDD "Balance of the default battle" / "Operational AI":
  - Mirrors (`contact_battle`): poland,poland attacker 51.5 %, russia,russia attacker 55.0 % – **in band**.
  - Default contact Poland v Russia: poland,russia 164 / 36, russia,poland 25 / 175 → Poland **84.8 %** – **outside the band**.
  - Operation (`--mode=operation`): NATO 80 / Russia 120 → **40.0 % / 60.0 %** – on the edge of the band.
  - Default battle (re-checked): Poland 51.1 %, unchanged.
- **Why the contact criterion is not met (blocker for the human)**: the per-battalion quality gap (2 × Abrams v 2 × T-72B3) is the design ("quality vs. mass"), offset in the operation by 8 Russian v 6 Polish formations. Every units-only tuning that brought the 7 v 7 into the band broke the operation and the default battle: e.g. T-72B3 9 HP / attack 7 / max 3 500 m + Motor Rifle Squad attack 5 → contact Poland 48.5 % (mirrors 51.5 / 56 %), but operation NATO **10.5 %** and default battle Poland **25 %**; a third T-72B3 instead of a squad → contact Russia 56 % but russia,russia attacker 72 %. Tactical-only knobs (tank ranges, move points) moved the contact by < 10 points. Data left unchanged; decision needed: even battalion duels (then fewer Russian formations in `data/operations/`, outside this task's allowed files) or Poland-favoured duels by design (then drop the criterion).
- **2026-11-17, human chose option (a)** – even battalion duels, order of battle in `data/operations/` may change (unit stats kept):
  - `data/formations/ru_motor_rifle_battalion.tres`: 3 × Motor Rifle Squad, **3 × T-72B3**, Uragan (was 4 squads + 2 T-72B3; strength 62 → 60, still 7 companies).
  - `data/operations/suwalki_gap.tres`: the 6th Motor Rifle Battalion (`ru_mr_6`) removed – Russia 7 formations / 416 (was 8 / 488); Belarus contribution 178, North Korea 120 (same types).
  - Contact Poland v Russia (200 seeds): poland,russia 100 / 100, russia,poland 96 / 104 → Poland **51.0 %** – in band. Mirrors: poland,poland 51.5 % (unchanged), russia,russia attacker **71.5 %** (143 / 57) – **outside the band**.
  - Operation: 8 Russian formations with the new battalion NATO 27.0 %; shipped (7) **NATO 119 / Russia 81 = 59.5 %** (seeds 1..200 as 4 × 50, 0 draws, 0 errors) – in band, at its edge. Tried and rejected: ru_mr_5 as a tank battalion 58.5 %; 8 Russian formations minus one Belarusian battalion 67.0 %; Polish 2nd Tank Battalion as mechanised 63.5 %.
  - Default battle: identical (Poland 51.1 %, mirrors 75.5 / 80.0 %) – it does not use formations.
  - Contact orders of battle tried (6 attempts, 100 seeds unless noted, Poland's share): Russia + 5th squad (8 companies) 86.3 % (200); Russia + 2nd Uragan (8) 80.5 %, Russian mirror 68 %; Poland 1 Abrams + 5 squads 33 %; Russia 3 T-72B3 + 3 squads (shipped) 55 % / 51.0 % (200); Russia 4 squads + 3 T-72B3 without Uragan 62 %, mirror 64 %; old ORBAT + T-72B3 9 HP / attack 7 46 %, mirror 77 %.
  - **Open – Russian mirror**: every Russian battalion with more or stronger tanks gives the Russian mirror's attacker 64–77 %; the order of battle cannot fix both the duel and that mirror. Needs an AI/deployment change (e.g. the waiting defender's tanks taking firing positions) – stopped per the fix-loop limit.
  - Tests updated: `test_operational_data.gd` (MR battalion companies / 60, counts [6, 7], strength [396, 416]), `test_operation.gd` (13 formations, totals), `test_contribution_data.gd` (Belarus 178).
- **AI turn time** (serial, `tools/simulate.sh 40 --scenario=contact_battle`): pre-170 4 v 4 baseline (formations of commit 8229146^, old AI): 30.2 / 33.4 ms average, 62.8 / 91.8 ms slowest (poland,russia / russia,poland). 7 v 7 now: 43.7 / 50.1 ms average (×1.45 / ×1.50), 148.8 / 134.8 ms slowest (×2.37 / ×1.47) – within ×2.5. Longest contact game 12 turns (turn limit); default battle has harness-limit games (50) as before TASK-170b.
- **60 FPS (HIGH) render of a 7 v 7 battle**: not measurable headless – left for the playtest.
- **Human decision (2026-11-17)**: the Russia v Russia mirror (attacker 71.5 %) is not a real scenario – accepted outside the band. The earlier "blocker" paragraph above is superseded by option (a). 60 FPS on a 7 v 7 battle is a playtest item.
