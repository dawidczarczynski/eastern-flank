# Eastern Flank – Player's Manual

> This manual covers the game **as it plays today** (an early prototype). It is updated whenever a rule, unit or control changes.

## 1. Overview

Eastern Flank is a turn-based tactical battle on a hex map. You command **Poland** (blue) against **Russia** (red), which the computer plays. Each side starts with four units. (In the Polish version of the game the sides are called "Polska" and "Rosja".)

For now the two sides differ only in name, colour and look: both field the same units with the same stats and follow the same rules. You and the opponent take turns moving and attacking.

**Goal:** destroy every enemy unit. The last side with units left on the map wins.

## 2. The battle

- The map is **12 × 10 hexes**. It is the same map every time you start the game.
- Poland starts on one short edge of the map, Russia on the opposite edge. Every unit starts on a plains tile.
- Each side has the same army:

  | Unit | Count | Position |
  |---|---|---|
  | Infantry | 2 | front line |
  | Cavalry | 1 | front line, between the two infantry |
  | Rocket Artillery | 1 | behind the cavalry, on the map edge |

## 3. Turn structure

1. **Poland (you) always moves first.** During your turn you can give orders to all your units, in any order.
2. When you are done, end your turn. The turn bar shows "AI TURN" and Russia acts. Its moves and attacks are replayed as animations (sped up if there are many, so the enemy turn takes only a few seconds).
3. Then it is your turn again, and the **turn counter** goes up by one. A banner in the middle of the screen announces each new turn and side.

At the start of a side's turn, all of its units get their full movement points back and may attack again. Points you don't use are not saved for later.

There is no turn limit.

## 4. Units

| Unit | HP | Movement | Attack | Defense | Range | Look on the map |
|---|---|---|---|---|---|---|
| Infantry | 10 | 3 | 4 | 3 | 1 | a squad of soldiers |
| Cavalry | 8 | 5 | 5 | 2 | 1 | a tank |
| Rocket Artillery | 6 | 3 | 5 | 1 | 5 | a truck with a rocket launcher |

- **HP**: how much damage the unit can take. At 0 HP it is destroyed and removed from the map. HP doesn't come back.
- **Movement**: movement points per turn (see Movement).
- **Attack** / **Defense**: used in the damage calculation (see Combat).
- **Range**: how far away, in hexes, the unit can attack. Range 1 means adjacent tiles only.

Roles in short: **infantry** is tough and slow, **cavalry** is fast and hits hard but is fragile, **rocket artillery** hits from up to 5 hexes away but dies quickly if the enemy reaches it.

Every unit has a small tag above it: a coloured tab for its side (blue for Poland, red for Russia), a short name (INF, CAV, ART) and an HP bar that turns from green to yellow to red as the unit loses HP.

## 5. The map and terrain

| Terrain | Movement cost | Defense bonus |
|---|---|---|
| Plains | 1 | +0 |
| Forest | 2 | +1 |
| Hills | 2 | +2 |
| Water | impassable | – |

- The **movement cost** is paid when a unit enters the tile.
- The **defense bonus** is added to the defense of a unit standing on that tile when it is hit.
- Every tile also has an **elevation**, shown in metres in the terrain panel. Elevation has **no effect on the rules** yet; only the terrain type matters.

## 6. Movement

- Select one of your units and click a tile to move there. The unit walks the cheapest path and the cost is taken from its movement points.
- A unit can move several times in one turn as long as it has points left.
- A unit cannot enter **water** and cannot enter or pass through a tile with **any other unit** on it, friend or enemy.
- Moving next to an enemy does not stop you; there are no zones of control.
- **After a unit attacks, it can't move any more this turn.** Move first, then attack.

When a unit is selected, the tiles it can reach are tinted in your side's colour. Hovering a reachable tile shows the path as a line of dots, and the terrain panel shows the path cost, e.g. `2 / 3 MP` (cost / movement points left).

## 7. Combat

### Attacking

- Any of your units can attack **one enemy unit per turn** that is within its range (counted in hexes, from 1 up to its range).
- Range is not blocked by terrain, water or other units.
- You can attack without moving, or move first and then attack. Attacking ends the unit's movement for the turn.
- When a unit is selected, enemies it can attack right now are marked in red. Click one to attack it.

### Damage

There are no dice: the result of an attack is always the same and can be worked out in advance.

**Damage = attacker's Attack − (defender's Defense + defense bonus of the defender's tile), but at least 1.**

The attacker's own tile doesn't matter.

### Counterattack

