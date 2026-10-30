# TASK-089a: Company combat with per-element rolls – core, forecast API, AI, simulation

- **Status**: done
- **Layers**: core (gameplay-engineer), AI; HUD forecast is [TASK-089b](TASK-089b-combat-forecast-hud.md)
- **Depends on**: – (soft: TASK-088). Step 1 approved by the human 2026-10-30.
- **Model**: opus (balance, determinism, AI expected values)

## Goal

Combat feels like companies fighting – mostly predictable, never certain – and a battered company fights worse (GDD "Vision decisions": units are companies, HP = strength).

## Step 1 – game-designer (no code)

Propose and get approved: each strength point (HP) of the attacker rolls once through `GameState.rng` with a hit chance `p` derived from attack vs. defence + terrain, so that a **full-strength** company deals on average what today's formula deals (`max(1, attack − defence − bonus)`); a minimum damage rule or not; counters use the same roll; what the forecast shows (expected value + 10–90 % range); the effect on the AI (expected damage); simulation check over both side assignments (the 59/34 side bias question). Numbers into GDD "Combat", MANUAL update listed.

## Step 1 – proposal (game-designer, 2026-10-30; approved by the human 2026-10-30)

Mirrored in docs/GDD.md "Combat" → "Per-element rolls".

### 1. The roll

For one strike of `striker` on `victim`:

