# TASK-081: Unit orders as game rules – umbrella and design (dig in, smoke, blind fire, ambush, scoot; resupply and camouflage specified only)

- **Status**: ready
- **Layers**: GDD / balance (game-designer); implementation in sub-tasks (core + ai, no presentation)
- **Depends on**: – (design decisions taken 2026-11-10; soft: TASK-039b balance)
- **Sections**: GDD "Unit orders", GDD "Combat"; docs/design/hud_v3/README.md section 04
- **Model**: sonnet (design and task writing; the opus part is TASK-081c)

## Goal

The radial menu of TASK-082 offers six orders per own unit but only Move exists. This umbrella fixes the rules (GDD "Unit orders") and splits the work into three buildable tasks.

## Decisions (human, 2026-11-10)

1. Every non-move order uses the unit's once-per-turn action slot (like an attack); no action points, no new resource.
2. First round ships: Dig in, Smoke screen (tank), Blind fire, Ambush (infantry), Scoot (MLRS). Resupply (needs ammo, TASK-099) and Camouflage (needs fog, TASK-007) are in the GDD only; their radial slots are shown disabled with a reason.
3. Dig in: +2 defence, infantry and tanks only, stacks with the tile bonus, cleared on move, no movement after digging in that turn; balance check with `tools/simulate.sh`.
4. Smoke (tank): hex within 2 of the tank, blocks direct-fire line of sight through it until the owner's next turn; indirect fire ignores it.
5. Blind fire, Ambush, Scoot are design proposals, fixed in the GDD table. Per-unit order state serialised in `Unit` / snapshot / `CommandCodec`.
6. Split: 081a (state, slot rule, Dig in), 081b (Smoke, Blind fire), 081c (Ambush, Scoot, AI use).

## Sub-tasks

| Task | Content | Depends on | Model |
|---|---|---|---|
| [TASK-081a](TASK-081a-order-state-and-dig-in.md) | `OrderDefinition` data, order state in `Unit`, slot rule, codec, events, **Dig in** | TASK-089a (done) | sonnet |
| [TASK-081b](TASK-081b-smoke-and-blind-fire.md) | **Smoke screen** (needs line of sight) and **Blind fire** | TASK-081a, TASK-131a | sonnet |
| [TASK-081c](TASK-081c-ambush-scoot-ai.md) | **Ambush** reaction strike, **Scoot**, AI use, balance check | TASK-081b | opus |

## Assumptions to confirm (all marked [ASSUMPTION] in the GDD)

- Scoot needs no second slot but only works after firing (otherwise it would be a plain move).
- Blind fire margin is `attack − defence − tile bonus − 1`, minimum 1; the defender counters by the normal rules; target hex must hold an enemy (rejected otherwise) until fog exists.
- Ambush: +1 attack on counters, one free reaction strike on an enemy ending its move adjacent (end hex only, not pass-through), no counter to it; lasts until the owner's next turn, a move or the strike.
- Smoke blocks both sides' direct fire, distance 1–2 (not 0), stored per hex in `GameState`, outlives its tank.
- Order state is in `snapshot()` only when set; `MatchRecord` version stays 2.
- Slot 3 / MLRS shows "Scoot" even though it costs no slot; Resupply / Camouflage reason texts in the GDD table.

## Acceptance criteria

- [x] GDD section "Unit orders" written: common rules, per-order table (cost, preconditions and reason codes, numbers, duration, fog, AI use) and UI texts.
- [x] Sub-task files 081a, 081b, 081c exist with testable criteria, and the Ammunition open question points to the section.
- [ ] Human has accepted the assumptions above (changes go into the GDD first).

## Player manual

none here; each sub-task lists its MANUAL change.

## Out of scope

HUD (TASK-082), visuals of smoke / entrenchment, ammunition and supply (TASK-099), fog of war (TASK-007), Resupply and Camouflage rules.

## Implementation notes

Design delivered 2026-11-10 (GDD "Unit orders"). Built by 081a–c; the task is `done` when all three are.
