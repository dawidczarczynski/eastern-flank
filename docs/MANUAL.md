# Eastern Flank – Player's Manual

> This manual covers the game **as it plays today** (an early prototype). It is updated whenever a rule, unit or control changes.

## 1. Overview

Eastern Flank is a turn-based tactical battle on a hex map. You command **Poland** (blue) against **Russia** (red), which the computer plays. Poland starts with four units, Russia with five. (In the Polish version of the game the sides are called "Polska" and "Rosja".)

The two sides field different, real-world equipment with its own stats: Poland has fewer but stronger units, Russia has more of them. Both sides follow exactly the same rules. You and the opponent take turns moving and attacking.

**Goal:** destroy every enemy unit. The last side with units left on the map wins.

## 2. The battle

- The map is **12 × 10 hexes**. It is the same map every time you start the game.
- Poland starts on one short edge of the map, Russia on the opposite edge. Every unit starts on a plains tile.
- The starting armies:

  | Side | Unit | Count | Position |
  |---|---|---|---|
  | Poland (left) | Mechanised Infantry Squad | 2 | front line |
  | Poland (left) | M1A2 SEPv3 Abrams (tank) | 1 | front line, between the two squads |
  | Poland (left) | Homar-K (rocket artillery) | 1 | behind the Abrams, on the map edge |
  | Russia (right) | Motor Rifle Squad | 2 | front line |
  | Russia (right) | T-72B3 (tank) | 2 | front line, alternating with the squads (squad, tank, squad, tank) |
  | Russia (right) | 9K57 Uragan (rocket artillery) | 1 | behind the first T-72B3, on the map edge |

## 3. Turn structure

1. **Poland (you) always moves first.** During your turn you can give orders to all your units, in any order.
2. When you are done, end your turn. The turn bar shows "AI TURN" and Russia acts. Its moves and attacks are replayed as animations (sped up if there are many, so the enemy turn takes only a few seconds).
3. Then it is your turn again, and the **turn counter** goes up by one. A banner in the middle of the screen announces each new turn and side.

At the start of a side's turn, all of its units get their full movement points back and may attack again. Points you don't use are not saved for later.

There is no turn limit.

## 4. Units

| Unit | HP | Movement | Attack | Defense | Range | Look on the map |
|---|---|---|---|---|---|---|
| Mechanised Infantry Squad (Poland) | 10 | 3 | 4 | 3 | 1 | a squad of soldiers |
| Motor Rifle Squad (Russia) | 10 | 3 | 4 | 3 | 1 | a squad of soldiers |
| M1A2 SEPv3 Abrams (Poland) | 10 | 5 | 7 | 4 | 1 | an Abrams tank |
| T-72B3 (Russia) | 8 | 5 | 6 | 4 | 1 | a T-72 tank |
| Homar-K (Poland) | 6 | 3 | 6 | 1 | 6 | a Homar-K truck with a turning rocket launcher |
| 9K57 Uragan (Russia) | 6 | 3 | 6 | 1 | 5 | a BM-27 truck with sixteen rocket tubes over the cab |

- **HP**: how much damage the unit can take. At 0 HP it is destroyed and removed from the map. HP doesn't come back.
- **Movement**: movement points per turn (see Movement).
- **Attack** / **Defense**: used in the damage calculation (see Combat).
- **Range**: how far away, in hexes, the unit can attack. Range 1 means adjacent tiles only.

Roles in short: **infantry squads** are tough and slow but barely scratch a tank; **tanks** are fast, well armoured and hit hard – the Abrams is stronger and tougher than the T-72B3, which is why Russia brings two; **rocket artillery** hits from a distance (Homar-K up to 6 hexes, Uragan up to 5) but dies quickly if the enemy reaches it. The two squads have the same stats.

Every unit has a small tag above it: a coloured tab for its side (blue for Poland, red for Russia), a short name – **INF** for the infantry squads (PIECH in the Polish version), the real designation for vehicles (**M1A2**, **HOMAR**, **T-72B3**, **BM-27**) – and an HP bar that turns from green to yellow to red as the unit loses HP.

The units themselves wear their army's camouflage: Polish vehicles and soldiers in olive green, brown and black, Russian ones in green, near-black and sand.

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

When a unit is selected, the area it can reach is outlined in your side's colour and the rest of the map is slightly darkened. Hovering a reachable tile tints it and shows the path as a line of dots, and the terrain panel shows the path cost, e.g. `2 / 3 MP` (cost / movement points left).

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
- Melee units (range 1) can't hit back at rocket artillery that fires from 2 or more hexes away. Rocket artillery has no minimum range: it can also fire at an adjacent enemy (which then counterattacks), and it counterattacks anything that attacks it from within its own range (Homar-K up to 6 hexes, Uragan up to 5).
- The Homar-K outranges the Uragan by one hex: fired from exactly 6 hexes away, the Uragan can't hit back.