- `base = max(1, striker.attack − (victim.defense + defense bonus of the victim's tile))` – today's damage, unchanged; the striker's tile still doesn't matter.
- `die = striker.max_hp` (the company's full strength).
- `hit_on = min(base, die)`.
- `shots = striker.hp` at the moment of the strike (its current strength).
- Each shot rolls `rng.randi_range(1, die)` on `GameState.rng`; a roll `<= hit_on` is a hit. **Damage = number of hits** (0 … shots); the victim loses `min(damage, victim.hp)`.

So `p = hit_on / die = clamp(base / max_hp, 1 / max_hp, 1)`. Expected damage = `shots × p = (hp / max_hp) × base`: **a company at x % strength deals on average x % of today's damage**, and a full-strength company deals exactly today's damage on average.

Why a die instead of a float threshold: integer only (no float comparison in the rules, cross-platform safe in replays), exact calibration, and it is explainable to the player ("each strength point rolls a die with as many faces as the unit's full strength; it hits on the attack margin or less"). No extra clamp: `p` is at least `1 / max_hp` (the old minimum of 1) and reaches 1 only when `base >= max_hp`, which no current matchup does (highest: MLRS vs MLRS on plains, 5/6). **No new balance data** – the formula reuses `attack`, `defense`, `max_hp` and the terrain `defense_bonus`.

### 2. Minimum damage – none

A strike may deal 0. Reasons: (a) a "at least 1" floor breaks the calibration for battered companies (a 1-HP infantry remnant against a tank would deal 1 instead of 0.1 on average) and so cancels "a battered company fights worse"; (b) "never certain" needs a real miss; (c) the old minimum survives as the mean – infantry still deals 1.0 to a tank on average at full strength. Cost: infantry vs. a tank misses completely 35 % of the time (0.9^10) instead of always chipping 1 – visible, so the forecast must show it.

### 3. Counterattack – same roll, with what is left

The counter is a normal strike with the same rule: `shots = defender's HP after the hit` (its lost strength doesn't fire back), `die` = the defender's `max_hp`, `hit_on` against the original attacker's defence + the attacker's tile bonus. All other counter rules stay (range check, no counter when the defender died or the battle ended, no counter to a counter). Consequence: attacking first is worth more than today (the defender is weakened before it answers), e.g. Abrams → T-72B3 on plains: counter 1.25 on average instead of 2. This is the main balance risk – see section 7.

### 4. Worked table (full strength, defender on plains / forest / hills)

Mean = today's damage. Range = 10–90 % range (smallest k with P(X ≤ k) ≥ 0.10 … smallest k with P(X ≤ k) ≥ 0.90), not capped by the target's HP. SD = standard deviation. P0 = chance of 0 damage.

| Attacker (die) → defender | Tile | today | hit_on / die (p) | mean | range | SD | P0 |
|---|---|---|---|---|---|---|---|
| Infantry (d10) → Infantry (D3) | plains / forest / hills | 1 / 1 / 1 | 1/10 (0.10) | 1.0 | 0–2 | 0.95 | 35 % |
| Infantry (d10) → Tank (D4) | all | 1 | 1/10 (0.10) | 1.0 | 0–2 | 0.95 | 35 % |
| Infantry (d10) → MLRS (D1) | plains | 3 | 3/10 (0.30) | 3.0 | 1–5 | 1.45 | 3 % |
| | forest | 2 | 2/10 (0.20) | 2.0 | 0–4 | 1.26 | 11 % |
| | hills | 1 | 1/10 (0.10) | 1.0 | 0–2 | 0.95 | 35 % |
| Abrams (d10) → Infantry | plains | 4 | 4/10 (0.40) | 4.0 | 2–6 | 1.55 | 0.6 % |
| | forest | 3 | 3/10 | 3.0 | 1–5 | 1.45 | 3 % |
| | hills | 2 | 2/10 | 2.0 | 0–4 | 1.26 | 11 % |
| Abrams (d10) → Tank | plains | 3 | 3/10 | 3.0 | 1–5 | 1.45 | 3 % |
| | forest | 2 | 2/10 | 2.0 | 0–4 | 1.26 | 11 % |
| | hills | 1 | 1/10 | 1.0 | 0–2 | 0.95 | 35 % |
| Abrams (d10) → MLRS | plains | 6 (kills) | 6/10 (0.60) | 6.0 (5.40 after the 6-HP cap) | 4–8 | 1.55 | 0 % |
| | forest | 5 | 5/10 (0.50) | 5.0 | 3–7 | 1.58 | 0.1 % |
| | hills | 4 | 4/10 | 4.0 | 2–6 | 1.55 | 0.6 % |
| T-72B3 (d8) → Infantry | plains | 3 | 3/8 (0.375) | 3.0 | 1–5 | 1.37 | 2 % |
| | forest | 2 | 2/8 (0.25) | 2.0 | 0–4 | 1.22 | 10 % |
| | hills | 1 | 1/8 (0.125) | 1.0 | 0–2 | 0.94 | 34 % |
| T-72B3 (d8) → Tank | plains | 2 | 2/8 | 2.0 | 0–4 | 1.22 | 10 % |
| | forest / hills | 1 | 1/8 | 1.0 | 0–2 | 0.94 | 34 % |
| T-72B3 (d8) → MLRS | plains | 5 | 5/8 (0.625) | 5.0 | 3–7 | 1.37 | 0 % |
| | forest | 4 | 4/8 (0.50) | 4.0 | 2–6 | 1.41 | 0.4 % |
| | hills | 3 | 3/8 | 3.0 | 1–5 | 1.37 | 2 % |
| Homar-K / Uragan (d6) → Infantry | plains | 3 | 3/6 (0.50) | 3.0 | 1–5 | 1.22 | 1.6 % |
| | forest | 2 | 2/6 (0.33) | 2.0 | 1–4 | 1.15 | 9 % |
| | hills | 1 | 1/6 (0.17) | 1.0 | 0–2 | 0.91 | 33 % |
| Homar-K / Uragan (d6) → Tank | plains | 2 | 2/6 | 2.0 | 1–4 | 1.15 | 9 % |
| | forest / hills | 1 | 1/6 | 1.0 | 0–2 | 0.91 | 33 % |
| Homar-K / Uragan (d6) → MLRS | plains | 5 | 5/6 (0.83) | 5.0 | 4–6 | 0.91 | 0 % |
| | forest | 4 | 4/6 (0.67) | 4.0 | 2–5 | 1.15 | 0.1 % |
| | hills | 3 | 3/6 | 3.0 | 1–5 | 1.22 | 1.6 % |

Kills and counters that change most:

| Situation | today | proposed |
|---|---|---|
| Abrams (10 HP) → full MLRS (6 HP) on plains | always destroyed, no counter | destroyed 63.3 %; expected loss 5.40; expected counter 0.20 |
| Homar-K → full Uragan on plains from 6 hexes | 5 damage, 6 → 1 HP | expected 5.0, range 4–6, destroyed 33.5 % ((5/6)^6) |
| Abrams → full T-72B3 on plains | 3, counter 2 | expected 3.0 (range 1–5), counter expected 1.25 |
| Infantry → full Abrams on plains | 1, counter 4 | expected 1.0 (range 0–2, 35 % nothing), counter expected 3.6 (0.4 × 9) |
| Abrams → full squad in forest (MANUAL example) | 3, counter 1 | expected 3.0, counter expected 0.7 (0.1 × 7) |

Battered companies (examples of `hp / max_hp × base`): Abrams at 5/10 → T-72B3 on plains 1.5 (today 3); T-72B3 at 4/8 → squad on plains 1.5 (today 3); squad at 3/10 → Abrams 0.3 (today 1); Uragan at 2/6 → Homar-K on plains 1.67 (today 5).

### 5. Forecast (pure, no rng)

API in `src/core/` (pure logic, `RefCounted`), used by the HUD and the AI:

```
## In AttackCommand (or a CombatForecast helper next to it):
static func hit_on(state: GameState, striker: Unit, victim: Unit) -> int   # min(base, striker.max_hp)
static func forecast(state: GameState, attacker: Unit, defender: Unit) -> CombatForecast

class_name CombatForecast extends RefCounted
var shots: int                 # attacker strength rolling
var hit_on: int                # a roll <= hit_on hits
var die: int                   # attacker max_hp
var expected_damage: float     # E[min(hits, defender.hp)]
var damage_low: int            # 10th percentile of min(hits, defender.hp)
var damage_high: int           # 90th percentile of min(hits, defender.hp)
var kill_chance: float         # P(hits >= defender.hp)
var counter_possible: bool     # defender has the attacker in range (ignores a battle end by objectives)
var counter_expected: float    # E[min(counter hits, attacker.hp)] over every outcome of the first strike
var counter_low: int           # 10th / 90th percentile of the counter mixture (0 when no counter)
var counter_high: int
var attacker_loss_chance: float  # P(the counter destroys the attacker)
```

Computed exactly from the binomial distribution (`shots ≤ max_hp ≤ 10`, at most 11 × 11 terms for the counter mixture `Σ_k P(hits = k) × Binomial(defender.hp − k, p_counter)`); percentiles use the same definition as the table above. It never touches `GameState.rng` (test: `rng.state` unchanged) and ignores that `BattleRules.after_strike` might end the battle after the first strike (noted in its doc comment).

**HUD**: when a unit is selected and the mouse is over an enemy it can attack (red-marked), the hover card shows an "ATTACK" block:

- `DAMAGE 3.0 (1–5)` – expected value with one decimal, 10–90 % range;
- `DESTROY 63 %` – only when the kill chance is above 0; `<1 %` for 0 < p < 0.5 %; `>99 %` above 99.5 % but below 1;
- `COUNTER 1.3 (0–3)` or `NO COUNTER` (out of range, or the target is certainly destroyed).

Exact placement and style belong to the HUD task (presentation-engineer); the numbers come from `forecast()` only (no rules in the view).

### 6. AI

Today the AI attacks the enemy in range with the lowest HP and never looks at damage. Proposal: for every valid target compute `forecast()` and pick the highest `score = expected_damage + 2 × kill_chance − counter_expected`; ties: lowest HP, then lowest id (today's rule). The kill bonus of 2 is an AI heuristic constant (not game balance), so it lives as a `const` in `AiPlayer`. Movement is unchanged. AI decisions use floats, but replays store commands, not AI decisions, so this cannot break a replay.

### 7. Simulation check (Step 2)

Run on the tree **before** the change (current master) and **after**, seeds 1..200, 50-turn harness limit, default battle:

1. `tools/simulate.sh 200 --factions=poland,russia`
2. `tools/simulate.sh 200 --factions=russia,poland`
3. Side bias (mirrored armies, the 59/34 question): `tools/simulate.sh 200 --factions=poland,poland` and `tools/simulate.sh 200 --factions=russia,russia`.

"After" is run twice: rolls with today's AI target choice (isolates the rule change) and rolls with the new AI scoring. Report a table per run: player 0 / player 1 wins, draws by the rules, matches cut by `--max-turns`, average length, errors; plus Poland's share of decided matches over runs 1 + 2 together, and the player-0 share in the mirror runs.

Targets (same as GDD "Balance of the default battle"): Poland 40–60 % of decided matches over runs 1 + 2, 0 errors, draws (incl. cut matches) ≤ 15 % per run. Expectations to check: matches get longer (battered companies deal less), the first-strike advantage grows, so the seat bias may change in either direction. If a target is missed, record the numbers and ask the human (the tuning ladder in the GDD changes unit counts only; do not change stats or the formula in Step 2). If `objective_battle` (TASK-088) is in master by then, also run 1 + 2 with `--scenario=objective_battle` and report them.

### 8. Determinism and roll order

- All rolls through `GameState.rng.randi_range(1, die)`, nothing else consumes it in an attack.
- Order in one `AttackCommand.apply()`: the attacker's strike rolls exactly `attacker.hp` times (all shots are rolled even if the target is already dead – the count never depends on the results), damage is applied, `BattleRules.after_strike` runs; then, only if the counter happens, the defender rolls exactly `defender.hp` (after the hit) times.
- `validate()` and `forecast()` never touch the rng.
- The same seed and command list give the same results; the replay fixture `tests/fixtures/replays/default_battle_12345.json` changes and must be regenerated with `tools/make_replay_fixture.sh` and committed with the change.
- The `unit_attacked` event keeps `damage` = hits scored (as today it may exceed the target's HP; 0 is now possible) and gains `"shots": int` (number of rolls); docs/ARCHITECTURE.md event table updated. The presentation must play a 0-damage strike (a miss) without errors.

## Open questions for the human

**Decided 2026-10-30: the human approved every recommendation below** (exact calibration, no minimum damage, counter with the HP left, certain hits allowed, AI scoring in this task, Step 2 split into TASK-089a / TASK-089b, one-shot kills no longer certain).

1. **Calibration below the minimum**: exact calibration (recommended) keeps the old "at least 1" as the mean, so terrain still makes no difference once the margin is ≤ 0 (infantry vs. a tank: 1.0 on plains, forest and hills). Alternative B: below margin 1 the die doubles per missing point (`die = max_hp × 2^(1 − margin)`, `hit_on = 1`) – infantry vs. a tank in forest 0.5, on hills 0.25. **Recommendation: exact calibration now**, so the simulation measures only the randomness; B is a candidate answer to the GDD "Damage scale" question later.
2. **No minimum damage** (a strike may deal 0). **Recommendation: yes, no minimum** (section 2).
3. **Counter strength = defender's HP after the hit**. **Recommendation: yes** – it is what "a battered company fights worse" means; watch the first-strike advantage in the simulation.
4. **Certain hits** when `base >= max_hp`. None today. **Recommendation: allow them** (no 95 % cap): a cap would break the calibration, and such matchups are a deliberate overmatch.
5. **AI scoring** (`expected_damage + 2 × kill_chance − counter_expected`) in this task or a follow-up? **Recommendation: in this task**, with the simulation run both with and without it so the two effects stay separate.
6. **Split Step 2** into 2a core + AI + simulation (opus) and 2b HUD forecast (sonnet)? It is one mechanic but two layers and a long session. **Recommendation: split** – 2b depends on 2a; the core change is playable without the forecast only for a short time, so 2b follows immediately.
7. **One-shot kills** (GDD open question): an Abrams now destroys a full MLRS 63 % of the time instead of always. **Recommendation: accept**; it answers that question for now.

## Step 2 – implementation

### Acceptance criteria – TASK-089a: core, AI, simulation (gameplay-engineer)

Damage rule (`tests/unit/test_attack.gd`, `test_counterattack.gd`, new `test_combat_rolls.gd`):

- [x] `hit_on`: Abrams (A7, 10 HP) vs. a squad (D3) on plains = 4, in forest = 3, on hills = 2; squad (A4) vs. Abrams (D4) on hills = 1 (never below 1); Homar-K (A6, 6 HP) vs. Uragan (D1) on plains = 5; a test unit with A20 vs. D1 and 6 HP gives 6 (capped at `max_hp`) and its strike always deals exactly `shots` damage.
- [x] A strike consumes exactly `striker.hp` calls of `GameState.rng.randi_range(1, striker.max_hp)` and its damage equals the number of results `<= hit_on`: checked against a second `RandomNumberGenerator` with the same seed/state replaying the same calls (full strength 10 and battered 3 HP).
- [x] Damage can be 0: with a seed found by the test, a squad's strike on an Abrams deals 0; the `unit_attacked` event has `damage` 0 and the target's HP is unchanged. The event carries `"shots"`.
- [x] The victim's HP never goes below 0; a dead victim emits `unit_died` as today.
- [x] Counter: rolls exactly `defender.hp` (after the hit) times with the defender's `max_hp` die and `hit_on` against the attacker's defence + the attacker's tile bonus; no counter rolls when the defender died, is out of range or the battle ended (rng state after the attack equals the state after only the attacker's rolls).
- [x] Determinism: two simulations with the same seed and the same commands give identical events and identical `GameState.to_dict()`; a different seed gives a different result for a fixed 10-attack sequence.
- [x] Statistical calibration (fixed seed, 2000 strikes, deterministic): mean damage of a full Abrams on a full squad on plains is within 4.0 ± 0.15; of a squad at 5/10 HP on an Abrams within 0.5 ± 0.05.

Forecast (`tests/unit/test_combat_forecast.gd`):

- [x] Full Abrams → full squad on plains: `expected_damage` 4.0 (± 1e-6), range 2–6, `kill_chance` 0, `counter_possible` true, `counter_expected` 0.6 (± 1e-3; 0.1 × E[10 − hits]).
- [x] Full squad → full Abrams on plains: expected 1.0, range 0–2, kill 0, `counter_expected` 3.6 (± 1e-3).
- [x] Full Abrams → full Homar-K/Uragan on plains: `expected_damage` 5.398 (± 1e-3), range 4–6 (capped at 6 HP), `kill_chance` 0.6331 (± 1e-4), `counter_expected` 0.2007 (± 1e-3).
- [x] Full Abrams → full T-72B3 on plains: expected 3.0 (± 1e-3), range 1–5, `kill_chance` 0.0016 (± 1e-4), `counter_expected` 1.250 (± 1e-3).
- [x] Homar-K → Uragan on plains at distance 6: `counter_possible` false, `counter_expected` 0, `kill_chance` 0.3349 (± 1e-4).
- [x] An attacker at 0 … `max_hp` HP: `expected_damage` = min-capped binomial mean (e.g. Abrams at 5 HP → squad on plains: 2.0).
- [x] `forecast()` does not change `GameState.rng.state` nor any unit.

AI (`tests/unit/test_ai_player.gd`):

- [x] With two targets in range, the AI attacks the one with the higher `expected_damage + 2 × kill_chance − counter_expected` (case: a full Abrams next to a full T-72B3 with 8 HP and a full Uragan with 6 HP – today it would pick the Uragan by lowest HP too; add a case where the lowest-HP target scores lower, e.g. a 6-HP Abrams on hills vs. a 7-HP squad on plains for a T-72B3).
- [x] Ties fall back to lowest HP, then lowest id.

Replay and records:

- [x] `tests/fixtures/replays/default_battle_12345.json` regenerated (`tools/make_replay_fixture.sh`); `test_replay` passes; a recorded match replays to the same final state including `rng_state`.

Simulation (no test; numbers in "Implementation notes"):

- [x] The before/after report of section 7 (runs 1–3, "after" with and without the new AI scoring) is in "Implementation notes"; the GDD "Balance of the default battle" gets the measured numbers.
- [x] docs/ARCHITECTURE.md event table: `unit_attacked` gains `shots`; `damage` may be 0.
- [x] `tools/check.sh` passes.

### 2b HUD forecast

Moved to [TASK-089b](TASK-089b-combat-forecast-hud.md) (presentation-engineer, after this task).

## Player manual

To change in docs/MANUAL.md: the rules items when TASK-089a is done, the forecast item when TASK-089b is done:

- Section 7 "Damage": replace "There are no dice …" with the roll: each HP of the attacker rolls once; the hit chance is (Attack − (Defense + tile bonus), at least 1) out of the attacker's full HP; damage = hits; it can be 0; a weakened unit fires fewer shots.
- "HP" in the unit stats: HP is the company's strength – fewer HP means fewer shots.
- Counterattack: the defender hits back with the HP it has left after the attack.
- Worked examples: rewrite with averages and ranges (Abrams → T-72B3: 3 on average, usually 1–5; counter 1.25).
- Damage table: becomes "average at full strength" (same numbers as today) plus a note on the spread and on 0-damage chances.
- New: the attack forecast in the hover card (expected damage, range, destroy chance, counter).
- Computer opponent: it now picks the attack with the best expected result (damage dealt, chance to destroy, minus the expected counter), not the weakest unit.

## Out of scope

Suppression / morale (TASK-090), indirect-fire accuracy from spotting (after TASK-007), changing unit stats or the default force (Step 2 only measures; the tuning ladder needs the human).

## Implementation notes

Done 2026-10-30 (gameplay-engineer, opus; review fixes in the main session).

- **Core**: `AttackCommand.hit_on()` (= `min(compute_damage, striker.max_hp)`), `roll_hits()` (exactly `striker.hp` calls of `rng.randi_range(1, max_hp)`), `forecast()`; `apply()` rolls the attacker's shots, applies damage, runs `after_strike`, then the counter rolls the defender's HP left. `unit_attacked` gains `shots`; `damage` = hits, may be 0 or exceed `target_hp`.
- **CombatForecast** (`src/core/combat_forecast.gd`): exact binomial, counter as the mixture over the first strike's outcomes, percentiles = smallest k with CDF ≥ q. Deviation from the spec text: `kill_chance` is exactly 0 only when `shots < defender.hp`; Abrams → full squad is 0.4^10 ≈ 1e-4, so TASK-089b will show `DESTROY <1 %` there.
- **AI**: `_best_target` scores `expected_damage + KILL_BONUS (2.0) × kill_chance − counter_expected` (`AiPlayer.target_score`), scores within 1e-9 tie → lowest HP → lowest id. The command-point ordering (`_action_score`) still uses the deterministic `compute_damage`.
- **Tests**: `Fixtures.sure_fighter()` (attack 100 → every shot hits) gives certain results; other exact checks replay the same calls on a copied `RandomNumberGenerator`. Two tests pin fixture-seed rolls with a comment (`test_rocket_artillery` `SURVIVING_SEED`, `test_a_counter_can_win_by_destroy_share`). Replay fixture regenerated.
- **Presentation**: unchanged – playback reads only `target_hp`, so a 0-damage strike plays as a hit with no HP loss (no "-0" text). A distinct miss cue could come with TASK-089b.
- **Docs**: ARCHITECTURE event table + roll order; MANUAL §4/§7/§9/§13 (§13 lists the forecast as not yet in the game – TASK-089b removes it); GDD Combat, Balance, Open questions.

### Simulation (seeds 1..200, 50-turn harness; P0 wins / P1 wins / draws by rules / harness cut / avg length of decided; 0 errors everywhere)

| Run | Before (master) | Rolls + old AI | Rolls + new AI (shipped) |
|---|---|---|---|
| default poland,russia | 94 / 98 / 0 / 8 / 10.5 | 76 / 117 / 0 / 7 / 11.5 | 88 / 105 / 0 / 7 / 11.2 |
| default russia,poland | 34 / 158 / 0 / 8 / 10.7 | 91 / 101 / 0 / 8 / 11.6 | 75 / 116 / 0 / 9 / 11.5 |
| default poland,poland | 88 / 106 / 0 / 6 / 10.2 | 84 / 107 / 0 / 9 / 11.1 | 78 / 113 / 0 / 9 / 10.5 |
| default russia,russia | 83 / 103 / 0 / 14 / 10.4 | 85 / 98 / 0 / 17 / 11.6 | 79 / 105 / 0 / 16 / 11.2 |
| objective poland,russia | 32 / 77 / 91 / 0 / 6.8 | 29 / 96 / 75 / 0 / 7.3 | 32 / 84 / 84 / 0 / 7.4 |
| objective russia,poland | 73 / 53 / 74 / 0 / 6.8 | 48 / 62 / 90 / 0 / 7.0 | 42 / 61 / 97 / 0 / 6.9 |
| Poland share of decided, runs 1+2 (target 40–60 %) | 65.6 % | 46.0 % | **53.1 %** |
| P0 share in mirrors (poland / russia) | 45.4 % / 44.6 % | 44.0 % / 46.4 % | 40.8 % / 42.9 % |

Default battle: inside every target (draws incl. cuts 3.5–8 % per run). The mild player-1 seat bias persists and grows slightly with the new AI. `objective_battle` draws are 42–49 % – above 15 %, but they were 37–46 % before this change (TASK-088 balance, not caused by the rolls).
