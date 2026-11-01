# TASK-120: Battle auto-resolve – the result of a contact battle computed from the same forces, postures, terrain and conditions; shared `BattleResult` outcome fields

- **Status**: blocked
- **Layers**: core (`src/core/`, `src/core/data/`) + data + presentation (one button on TASK-094's contact notice)
- **Depends on**: TASK-094
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

At every contact the player – the leader on the staff map – may either fight the battle as the commander or auto-resolve it and see the result at once (GDD "Vision decisions" → "Auto-resolve", "Operational layer" → "Player roles", "Battle hand-off and auto-resolve"; human decision 2026-11-01). Auto-resolve hands back the same `BattleResult` as a played battle, so TASK-095 applies both identically, and AI-vs-AI campaigns (TASK-103) run fast without playing battles.

## Acceptance criteria (testable)

Common test setups (built in `tests/fixtures.gd`; factions `[poland, russia]` unless stated; `attacker` 0; `terrain` `&"plains"`; `command_points` 0 for both; no turn limit unless stated; the `BattleSetup` fields `attacker`, `terrain`, `Conditions.posture`, `Conditions.position_bonus` come from TASK-094 – position bonus defend +1, advance 0, march −1):

- **"salvo"**: company 0 player 0 `homar_k` strength 3, company 1 player 0 `homar_k` strength 6 (advance, 0); company 2 player 1 `bm27_uragan` strength 6 (march, −1). Homar-K → Uragan `hit_on` = min(max(1, 6 − (1 − 1 + 0)), 6) = 6 – every roll hits.
- **"crush"**: player 0: 3 × `m1a2_sepv3` 10 + 1 × `pl_mech_infantry` 10 (advance, 0); player 1: 1 × `ru_motor_rifle` 10 (defend, +1).
- **"mirror"**: factions `[poland, poland]`; each player 3 × `pl_mech_infantry` 10 + 1 × `m1a2_sepv3` 10, both `advance` (0).
- **"fortress"**: "mirror" with player 1 `defend` (+1) and `terrain` `&"hills"` (+2).

Data:

- [ ] `AutoResolveRules` (Resource, `src/core/data/auto_resolve_rules.gd`, `data/battle/auto_resolve.tres`): `default_rounds` 8, `break_share` 50 (percent of a side's starting strength) **[ASSUMPTION]** (test reads the file); `problem() -> String` ("" when valid; one test each: `default_rounds` < 1, `break_share` outside 1 … 100).

Shared result fields (`BattleResult`, used by played and auto-resolved battles):

- [ ] `BattleResult` gains `resolution: StringName` (`&"played"` / `&"auto"`), `field_holder: int` and `retreat: int`; `to_dict` / `from_dict` carry them (`from_dict` → null when one is missing or `resolution` is another string). `from_battle` sets `&"played"`.
- [ ] One helper, `BattleResult.settle(setup)` (called by `from_battle` and by auto-resolve – the rule exists once): `field_holder` = `winner` when ≥ 0, else `1 − setup.attacker` (the defender) when `attacker` ≥ 0, else −1; `retreat` = the loser when `winner` ≥ 0 and the loser has a company with `strength_end` > 0, else −1. Tests (on hand-made results): winner 0, a player 1 company left → holder 0, retreat 1; winner 0, player 1 wiped out → holder 0, retreat −1; draw with attacker 0 → holder 1, retreat −1; draw with attacker −1 → holder −1, retreat −1. A played battle via `from_battle` on a finished `GameState` with winner 1 gives the same two fields as the helper.

Resolver (`AutoResolve`, static, pure, `src/core/auto_resolve.gd`): `resolve(setup: BattleSetup, rules: AutoResolveRules = <data/battle/auto_resolve.tres>) -> BattleResult`.

- [ ] Rejects (`push_error`, null – one test each, same messages as `Scenario.from_setup`): a unit type not in its player's faction roster, a strength outside 1 … `max_hp`, a player without companies, `conditions` not one per faction.
- [ ] Shape: one `Company` per setup company, same order, `player` / `unit_type` / `ref` / `strength_start` copied, 0 ≤ `strength_end` ≤ `strength_start`; `resolution` `&"auto"`; `turns` = the rounds fought; `field_holder` / `retreat` from `settle`.
- [ ] Rounds and fire (GDD "Battle hand-off and auto-resolve"): rounds = `setup.objectives.turn_limit` when > 0, else `default_rounds`. In a round, every living company fires once; with `command_points` > 0 only the first that many living companies of that player in setup order fire. Firing order = setup order; the target is the living enemy company with the highest `hit_on / shooter max_hp` (ties: lowest strength at the start of the round, then lowest setup index); `hit_on = min(max(1, attack − (target defense + target side's position_bonus + terrain defense bonus if the target's side is the defender)), shooter max_hp)`; the shooter rolls exactly its strength at the start of the round, each roll `rng.randi_range(1, max_hp)`, hits = rolls ≤ `hit_on`. Damage is applied after all companies have fired (simultaneous; a company destroyed in the round has fired), capped at the target's strength.
- [ ] End of a round: a side with no strength left is eliminated; a side whose losses × 100 ≥ `break_share` × its starting strength is broken. Exactly one side eliminated or broken → the other wins (`reason` `&"eliminated"` when the loser has no strength left, else `&"broken"`); both in the same round → draw (`&"eliminated"` when both have no strength left, else `&"broken"`); no end after the last round → draw, `&"turn_limit"`.
- [ ] "salvo" (exact, any seed): → winner 0, `reason` `eliminated`, `turns` 1, company 2 `strength_end` 0, company 1 `strength_end` 6, company 0 `strength_end` in 0 … 3 (the Uragan targets the weaker Homar-K), `field_holder` 0, `retreat` −1.
- [ ] "salvo" with player 0 `command_points` 1 (only company 0 fires: 3 hits) → winner 0, `reason` `broken`, `turns` 1, company 2 `strength_end` 3, `retreat` 1.
- [ ] "salvo" with company 1 removed, company 0 `homar_k` strength 4, company 2 `bm27_uragan` strength 4 and player 0 also `march` (−1) – both always hit → draw, `reason` `eliminated`, both `strength_end` 0, `field_holder` 1, `retreat` −1.
- [ ] Overwhelming force wins cheaply – "crush", seeds 1 … 100: player 0 wins ≥ 95; mean player 0 losses ≤ 4.0 (10 % of 40); in every player 0 win the motor rifle company is destroyed or retreats.
- [ ] Equal forces are costly – "mirror", seeds 1 … 200: each side's mean losses ≥ 12 (30 % of 40); |wins of player 0 − wins of player 1| ≤ 30.
- [ ] Terrain and posture count – "fortress", seeds 1 … 200: player 1 wins more often than player 0, and player 0's mean losses > player 1's mean losses.
- [ ] Turn limit – "mirror" with `turn_limit` 1, seeds 1 … 50: every result is a draw, `reason` `turn_limit`, `turns` 1, `field_holder` 1.
- [ ] Determinism: the same setup and seed twice → identical `to_dict()`; "mirror" over seeds 1 … 20 → at least 2 different results; golden: "mirror" seed 7 → the `to_dict()` stored in the test (regenerated only on purpose, like the replay fixture).
- [ ] No state change: `setup.to_dict()` is unchanged after `resolve`; with an `OperationalState` holding the setup as a pending battle (TASK-094), `resolve` leaves its `snapshot()` and `rng_state` unchanged – the operation changes only through `ResolveBattleCommand`.
- [ ] Speed: a 12 vs 12 company setup (three battalions per side) resolves in ≤ 2 ms median over 50 runs (headless test; budget for TASK-103's AI-vs-AI campaigns).

Operation and record:

- [ ] `ResolveBattleCommand` (TASK-094) gains, after its existing checks, `auto_mismatch`: a result with `resolution` `&"auto"` whose `to_dict()` differs from `AutoResolve.resolve(first pending setup).to_dict()`. Tests: the correct auto result → accepted; one `strength_end` changed → `auto_mismatch`; a `played` result is not recomputed.
- [ ] `CampaignRecord` battle entries gain `"resolution"`; an auto entry has `"commands": []`. Full verification re-runs `AutoResolve.resolve(setup)` for auto entries (mismatch → `battle_diverged`), operational replay is unchanged (results come from the stored `ResolveBattleCommand`s). Test: a record with one played and one auto-resolved battle verifies; a tampered auto entry → `battle_diverged`.
- [ ] ADR 0015 amended (dated note): §2 battles are played or auto-resolved, the auto result is computed from `setup.seed` only; §3 the new `BattleResult` fields and `settle`; §4 the `"resolution"` field of battle entries. docs/ARCHITECTURE.md "Two layers": `AutoResolve`, `AutoResolveRules`, the result fields, `auto_mismatch`.

Presentation (small):

- [ ] TASK-094's contact notice gets an **Auto-resolve** button next to **Play battle** (only for a battle where the human plays a side): `Session.auto_resolve()` → `AutoResolve.resolve(setup)` → `ResolveBattleCommand` → the staff map stays and shows a short result notice (losses per company of each formation, who holds the field, who retreats – read from the `BattleResult`; TASK-095 turns it into the full after-action report for both kinds of battle). Strings through `tr()`, en + pl rows. A battle where neither side is human (simulation) never shows the notice – the caller resolves it automatically (helper `Session` / harness, tested in core by TASK-103).

## Playtest (for the human)

1. Start the Suwałki operation, give a Polish battalion an `advance` order into a Russian formation and end turns until contact.
2. On the contact notice choose **Auto-resolve**: the result appears at once on the staff map (losses, field held, retreat); no battle scene loads.
3. Save, reload: the same result. Start the same contact again from an earlier save and choose **Play battle** instead: the battle starts with the same companies and strengths.
4. Judge whether the auto results feel plausible against played ones (a strong attack wins with few losses, equal forces bleed both sides, defending on hills or in a town holds).

## Player manual

In the operational chapter (written with TASK-093 / TASK-094): at each contact you choose to **play the battle** as the commander or to **auto-resolve** it. Auto-resolve uses the same companies, strengths, postures (defend +1, advance 0, caught on the march −1 to defense), the defender's terrain and the command points; the companies fire in rounds with the same dice as in battle, and a side that has lost half of its strength breaks; the result (losses, who holds the field, who retreats) counts exactly like a played battle's. There is no penalty for auto-resolving; a played battle cannot be switched to auto-resolve.

## Out of scope

- Applying the result to formations (losses, retreat, fatigue – TASK-095); the contact rule, setup fields, mission / intent and the contact notice itself (TASK-094).
- Range, movement, objective hexes and line of sight inside auto-resolve (artillery fires like any company; the tactical map is not loaded) **[ASSUMPTION – GDD Open questions "Auto-resolve numbers"]**.
- Ammunition, morale, fire support, suppression – not read by played battles yet either; TASK-099 / TASK-090 change both resolvers together.
- An odds forecast for auto-resolve on the contact notice (later, from repeated `resolve` runs or a closed form); switching a played battle to auto-resolve halfway; the `tools/simulate.sh` campaign harness (TASK-103).
- Calibration against played battles is measured, not tested: the agent runs "crush", "mirror" and "fortress" also as headless tactical AI-vs-AI battles (`Scenario.from_setup` on the generated map, 50 seeds each) and lists win shares and mean losses of both resolvers in the implementation notes; a gap of more than 20 points in a win share is flagged to the human.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