### Worked examples

Your Abrams (Attack 7, Defense 4, on plains) attacks an enemy T-72B3 (Attack 6, Defense 4) on **plains** (+0).

1. Your hit: 7 − (4 + 0) = **3** damage. The T-72B3 goes from 8 to 5 HP.
2. The T-72B3 survived and your Abrams is adjacent (within range 1), so it hits back: 6 − (4 + 0) = **2** damage. Your Abrams goes from 10 to 8 HP.

Your Abrams attacks an enemy Motor Rifle Squad (Attack 4, Defense 3) standing in a **forest** (+1).

1. Your hit: 7 − (3 + 1) = **3** damage. The squad goes from 10 to 7 HP.
2. The squad hits back: 4 − (4 + 0) = 0, raised to the minimum of **1** damage. Your Abrams goes from 10 to 9 HP.

The same attack on a squad standing on plains would deal 4 damage, on hills only 2. Attacking units in good terrain is costly.

Your Homar-K (Attack 6) fires at the Uragan (Defense 1) on plains from 6 hexes away: 6 − (1 + 0) = **5** damage (6 to 1 HP), and the Uragan can't hit back because it has range 5.

### Damage table

Damage dealt by the attacker to the defender, depending on the defender's tile (plains / forest / hills). The two squads have the same stats, and so do the two tanks' Defense and the two rocket launchers' Attack and Defense, so they share a row or column:

| Attacker → Defender | Infantry squad (Def 3) | Abrams / T-72B3 (Def 4) | Homar-K / Uragan (Def 1) |
|---|---|---|---|
| Infantry squad (Attack 4) | 1 / 1 / 1 | 1 / 1 / 1 | 3 / 2 / 1 |
| M1A2 SEPv3 Abrams (Attack 7) | 4 / 3 / 2 | 3 / 2 / 1 | 6 / 5 / 4 |
| T-72B3 (Attack 6) | 3 / 2 / 1 | 2 / 1 / 1 | 5 / 4 / 3 |
| Homar-K / Uragan (Attack 6) | 3 / 2 / 1 | 2 / 1 / 1 | 5 / 4 / 3 |

Remember that a unit's HP differ too: the Abrams and the squads have 10 HP, the T-72B3 8 and the rocket launchers 6. An Abrams destroys a rocket launcher on plains in one hit.

## 8. Victory and defeat

- As soon as one side has no units left, the other side wins. This can also happen through a counterattack.
- A banner shows **VICTORY** or **DEFEAT**. After that no more orders are accepted. To play again, restart the game.
- There are no draws and no other victory conditions.

## 9. The opponent

Russia is played by a simple computer opponent that follows the same rules as you. Each turn, every one of its units moves towards the nearest of your units and attacks the weakest unit it can reach (the one with the fewest HP). Its rocket artillery tries to stay at its full range from your nearest unit (5 hexes for the Uragan), so it can fire without being hit back.

## 10. Screen

