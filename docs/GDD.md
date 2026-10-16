# Game Design Document

> Living document. Assumptions marked **[ASSUMPTION]** are the starting point for the prototype – to be confirmed or changed.

## Vision

- **Genre**: turn-based tactical 3D strategy on a hex grid.
- **One sentence**: _[to be filled in – what makes this game unique?]_
- **Inspirations**: _[e.g. Battle for Wesnoth, Into the Breach, Civilization, Heroes]_
- **Platform**: PC (Linux/Windows) **[ASSUMPTION]**

## Gameplay loop

1. On their turn, the player gives orders to units (move, attack).
2. They end the turn; the opponent (AI) takes theirs.
3. The last side with living units wins – eliminate all enemy units **[ASSUMPTION]** (see Open questions).

## Map

- Hexes, procedural rectangular map from a seed (12×10 in the prototype battle) **[ASSUMPTION]**.
- Terrain:

  | Terrain | Move cost | Defense bonus | Status |
  |---|---|---|---|
  | Plains | 1 | 0 | cost implemented; bonus planned (TASK-002) |
  | Forest | 2 | +1 | cost implemented; bonus planned (TASK-002) |
  | Hills | 2 | +2 | cost implemented; bonus planned (TASK-002) |
  | Water | impassable | – | implemented |

  Move costs are currently hardcoded in `src/core/terrain.gd`; TASK-002 moves them to `data/terrain/*.tres`, which then becomes the source of truth.

## Units

| Unit | HP | Move | Attack | Defense | Range | Status |
|---|---|---|---|---|---|---|
| Infantry | 10 | 3 | 4 | 3 | 1 | implemented |
| Cavalry | 8 | 5 | 5 | 2 | 1 | implemented |
| Archer | 6 | 3 | 5 | 1 | 2 | planned (TASK-011) |

Source of truth for the numbers: `data/units/*.tres`.

Starting armies (prototype battle): each side has infantry, cavalry, infantry (+ an archer after TASK-011) on opposite map edges; spawn tiles are always plains.

## Combat

Implemented in TASK-001 (`AttackCommand`):

- **Attack**: a unit may attack one living enemy unit within its `attack_range` (hex distance; 1 = adjacent). Rejection codes: `game_over`, `unit_not_found`, `not_your_unit`, `not_an_enemy`, `already_attacked`, `out_of_range`.
- **Once per turn**: each unit attacks at most once per turn. Attacking sets the attacker's remaining movement to 0 – a unit can move then attack, but not attack then move. Both are reset at the start of the owner's turn.
- **Damage** = `max(1, attack − defense)`, **deterministic**, no RNG **[ASSUMPTION]** (see Open questions: randomness). Current matchups: infantry→infantry 1, infantry→cavalry 2, cavalry→infantry 2, cavalry→cavalry 3.
- **Death**: a unit whose HP drops to 0 dies (`unit_died`), is removed from the map and no longer blocks its tile.
- **Victory**: when exactly one player has living units left, that player wins (`game_over`, `GameState.winner`); after that every command is rejected with `game_over` **[ASSUMPTION]**.

Planned:

- **Terrain defense** (TASK-002): damage = `max(1, attack − (defense + defense bonus of the defender's tile))`; the attacker's tile doesn't matter.
- **Counterattack** (TASK-010): a defender that survives and has the attacker within its own `attack_range` hits back once with the same formula; deterministic **[ASSUMPTION]**; doesn't use the defender's attack for the turn; a unit counters every attack it survives.
- **Ranged units** (TASK-011): an archer with range 2 can attack melee units (range 1) from distance 2 without being countered.

## Open questions

Each question lists the tasks that depend on the answer.

- **Victory condition**: elimination of all enemy units is the current **[ASSUMPTION]**. Alternatives: hold objectives, kill the leader, turn limit with points. → TASK-012 uses a harness-only turn limit (draw) and would change if a turn limit becomes a real rule; future scenario tasks.
- **Turn limit as a game rule?** Not in the game yet; only the AI-vs-AI simulation (TASK-012) stops matches after N turns. → TASK-012.
- **Randomness in combat**: deterministic (like Into the Breach) or with rolls (like Wesnoth)? Currently deterministic **[ASSUMPTION]**. → TASK-002 (flat defense bonus vs. hit-chance modifier), TASK-010 (deterministic counter), TASK-011 (archer balance). Replays (TASK-005) work either way, because all randomness goes through `GameState.rng`.
- **Damage scale**: with the subtractive formula and current stats, most matchups deal 1–3 damage, and terrain bonuses (TASK-002) push many of them to the minimum of 1, which makes terrain differences between units disappear. Should HP/attack be scaled up (e.g. ×2) or the formula changed? → revisit with TASK-012 statistics after TASK-002/-010/-011.
- **Forest vs. hills**: with the proposed numbers hills (+2) strictly dominate forest (+1) at the same move cost. Should they differ in another way (e.g. forest blocks archer shots, hills give +1 range)? → TASK-002, TASK-011 follow-ups.
- **Scale**: tactical skirmishes (a few units) or strategy with an economy and cities? → TASK-007 (fog of war), map size, AI scope.
- **Setting**: fantasy, historical, sci-fi? → unit roster and art; no current task blocked.
- **Modes**: vs AI only, hot-seat, network multiplayer? → TASK-005 (command serialization is the groundwork for network/replays), `HUMAN_PLAYER` constant in the battle controller, TASK-007 (hot-seat fog needs a hand-off screen).
- **Fog of war**: yes/no, and per player vision rules? → TASK-007 (stays `idea` until scale and modes are decided).
