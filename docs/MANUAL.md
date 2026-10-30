# Eastern Flank – Player's Manual

> This manual covers the game **as it plays today** (an early prototype). It is updated whenever a rule, unit or control changes.

## 1. Overview

Eastern Flank is a turn-based tactical battle on a hex map. You command **Poland** (blue) against **Russia** (red), which the computer plays. Poland starts with four units, Russia with five. (In the Polish version of the game the sides are called "Polska" and "Rosja".)

The two sides field different, real-world equipment with its own stats: Poland has fewer but stronger units, Russia has more of them. Both sides follow exactly the same rules. You and the opponent take turns moving and attacking.

**Goal:** every battle has its own victory conditions and may have a turn limit (see section 8). In the normal battle the goal is to destroy every enemy unit: the last side with units left on the map wins, and there is no turn limit. A second, objective battle (a debug option for now) is about taking and holding two marked hexes within 8 turns.

The game opens in a main menu, where you start the battle, pick the language or browse the units in the unit catalog (see section 12).

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

The normal battle has no turn limit. A battle with a turn limit (such as the objective battle, limit 8) ends after the last side – Russia – finishes its turn of the final turn; see section 8.

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

Each battle sets its own victory conditions and, optionally, a turn limit. The game has two battles: the **normal battle** (what **Start operation** starts) and the **objective battle**.

### Ways to win

- **Eliminate the enemy**: as soon as one side has no units left, the other side wins at once. This can also happen through a counterattack. Both battles have this condition for both sides.
- **Take the objectives**: if, when you **end your own turn**, one of your units stands on **every** objective hex of the condition, you win at once. It has to be all of them at the same moment, and it is checked only at the end of your own turn – not during it and not during the enemy's turn.
- **Hold the objectives**: when the turn limit is reached, a side whose condition is to hold the objective hexes wins if it **holds** all of them at that moment (see "Holding a hex" below). Nobody needs to be standing on them.
- **Destroy a share of the enemy**: a battle can also be won at once by destroying a set share of the enemy's starting total HP (e.g. half). Neither of the current battles uses this condition.

### Holding a hex

- Each objective hex is **held** by one side. At the start the battle decides who holds it.
- A hex changes hands when a unit **ends a move** on it. Passing through a hex on the way somewhere else does not capture it, and neither does attacking a unit standing on it.
- The hex stays with the last side that ended a move on it, even after that unit moves away or is destroyed, until an enemy unit ends a move there.
- Holding and standing on are different: "take" needs your units standing on the hexes at the end of your turn; "hold" only needs the hexes to be yours when the turn limit runs out.

### Turn limit and draws

- With a turn limit, the battle ends when the last side (Russia) finishes its turn of the final turn. Poland therefore gets its last turn first, then Russia gets its last turn.
- At that moment, if exactly one side meets its hold condition, it wins. Otherwise the battle is a **draw**.
- The normal battle has no turn limit, so it can't end in a draw.

### The objective battle

- Same map, armies and starting positions as the normal battle, with a **turn limit of 8**.
- Two **objective hexes** lie on Russia's side of the river, just past its two fords. **Russia holds both** at the start.
- **Poland (you)** wins by having units standing on **both** objective hexes at the end of one of your turns, or by eliminating every Russian unit.
- **Russia** wins by still holding **both** hexes when turn 8 ends, or by eliminating every Polish unit.
- Anything else when turn 8 ends – for example Poland has taken one hex, or holds both but no longer stands on both – is a **draw**.
- To play it, start the game with `--scenario=objective_battle` (for example `tools/run_windows.sh --scenario=objective_battle` or `tools/run.sh --scenario=objective_battle`), then pick **Start operation**. Without the option you get the normal battle.

### The end of the battle

- A banner shows **VICTORY**, **DEFEAT** or **DRAW**, the turn it ended on (e.g. "TURN 05", or "TURN 05 / 08" in a battle with a turn limit) and why it ended:

  | Why | Your victory | Your defeat or a draw |
  |---|---|---|
  | All enemy units destroyed | ENEMY ELIMINATED | OUR FORCES ELIMINATED |
  | A share of the enemy destroyed | ENEMY DESTROYED | OUR FORCES DESTROYED |
  | Objectives taken | OBJECTIVES TAKEN | OBJECTIVES LOST |
  | Turn limit | TURN LIMIT REACHED | TURN LIMIT REACHED |