- **Top bar**: a bar hanging from the top edge, with a tick ruler under it. The turn number is in the centre, with the side whose turn it is ("▸ POLAND"). On each side: a hexagonal badge with the side's short code (PL for Poland, RU for Russia), its name, its status (ACTIVE / WAITING) and how many units it has. The active side is lit and has a hatched bar under it in its colour; the waiting side is dimmed.
- **Bottom right**: a row of key hints (only keys the game has, see Controls), the **READY** counter (your units that can still do something / all your units, one block per unit: filled = can still act) and the **End turn** button in your side's colour. The button is greyed out while animations play and during the enemy turn.
- **Unit card**: hover any unit (yours or the enemy's) to see a lit 3D portrait of it in its side's camouflage (rendered once per unit type and side at the start of the battle), then its class (Infantry, Tank or Rocket Artillery) with the unit's real name below it (e.g. M1A2 SEPv3 Abrams). In the Polish version the class and the squad names are translated (Drużyna piechoty zmechanizowanej, Drużyna zmotoryzowana); vehicle names stay as they are. The card also shows the unit's side, HP, Attack, Defense, Moves (left / per turn) and Range. Defense includes the terrain bonus of its tile, e.g. `5 (3+2)` on hills. The status line says "Ready", "Ready · already attacked", "Done this turn" or "Enemy unit".
- **Terrain panel** (bottom left): the hovered tile's terrain, hex position (column·row), movement cost, defense bonus and elevation, plus the path cost when you have a unit selected and the tile is reachable.
- **Selection**: selecting a unit outlines the area it can reach in your colour and slightly darkens the rest of the map; the tile under the cursor is tinted when the unit can move there. Water is never darkened, and unreachable tiles inside the area (such as a lake) get their own outline.
- **Beyond the map edge**: the land around the map (a little greyer and paler, with trees on HIGH graphics) is scenery only. You can't hover or click tiles there, units can't go there, and the camera can't be panned off the map.
- **Hex grid**: a faint light grid marks the hexes on land (not over water). It fades as you zoom out and is a little stronger while a unit is selected. Press **G** to hide or show it.
- **Done units**: a unit that can neither move nor attack any more this turn has a dimmed tag.
- **Rocket artillery range**: selecting your rocket artillery outlines all tiles within its range in amber. With nothing selected, hovering any rocket artillery (yours or the enemy's) shows its range, so you can see where it can hit.
- **Ground marks**: tanks leave dark tread marks and rocket artillery trucks thinner tyre marks behind them as they move, rocket strikes leave small craters and a scorched patch around the target, and a destroyed unit leaves a scorched patch on its tile. They are only decoration – they don't change movement or defense. Old marks fade away to make room for new ones (fewer are kept on LOW graphics).
- **Wrecks and smoke**: a destroyed vehicle (tank or rocket artillery truck) leaves a burnt-out wreck on its tile, standing on a wide patch of black burnt ground where no plants grow (rocks are blackened with soot), with its turret or launcher knocked askew, and a column of smoke rises from it. Smoke is shown on HIGH graphics only. It thins after the first turn start and stops after the third (each player's turn start counts), but the wreck stays. Destroyed infantry leave only the scorched patch, no wreck. Wrecks are scenery only: they don't block movement, give no cover, and can't be selected or attacked. A wreck fades away when a unit ends its move on its tile; a unit that only passes through the tile leaves it standing.

- **Graphics**: the game picks a graphics quality by itself when it starts. On a computer with a real graphics card it uses **HIGH** (full look). On software or compatibility rendering (for example a virtual machine or WSL without GPU) it uses **LOW**: no trees, bushes or rocks (forests and other terrain show only by the ground colour), no shadows, no ambient occlusion or edge smoothing (MSAA), and the 3D view rendered at half resolution, so the game stays playable. The chosen level is printed in the console as "Graphics quality: …". There is no settings screen. To force a level, start the game with `--quality=low` or `--quality=high` (for example `tools/run.sh --quality=low`, or `tools/run_windows.sh --quality=high`).

## 11. Controls

| Action | Control |
|---|---|
| Select your unit | Left-click it |
| Move the selected unit | Left-click a tile inside the outlined area |
| Attack with the selected unit | Left-click a red-marked enemy |
| Deselect | Right-click, or Esc |
| End turn | Enter, or the End turn button |
| Pan the camera | Left-drag, or W A S D / arrow keys |
| Rotate the camera | Right-drag, or Q / E |
| Zoom | Mouse wheel (the camera tilts toward the horizon as you zoom in and looks almost straight down when zoomed out; it never dips below the ground) |
| Tilt the camera | Ctrl + mouse wheel (wheel up tilts toward the horizon; does not zoom), hold R (toward the horizon) / F (toward top-down), or middle-drag up / down (drag down tilts toward top-down). Your tilt is added on top of the automatic zoom tilt, up to about 20° either way, and stays for the rest of the match; the camera never dips below the ground |
| Reset the tilt | Home (the camera smoothly returns to the default tilt) |
| Show / hide the hex grid | G (the grid fades as you zoom out) |
| Save the match record | F5 |

- Clicks on tiles you can't move to and enemies you can't attack are ignored.
- While animations are playing or the enemy is moving, clicks and keys (except camera controls, G and F5) are ignored, not queued.
- **F5** saves a record of the match so far (the moves made, for reporting bugs); the game also does this automatically when the battle ends. There is no way to load a saved match in the game yet. Match records saved by earlier versions of the game (before the real Polish and Russian units) can no longer be replayed: they are refused with a clear "unsupported match record version" message instead of replaying a different battle.

## 12. Not in the game yet

To avoid confusion – these are **not** part of the current game: fog of war (you always see all enemy units), healing or repairing, line of sight, elevation effects, ammunition, unit experience, vehicles carrying the infantry squads, different maps, choosing your country or army, a menu, and saving/loading a match to continue later.