If the defender **survives** and the attacker is **within the defender's own range**, the defender immediately hits back once, with the same formula (now the original attacker's tile gives the defense bonus).

- A counterattack doesn't use up the defender's attack or movement. A unit counterattacks **every** attack it survives, any number of times per turn.
- A counterattack never triggers another counterattack.
- A counterattack can destroy the attacker.
- Melee units (range 1) can't hit back at rocket artillery that fires from 2 or more hexes away. Rocket artillery has no minimum range: it can also fire at an adjacent enemy (which then counterattacks), and it counterattacks anything that attacks it from up to 5 hexes away.

### Worked example

Your Cavalry (Attack 5, on plains) attacks an enemy Infantry (Defense 3) standing in a **forest** (+1).

1. Your hit: 5 − (3 + 1) = **1** damage. The infantry goes from 10 to 9 HP.
2. The infantry survived and your cavalry is adjacent (within range 1), so it hits back: 4 − (2 + 0) = **2** damage. Your cavalry goes from 8 to 6 HP.

The same attack on infantry standing on plains would deal 2 damage. Attacking units in good terrain is costly.

### Damage table

Damage dealt by the attacker to the defender, depending on the defender's tile (plains / forest / hills):

| Attacker → Defender | Infantry | Cavalry | Rocket Artillery |
|---|---|---|---|
| Infantry (Attack 4) | 1 / 1 / 1 | 2 / 1 / 1 | 3 / 2 / 1 |
| Cavalry (Attack 5) | 2 / 1 / 1 | 3 / 2 / 1 | 4 / 3 / 2 |
| Rocket Artillery (Attack 5) | 2 / 1 / 1 | 3 / 2 / 1 | 4 / 3 / 2 |

## 8. Victory and defeat

- As soon as one side has no units left, the other side wins. This can also happen through a counterattack.
- A banner shows **VICTORY** or **DEFEAT**. After that no more orders are accepted. To play again, restart the game.
- There are no draws and no other victory conditions.

## 9. The opponent

Russia is played by a simple computer opponent that follows the same rules as you. Each turn, every one of its units moves towards the nearest of your units and attacks the weakest unit it can reach (the one with the fewest HP). Its rocket artillery tries to stay about 5 hexes away from your nearest unit, so it can fire without being hit back.

## 10. Screen

- **Top bar**: the turn number in the centre with the side whose turn it is ("MOVE: POLAND"). On each side: a badge with the side's short code (PL for Poland, RU for Russia), its name, its status (YOUR TURN / AI TURN / WAITING) and how many units it has left. The active side is highlighted.
- **Bottom right**: **READY UNITS** (your units that can still do something / all your units) and the **End turn** button. The button is greyed out while animations play and during the enemy turn.
- **Unit card**: hover any unit (yours or the enemy's) to see its type, side, HP, Attack, Defense, Moves (left / per turn) and Range. Defense includes the terrain bonus of its tile, e.g. `5 (3+2)` on hills. The status line says "Ready", "Ready · already attacked", "Done this turn" or "Enemy unit".
- **Terrain panel** (bottom left): the hovered tile's terrain, hex position (column·row), movement cost, defense bonus and elevation, plus the path cost when you have a unit selected and the tile is reachable.
- **Done units**: a unit that can neither move nor attack any more this turn has a dimmed tag.
- **Rocket artillery range**: selecting your rocket artillery outlines all tiles within its range in amber. With nothing selected, hovering any rocket artillery (yours or the enemy's) shows its range, so you can see where it can hit.

## 11. Controls

| Action | Control |
|---|---|
| Select your unit | Left-click it |
| Move the selected unit | Left-click a highlighted tile |
| Attack with the selected unit | Left-click a red-marked enemy |
| Deselect | Right-click, or Esc |
| End turn | Enter, or the End turn button |
| Pan the camera | Left-drag, or W A S D / arrow keys |
| Rotate the camera | Right-drag, or Q / E |
| Zoom | Mouse wheel (the camera tilts lower as you zoom in) |
| Save the match record | F5 |

- Clicks on tiles you can't move to and enemies you can't attack are ignored.
- While animations are playing or the enemy is moving, clicks and keys (except camera controls and F5) are ignored, not queued.
- **F5** saves a record of the match so far (the moves made, for reporting bugs); the game also does this automatically when the battle ends. There is no way to load a saved match in the game yet.

## 12. Not in the game yet

To avoid confusion – these are **not** part of the current game: fog of war (you always see all enemy units), healing or repairing, line of sight, elevation effects, ammunition, unit experience, different maps or armies, a menu, and saving/loading a match to continue later.