- An attack that ends the battle is not answered by a counterattack.
- After the banner no more orders are accepted. To play again, restart the game.

## 9. The opponent

Russia is played by a simple computer opponent that follows the same rules as you. Each turn, every one of its units moves towards the nearest of your units and attacks the weakest unit it can reach (the one with the fewest HP). Its rocket artillery tries to stay at its full range from your nearest unit (5 hexes for the Uragan), so it can fire without being hit back.

In the objective battle it also minds the objective hexes: a unit standing on one stays there (it still attacks whatever it can reach), and a unit whose nearest objective hex without a Russian unit on it is no farther away than your nearest unit heads for that hex instead of for you.

## 10. Screen

- **Top bar**: a bar hanging from the top edge, with a tick ruler under it. The turn number is in the centre (e.g. "01"; in a battle with a turn limit followed by the limit in smaller type, e.g. "01/08"), with the side whose turn it is ("▸ POLAND"). On each side: a hexagonal badge with the side's short code (PL for Poland, RU for Russia), its name, its status (ACTIVE / WAITING) and how many units it has. The active side is lit and has a hatched bar under it in its colour; the waiting side is dimmed.
- **Bottom right**: a row of key hints (only keys the game has, see Controls), the **READY** counter (your units that can still do something / all your units, one block per unit: filled = can still act) and the **End turn** button in your side's colour. The button is greyed out while animations play and during the enemy turn.
- **Unit card**: hover any unit (yours or the enemy's) to open its card next to the cursor (it moves to the left of the cursor near the right screen edge, and always stays below the top bar). The card is framed in the unit's side colour. From top to bottom:
  - **Tab**: the unit's class (INFANTRY, TANK or ROCKET ARTILLERY) on the left and its side (POLAND / RUSSIA) on the right.
  - **Name**: the unit's real name in capitals (e.g. M1A2 SEPv3 ABRAMS), with its short designation in small grey type below it (M1A2, HOMAR, BM-27). Squads and the T-72B3 have no designation line, because it would only repeat the class or the name. In the Polish version the class and the squad names are translated (Drużyna piechoty zmechanizowanej, Drużyna zmotoryzowana); vehicle names stay as they are.
  - **Portrait**: a lit 3D picture of the unit in its side's camouflage (rendered once per unit type and side at the start of the battle), behind amber corner brackets and a crosshair. Until it is ready the box is plain dark.
  - **Strength**: HP as `current/max` and a row of slanted segments, one per maximum HP point. Lost points are empty; the remaining ones are green above 60 % HP, yellow above 35 % and red at 35 % or less.
  - **Stats**: Attack, Defense, Moves (left / per turn) and Range, each with its number and a short bar. Attack and Defense bars are full at 10, Moves and Range bars at 6. Defense includes the terrain bonus of the unit's tile, e.g. `5 (3+2)` on hills, and its bar shows that total.
  - **Mobility tag**: how the unit moves – FOOT (infantry), WHEELED (rocket artillery) or TRACKED (tanks). For now this is information only; all units pay the same movement costs.
  - **Status**: a small hexagon and a line saying READY (green), READY · ALREADY ATTACKED (green), DONE THIS TURN (grey) or ENEMY UNIT (in the enemy's colour).
- **Terrain panel** (bottom left): the hovered tile's terrain, hex position (column·row), movement cost, defense bonus and elevation, plus a `PATH · 2 / 5 MP` row (in your faction colour) when you have a unit selected and the tile is reachable. Above the panel, `■ OP. IRON SHORE` names the operation.
- **Selection**: selecting a unit outlines the area it can reach in your colour and slightly darkens the rest of the map; the tile under the cursor is tinted when the unit can move there. Water is never darkened, and unreachable tiles inside the area (such as a lake) get their own outline.
- **Beyond the map edge**: the land around the map (a little greyer and paler, with trees on HIGH graphics) is scenery only. You can't hover or click tiles there, units can't go there, and the camera can't be panned off the map.
- **Hex grid**: a faint light grid marks the hexes on land (not over water). It fades as you zoom out and is a little stronger while a unit is selected. Press **G** to hide or show it.
- **Objective hexes** (only in a battle that has them): each is outlined by a coloured ring along its edge, with a small flag on a pole near one corner and an **OBJECTIVE** tag above the flag (visible even over forest). Ring, flag and the tag's tab are in the colour of the side that holds the hex (red for Russia, blue for Poland) and change colour when the hex is captured.
- **Done units**: a unit that can neither move nor attack any more this turn has a dimmed tag.
- **Rocket artillery range**: selecting your rocket artillery outlines all tiles within its range in amber. With nothing selected, hovering any rocket artillery (yours or the enemy's) shows its range, so you can see where it can hit.
- **Ground marks**: tanks leave dark tread marks and rocket artillery trucks thinner tyre marks behind them as they move, rocket strikes leave small craters and a scorched patch around the target, and a destroyed unit leaves a scorched patch on its tile. They are only decoration – they don't change movement or defense. Old marks fade away to make room for new ones (fewer are kept on LOW graphics).
- **Rocket salvos**: rocket artillery fires its full salvo, one rocket after another: 12 rockets for the Homar-K, 16 for the Uragan. The target's HP bar drops as the rockets land. Smoke hangs over the target for a few seconds (on HIGH graphics only). The salvo is only for show: the damage is the same as for any other attack (see Combat). Its counterattacks are full salvos too. In the enemy turn most animations play much faster, but salvos are sped up to only 1.5× normal speed.
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

## 12. Main menu and unit catalog

The game opens in the main menu:

- **Start operation** starts the battle. There is no way back to the menu from a battle; restart the game for that.
- **Language** (the button shows the current one, e.g. "LANGUAGE: ENGLISH") switches between English and Polish (Polski) at once. The choice is saved and used the next time you start the game.
- **Unit catalog** opens a viewer where you can look at every unit in the game.

**Unit catalog.** The list on the left has every unit, grouped by class; a unit without a finished 3D model is marked `(!)` and shown as a simple placeholder. The selected unit stands on a ground disc in the middle. The panel on the right shows its name, its side (with buttons to switch sides when more than one army fields it, e.g. a squad in Polish or Russian colours), its class, how it moves, its HP, Attack, Defense, Moves and Range, and the model's size in metres.

Below that are the animation buttons. Each unit only gets the ones it has:

| Button | Units | What it shows |
|---|---|---|
| Drive | vehicles | the unit drives on the spot, wheels or tracks turning (on/off) |
| March / Kneel / stand | infantry squads | the soldiers march (on/off); kneel down or stand up |
| Deploy | rocket artillery | stabiliser jacks down (Uragan: also the blast shields closed over the cab windows) (on/off) |
| Raise launcher / Traverse | rocket artillery | raises the launcher, turns it to the side (on/off) |
| Fire | rocket artillery | the full battle salvo at a target post: deploy, raise, turn, fire, then everything back to travel position |
| Hit / Death | all | the hit reaction and the destruction (a vehicle leaves its burnt wreck) |
| Reset | all | rebuilds the model in its normal state, e.g. after Death |
| Auto-rotate | all | slowly turns the camera around the unit (on/off) |

While Deploy, Raise launcher, Traverse or Fire is running, the other pose buttons are greyed out. Fire is only available when the launcher is in travel position (Deploy, Raise launcher and Traverse all off). After Death, only Reset brings the unit back.

| Action (catalog) | Control |
|---|---|
| Rotate around the unit | Left-drag (up and down tilts the view, within limits) |
| Zoom | Mouse wheel |
| Reset the view | Double-click, or Home |
| Back to the main menu | Esc, or the ‹ Back button |

## 13. Not in the game yet

To avoid confusion – these are **not** part of the current game: fog of war (you always see all enemy units), healing or repairing, line of sight, elevation effects, ammunition, unit experience, vehicles carrying the infantry squads, different maps, choosing your country or army, choosing the battle in the menu (the objective battle is only a start option), victory points, an options or graphics settings menu, and saving/loading a match to continue later.
