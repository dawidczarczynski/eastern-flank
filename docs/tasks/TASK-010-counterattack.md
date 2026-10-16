# TASK-010: Counterattack

- **Status**: ready
- **Layers**: core / presentation
- **Depends on**: TASK-001. Soft: TASK-002 (if done, counter damage uses `AttackCommand.compute_damage`, i.e. includes the terrain bonus of the original attacker's tile; if not, create `compute_damage` here with the TASK-001 formula). TASK-008 makes the counter readable (hit, then counter-hit) but is not required.

## Goal

Attacking has a cost: a defender that survives strikes back. The player must weigh whether a hit is worth the damage taken – and ranged units (TASK-011) gain their main advantage.

## Rules

- After the attacker's hit, if the target is **alive** and `Hex.distance(target, attacker) <= target.definition.attack_range`, the target hits back **once** with the same formula: `compute_damage(state, target, attacker)`.
- **Deterministic**, same as TASK-001 – **[ASSUMPTION]** pending the GDD open question on randomness.
- A counter is not an action: it ignores and does not change the target's `has_attacked` and `moves_left` (the target may have attacked in its own previous turn and still counters). A unit counters every attack it survives (no per-turn limit). A counter never triggers another counter.

## Event decision

Reuse `unit_attacked` and add a `counter: bool` field to **every** `unit_attacked` event (`false` for normal attacks, `true` for counters). Reason: a counter is the same thing for every consumer (one unit damages another, same fields, same hit animation); a flag keeps a single handler in the view and in future replay/log tools, while still letting the view tell them apart. A separate `unit_counterattacked` type would duplicate handling for no gain. Update the events table in `docs/ARCHITECTURE.md`.

## Acceptance criteria (testable)

Tests in `tests/unit/test_counterattack.gd`, plains map, A = attacker (owner 0), B = target (owner 1), `Fixtures.fighter(attack, defense, max_hp, range)`:

- [ ] A = `fighter(4, 2)` at `(0,0)`, B = `fighter(5, 1)` at `(1,0)`. A attacks B → B hp **7**, A hp **7**. Events exactly: `unit_attacked {attacker_id: A, target_id: B, damage: 3, target_hp: 7, counter: false}`, then `unit_attacked {attacker_id: B, target_id: A, damage: 3, target_hp: 7, counter: true}`.
- [ ] Target dies: A = `fighter(6, 2)`, B = `fighter(5, 1, 5)` → events `unit_attacked (counter: false, target_hp 0)`, `unit_died B`; **no** counter event; A hp unchanged (10).
- [ ] Counter kills the attacker: A = `fighter(4, 2, 3)` (only unit of player 0), B = `fighter(5, 1)` (only unit of player 1) → events `unit_attacked (counter false)`, `unit_attacked (counter true, damage 3, target_hp 0)`, `unit_died A`, `game_over {winner: 1}`; `state.winner == 1`; further commands rejected with `game_over`.
- [ ] Counter kills the attacker but player 0 has other units → `unit_died A`, no `game_over`, `state.winner == -1`.
- [ ] Out of the defender's range: A = `fighter(4, 2, 10, 2)` at `(0,0)`, B = `fighter(5, 1)` (range 1) at `(2,0)` → only one `unit_attacked` event, A hp 10.
- [ ] Defender with range 2 counters at distance 1: A = `fighter(4, 2)` at `(0,0)`, B = `fighter(5, 1, 10, 2)` at `(1,0)` → counter happens (A hp 7).
- [ ] B with `has_attacked = true` and `moves_left = 0` before being attacked still counters; after the counter B's `has_attacked` and `moves_left` are unchanged.
- [ ] Two different player-0 units attack B in one turn → B counters both (two `counter: true` events).
- [ ] Existing TASK-001 tests are updated only where they assert exact event lists / attacker HP (now affected by counters); `counter: false` is present on normal attacks.
- [ ] If TASK-002 is done: A on FOREST (+1) attacked back by B (attack 5) with defense 2 → counter damage **2** instead of 3.
- [ ] AI: `AiPlayer` loop keeps working when its own unit dies from a counter (skips dead units, stops on `game_over`) – test: AI unit with 1 HP attacks a strong adjacent enemy, dies, AI ends the turn without errors.
- [ ] View: a `counter: true` event plays the hit reaction and HP update on the original attacker; `unit_died` for the attacker plays its death animation.

## Playtest (for the human)

1. Attack an enemy infantry with your infantry – the enemy loses 1 HP, then your unit flashes and loses 1 HP too.
2. Attack with cavalry an enemy that has only 2 HP left – the enemy dies and your cavalry takes no damage.
3. Bring a badly damaged unit next to an enemy and attack – the counter kills it and it disappears.
4. During the AI turn, AI attacks on your units are answered by counter-hits on the AI units.
5. (With TASK-008) the counter-hit plays after the first hit, not at the same time.

## Out of scope

- Randomness, first-strike/no-counter abilities, counter damage penalties, AI weighing counter damage when choosing targets, damage preview.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
