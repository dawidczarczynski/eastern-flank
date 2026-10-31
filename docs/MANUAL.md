# Eastern Flank – Player's Manual

> This manual covers the game **as it plays today** (an early prototype). It is updated whenever a rule, unit or control changes.

## 1. Overview

Eastern Flank is a turn-based tactical battle on a hex map. You command **Poland** (blue) against **Russia** (red), which the computer plays. Poland starts with four units, Russia with five. (In the Polish version of the game the sides are called "Polska" and "Rosja".)

The two sides field different, real-world equipment with its own stats: Poland has fewer but stronger units, Russia has more of them. Both sides follow exactly the same rules. You and the opponent take turns moving and attacking.

**Goal:** every battle has its own victory conditions and may have a turn limit (see section 8). In the normal battle the goal is to destroy every enemy unit: the last side with units left on the map wins, and there is no turn limit. A second, objective battle (a debug option for now) is about taking and holding two marked hexes within 8 turns.

The game opens in a main menu, where you start the battle, pick the scenario, pick the language or browse the units in the unit catalog (see section 12).

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

### Command points

Some battles limit how many units each side can command per turn. The normal battle and the objective battle have **no limit**: every unit can act every turn.

- In a limited battle a side gets **N command points** at the start of each of its turns (unused points are not saved).
- A unit's **first move or attack of the turn costs 1 point** – it "activates" the unit. Everything else that unit does this turn (further moves, its attack) is free.
- **Counterattacks never cost points.**
- With 0 points left, a unit that has not acted yet this turn can't move or attack; trying it shows "NO COMMAND POINTS LEFT THIS TURN". Units already activated keep acting normally.
- The turn bar shows the points left, e.g. `C2 1/2` (see Screen).
- To try it, start the game with `--scenario=command_points_battle` (for example `tools/run.sh --scenario=command_points_battle`), then pick **Start operation**: the normal battle with **N = 2** for both sides. It is a test battle; later, an operation's battle conditions will set N.

## 4. Units

| Unit | HP | Movement | Attack | Defense | Range | Look on the map |
|---|---|---|---|---|---|---|
| Mechanised Infantry Squad (Poland) | 10 | 3 | 4 | 3 | 1 | a squad of soldiers |
| Motor Rifle Squad (Russia) | 10 | 3 | 4 | 3 | 1 | a squad of soldiers |
| M1A2 SEPv3 Abrams (Poland) | 10 | 5 | 7 | 4 | 1 | an Abrams tank |
| T-72B3 (Russia) | 8 | 5 | 6 | 4 | 1 | a T-72 tank |
| Homar-K (Poland) | 6 | 3 | 6 | 1 | 6 | a Homar-K truck with a turning rocket launcher |
| 9K57 Uragan (Russia) | 6 | 3 | 6 | 1 | 5 | a BM-27 truck with sixteen rocket tubes over the cab |

- **HP**: the unit's strength – how much damage it can take, and how many shots it fires (see Combat). Every unit is a company: a unit that has lost HP also fights worse, because it fires fewer shots. At 0 HP it is destroyed and removed from the map. HP doesn't come back.
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

### Maps from real terrain

Battles are meant to be fought on the real ground of the eastern flank. A real-terrain map is built from open map data: forests, lakes and open ground come from OpenStreetMap, heights from the Copernicus elevation model. Each hex is about **250 m** across; a battle map of 30 × 24 hexes covers roughly 7.5 × 5 km.

- A hex takes the terrain that covers most of it: mostly lake → **water**, mostly forest → **forest**, otherwise open ground; open ground that rises or falls steeply within the hex (15 m or more) is **hills**. Villages, fields and marshes count as plains for now.
- On a real-terrain map the terrain panel shows the hex's **real height above sea level**. The 3D relief is drawn 1.5 × taller than reality so that hills read on screen, and every lake sits at the same water level.
- To try it, start the game with `--scenario=suwalki_battle` (for example `tools/run.sh --scenario=suwalki_battle`), then pick **Start operation**: the usual forces on the lakes and moraine hills around **Szurpiły** in the Suwałki Landscape Park (north-east Poland). Poland deploys in the west, Russia in the east; the usual objectives and win conditions apply (see the battle rules).
- Map data © OpenStreetMap contributors (ODbL), elevation © DLR e.V. / Airbus Defence and Space, provided under Copernicus by the European Union and ESA. Full credits: `data/maps/CREDITS`.

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
- When a unit is selected, enemies it can attack right now are marked in red. Click one to attack it at once.
- Hovering a red-marked enemy turns the cursor into an amber crosshair and shows a small **attack tag** beside it: your expected damage, the chance to destroy the target and its expected counterattack, so you don't have to work out the odds below by hand.
- **Right-click any enemy** to open the **unit ring** around it: its ATTACK action shows the full forecast and lets you attack from there, or tells you why you can't. See Screen for both.

### Damage

An attack is a roll of dice: you know the odds, never the exact result.

1. **Hit number** = attacker's Attack − (defender's Defense + defense bonus of the defender's tile), but at least 1. The attacker's own tile doesn't matter.
2. The attacker fires **one shot per HP it has right now**. Each shot rolls a die with as many faces as the attacker's **full** HP (a d10 for the squads and the Abrams, a d8 for the T-72B3, a d6 for the rocket launchers).
3. A roll **at or below the hit number** is a hit. **Damage = number of hits.** The defender loses that many HP (it can't go below 0).

So the hit chance of each shot is the hit number out of the attacker's full HP – for example an Abrams with hit number 3 hits on 1–3 of a d10, 30 % per shot.

What this means:

- A unit at **full strength deals on average exactly the hit number** (the damage table below). A unit at half its HP fires half the shots and deals half as much on average.
- **An attack can deal 0 damage.** With a hit number of 1, about one attack in three misses completely (e.g. a squad attacking a tank). Such an attack plays out normally, the target just loses no HP; there is no separate "miss" message.
- An attack can never deal more damage than the attacker has HP (one hit per shot at most).
- A unit can only be destroyed in one attack if the attacker fires at least as many shots as the target has HP left, and the more the attacker has to spare, the likelier it is. Against a full squad even a full Abrams has only a tiny chance (all ten shots must hit: about 1 in 10,000); against a full rocket launcher (6 HP) on plains it succeeds 63 % of the time.

### Counterattack

If the defender **survives** and the attacker is **within the defender's own range**, the defender immediately hits back once, with the same roll (now the original attacker's tile gives the defense bonus). It fires **only with the HP it has left after your attack**, so a defender you have hurt hits back weaker – striking first pays off.

- A counterattack doesn't use up the defender's attack or movement. A unit counterattacks **every** attack it survives, any number of times per turn.
- A counterattack never triggers another counterattack.
- A counterattack can destroy the attacker.
- Melee units (range 1) can't hit back at rocket artillery that fires from 2 or more hexes away. Rocket artillery has no minimum range: it can also fire at an adjacent enemy (which then counterattacks), and it counterattacks anything that attacks it from within its own range (Homar-K up to 6 hexes, Uragan up to 5).
- The Homar-K outranges the Uragan by one hex: fired from exactly 6 hexes away, the Uragan can't hit back.

### Worked examples

Your Abrams (Attack 7, Defense 4, on plains) attacks an enemy T-72B3 (Attack 6, Defense 4) on **plains** (+0).

1. Your hit number: 7 − (4 + 0) = **3**. Your Abrams fires 10 shots with a d10, each hitting on 1–3 (30 %). On average **3** damage, usually 1 to 5 (only about 3 % of attacks miss completely); the T-72B3 goes from 8 HP to about 5.
2. If the T-72B3 survives (it almost always does), it hits back, because your Abrams is adjacent (within range 1): hit number 6 − (4 + 0) = **2** on a d8 (25 % per shot), one shot per HP it has left. With about 5 HP left that is **1.25** damage on average; about a quarter of the time it doesn't hit at all.
3. The attack tag sums this up as `ATTACK ~3.0 (1–5)`, `DESTROY <1 %`, `COUNTER ~1.3`; the unit ring's ATTACK card also gives the counter's range, `COUNTER 1.3 (0–3)`.

Your Abrams attacks an enemy Motor Rifle Squad (Attack 4, Defense 3) standing in a **forest** (+1).

1. Your hit number: 7 − (3 + 1) = **3**: on average **3** damage, usually 1 to 5. The squad goes from 10 HP to about 7.
2. The squad hits back: 4 − (4 + 0) = 0, raised to the minimum hit number of **1**, so each of its remaining shots hits on a 1 of a d10. On average **0.7** damage to your Abrams; about half the time nothing.

The same attack on a squad standing on plains would deal 4 damage on average, on hills only 2. Attacking units in good terrain is costly.

Your Homar-K (Attack 6) fires at the Uragan (Defense 1) on plains from 6 hexes away: hit number 6 − (1 + 0) = **5**, six shots with a d6, each hitting on 1–5. On average **5** damage, usually 4 to 6, and a 33 % chance that all six hit and the Uragan is destroyed. The Uragan can't hit back because it has range 5. Attack tag: `ATTACK ~5.0 (4–6)`, `DESTROY 33 %`, `NO COUNTER`.

### Damage table

The hit number of the attacker against the defender, depending on the defender's tile (plains / forest / hills). It is also the **average damage of a full-strength attacker**; a weakened attacker deals the same share of it as the share of HP it has left (an Abrams at 5 of 10 HP: half). The two squads have the same stats, and so do the two tanks' Defense and the two rocket launchers' Attack and Defense, so they share a row or column:

| Attacker → Defender | Infantry squad (Def 3) | Abrams / T-72B3 (Def 4) | Homar-K / Uragan (Def 1) |
|---|---|---|---|
| Infantry squad (Attack 4) | 1 / 1 / 1 | 1 / 1 / 1 | 3 / 2 / 1 |
| M1A2 SEPv3 Abrams (Attack 7) | 4 / 3 / 2 | 3 / 2 / 1 | 6 / 5 / 4 |
| T-72B3 (Attack 6) | 3 / 2 / 1 | 2 / 1 / 1 | 5 / 4 / 3 |
| Homar-K / Uragan (Attack 6) | 3 / 2 / 1 | 2 / 1 / 1 | 5 / 4 / 3 |

The spread around the average, for a full-strength attacker:

- Most attacks (8 in 10) land within about 2 of the average: an average of 4 means usually 2–6, an average of 1 usually 0–2.
- An entry of **1** deals nothing in about one attack in three; an entry of **2** in about one in ten; an entry of 3 or more only rarely (3 % or less).

Remember that a unit's HP differ too: the Abrams and the squads have 10 HP, the T-72B3 8 and the rocket launchers 6. A full Abrams destroys a full rocket launcher on plains in one attack 63 % of the time (in forest about 38 %, on hills about 17 %).

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

Russia is played by a simple computer opponent that follows the same rules as you. Each turn, every one of its units moves towards the nearest of your units and then attacks, if any of your units is in its range. It picks the attack with the best expected result: the average damage it deals, plus a bonus for the chance to destroy the target, minus the average damage it expects to take back in the counterattack. If two attacks are equally good, it attacks the unit with fewer HP. It always attacks when it can, even when the counterattack is expected to hurt more. Its rocket artillery tries to stay at its full range from your nearest unit (5 hexes for the Uragan), so it can fire without being hit back.

In the objective battle it also minds the objective hexes: a unit standing on one stays there (it still attacks whatever it can reach), and a unit whose nearest objective hex without a Russian unit on it is no farther away than your nearest unit heads for that hex instead of for you.

In a battle with command points it spends its points on its most valuable actions first: attacks (above all ones whose average damage would destroy a unit) before moves.

## 10. Screen

- **Top bar**: a bar hanging from the top edge, with a tick ruler under it. The turn number is in the centre (e.g. "01"; in a battle with a turn limit followed by the limit in smaller type, e.g. "01/08"), with the side whose turn it is ("▸ POLAND"). On each side: a hexagonal badge with the side's short code (PL for Poland, RU for Russia), its name, its status (ACTIVE / WAITING) and how many units it has. The active side is lit and has a hatched bar under it in its colour; the waiting side is dimmed. In a battle with command points, the active side's name has a `C2 remaining/N` line under it (e.g. `C2 1/2`); without a limit it is not shown.
- **Bottom right**: a row of key hints (only keys the game has, see Controls, e.g. `RMB ON UNIT – UNIT MENU`; in Polish `PPM NA JEDNOSTCE – MENU JEDNOSTKI`), the **READY** counter (your units that can still do something / all your units, one block per unit: filled = can still act; once your command points run out, units that have not acted no longer count as ready) and the **End turn** button in your side's colour. The button is greyed out while animations play and during the enemy turn.
- **Unit card**: shown only through the unit ring's **INFO** action (see Unit ring below) – hovering a unit on the map does not show it. It appears beside the ring and is framed in the unit's side colour. From top to bottom:
  - **Tab**: the unit's class (INFANTRY, TANK or ROCKET ARTILLERY) on the left and its side (POLAND / RUSSIA) on the right.
  - **Name**: the unit's real name in capitals (e.g. M1A2 SEPv3 ABRAMS), with its short designation in small grey type below it (M1A2, HOMAR, BM-27). Squads and the T-72B3 have no designation line, because it would only repeat the class or the name. In the Polish version the class and the squad names are translated (Drużyna piechoty zmechanizowanej, Drużyna zmotoryzowana); vehicle names stay as they are.
  - **Portrait**: a lit 3D picture of the unit in its side's camouflage (rendered once per unit type and side at the start of the battle), behind amber corner brackets and a crosshair. Until it is ready the box is plain dark.
  - **Strength**: HP as `current/max` and a row of slanted segments, one per maximum HP point. Lost points are empty; the remaining ones are green above 60 % HP, yellow above 35 % and red at 35 % or less.
  - **Stats**: Attack, Defense, Moves (left / per turn) and Range, each with its number and a short bar. Attack and Defense bars are full at 10, Moves and Range bars at 6. Defense includes the terrain bonus of the unit's tile, e.g. `5 (3+2)` on hills, and its bar shows that total.
  - **Mobility tag**: how the unit moves – FOOT (infantry), WHEELED (rocket artillery) or TRACKED (tanks). For now this is information only; all units pay the same movement costs.
  - **Status**: a small hexagon and a line saying READY (green), READY · ALREADY ATTACKED (green), DONE THIS TURN (grey) or ENEMY UNIT (in the enemy's colour).
- **Attack tag**: while one of your units is selected and you hover an enemy it can attack right now, the cursor becomes an amber crosshair and a small tag appears next to it. Anything else (your own unit, an enemy out of range, nothing selected) shows the normal cursor and nothing extra. The numbers follow the dice rules in Combat, including a weakened attacker firing fewer shots and the target's terrain:
  - `ATTACK ~3.0 (1–5)`: your attack's average damage and, in brackets, the range it lands in 8 times out of 10. It never exceeds the HP the target has left.
  - `DESTROY 63 %`: the chance your attack destroys the target outright. Shows `<1 %` or `>99 %` near the edges and `100 %` when certain; the line is left out when it is impossible (you fire fewer shots than the target has HP).
  - `COUNTER ~1.3`: the average damage of the enemy's counterattack, counting only the HP it would have left after your attack (a destroyed target doesn't hit back). `NO COUNTER` when your unit is outside the enemy's range, e.g. a Homar-K firing from 6 hexes at an Uragan.
  - Examples on plains, both units at full strength: Abrams → T-72B3 `ATTACK ~3.0 (1–5)`, `DESTROY <1 %`, `COUNTER ~1.3`; Abrams → Motor Rifle Squad `ATTACK ~4.0 (2–6)`, `DESTROY <1 %`, `COUNTER ~0.6`; Abrams → Uragan `ATTACK ~5.4 (4–6)`, `DESTROY 63 %`, `COUNTER ~0.2`; Homar-K → Uragan from 6 hexes `ATTACK ~5.0 (4–6)`, `DESTROY 33 %`, `NO COUNTER`.
- **Unit ring**: right-click (without dragging) any living unit – yours or the enemy's – during your turn to open a ring of six segments around it. It stays on the unit when you pan, rotate or zoom. Beside the ring is a card: with nothing hovered it shows the unit's name and Strength under a UNIT tab (your own unit) or a TARGET tab (an enemy); hovering a segment shows that action's description instead. On an enemy the first two segments are used (1 ATTACK, 2 INFO); on your own unit only 2 INFO is used for now and segment 1 is empty (its orders come later). The remaining segments are empty and dimmed.
  - **1 ATTACK**: the card shows the full forecast for your selected unit – the average damage as a big number (AVG DAMAGE), a bar with the range it lands in 8 times out of 10 (RANGE 10–90 %), DESTROY, COUNTER with its range (e.g. `COUNTER 1.3 (0–3)`) or NO COUNTER, and the cost: ENDS MOVEMENT. Click the segment or press **1** to attack; the ring closes and the attack plays. When the attack isn't possible the segment is red and the card says UNAVAILABLE with the reason: NO UNIT SELECTED, TARGET OUT OF RANGE, ALREADY ATTACKED THIS TURN or NO COMMAND POINTS LEFT THIS TURN (or THE BATTLE IS OVER).
  - **2 INFO** (any unit): hovering it only shows the action's card (`ACTION [2] INFO` – "Show the unit's card: strength, stats and status."). Click it or press **2** to show the unit's card (see Unit card) beside the ring; click it or press **2** again to hide it.
  - **Closing**: Esc, a click anywhere outside the ring, or another right-click closes it; that click does nothing else (a right-click on another unit opens the ring there instead). It also closes when your turn ends or the unit is destroyed.
  - In the Polish version the labels read ATAK, INFO, ZNISZCZENIE, KONTRATAK, BEZ KONTRATAKU, KOŃCZY RUCH and NIEDOSTĘPNE.
- **Terrain panel** (bottom left): the hovered tile's terrain, hex position (column·row), movement cost, defense bonus and elevation, plus a `PATH · 2 / 5 MP` row (in your faction colour) when you have a unit selected and the tile is reachable. Above the panel, `■ OP. IRON SHORE` names the operation.
- **Selection**: selecting a unit outlines the area it can reach in your colour and slightly darkens the rest of the map; the tile under the cursor is tinted when the unit can move there. Water is never darkened, and unreachable tiles inside the area (such as a lake) get their own outline.
- **Beyond the map edge**: the land around the map (a little greyer and paler, with trees on HIGH graphics) is scenery only. You can't hover or click tiles there, units can't go there, and the camera can't be panned off the map.
- **Hex grid**: a faint light grid marks the hexes on land (not over water). It fades as you zoom out and is a little stronger while a unit is selected. Press **G** to hide or show it.
- **Objective hexes** (only in a battle that has them): each is outlined by a coloured ring along its edge, with a small flag on a pole near one corner and an **OBJECTIVE** tag above the flag (visible even over forest). Ring, flag and the tag's tab are in the colour of the side that holds the hex (red for Russia, blue for Poland) and change colour when the hex is captured.
- **Done units**: a unit that can neither move nor attack any more this turn has a dimmed tag. This includes units that have not acted once your command points run out.
- **Rocket artillery range**: selecting your rocket artillery outlines all tiles within its range in amber. With nothing selected, hovering any rocket artillery (yours or the enemy's) shows its range, so you can see where it can hit.
- **Ground marks**: tanks leave dark tread marks and rocket artillery trucks thinner tyre marks behind them as they move, rocket strikes leave small craters and a scorched patch around the target, and a destroyed unit leaves a scorched patch on its tile. They are only decoration – they don't change movement or defense. Old marks fade away to make room for new ones (fewer are kept on LOW graphics).
- **Rocket salvos**: rocket artillery fires its full salvo, one rocket after another: 12 rockets for the Homar-K, 16 for the Uragan. The target's HP bar drops as the rockets land. Smoke hangs over the target for a few seconds (on HIGH graphics only). The salvo is only for show: the damage is the same as for any other attack (see Combat). Its counterattacks are full salvos too. In the enemy turn most animations play much faster, but salvos are sped up to only 1.5× normal speed.
- **Tank fire**: before a tank fires – also when it fires back at an attacker – it turns its turret towards the target and raises or lowers its gun to it; as the shot lands, the barrel kicks back and a flash appears at the muzzle (the glow only on HIGH graphics); then the turret turns back to the front. Purely visual.
- **Wrecks and smoke**: a destroyed vehicle (tank or rocket artillery truck) leaves a burnt-out wreck on its tile, standing on a wide patch of black burnt ground where no plants grow (rocks are blackened with soot), with its turret or launcher knocked askew, and a column of smoke rises from it. Smoke is shown on HIGH graphics only. It thins after the first turn start and stops after the third (each player's turn start counts), but the wreck stays. Destroyed infantry leave only the scorched patch, no wreck. Wrecks are scenery only: they don't block movement, give no cover, and can't be selected or attacked. A wreck fades away when a unit ends its move on its tile; a unit that only passes through the tile leaves it standing.

- **Graphics**: the game picks a graphics quality by itself when it starts. On a computer with a real graphics card it uses **HIGH** (full look). On software or compatibility rendering (for example a virtual machine or WSL without GPU) it uses **LOW**: no trees, bushes or rocks (forests and other terrain show only by the ground colour), no shadows, no ambient occlusion or edge smoothing (MSAA), and the 3D view rendered at half resolution, so the game stays playable. The chosen level is printed in the console as "Graphics quality: …". There is no settings screen. To force a level, start the game with `--quality=low` or `--quality=high` (for example `tools/run.sh --quality=low`, or `tools/run_windows.sh --quality=high`).

## 11. Controls

| Action | Control |
|---|---|
| Select your unit | Left-click it |
| Move the selected unit | Left-click a tile inside the outlined area |
| Attack with the selected unit | Left-click a red-marked enemy, or ATTACK (key 1) in its unit ring |
| Open the unit ring | Right-click any unit, yours or the enemy's (without dragging) |
| Use the unit ring | Click a segment, or keys 1 (ATTACK, enemies only) / 2 (INFO) |
| Show / hide a unit's card | INFO in its unit ring (click or key 2, again to hide) |
| Close the unit ring | Esc, a click outside it, or right-click |
| Deselect | Right-click the ground, or Esc (with the unit ring closed) |
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

- **Scenario: …** cycles through the available battles (Iron Shore, Objective battle, Command points battle, Szurpiły Lakes); the chosen one is started by Start operation.
- **Start operation** starts the battle. There is no way back to the menu from a battle; restart the game for that.
- **Language** (the button shows the current one, e.g. "LANGUAGE: ENGLISH") switches between English and Polish (Polski) at once. The choice is saved and used the next time you start the game.
- **Unit catalog** opens a viewer where you can look at every unit in the game.

**Unit catalog.** The list on the left has every unit, grouped by class; a unit without a finished 3D model is marked `(!)` and shown as a simple placeholder. The selected unit stands on a ground disc in the middle. The panel on the right shows its name, its side (with buttons to switch sides when more than one army fields it, e.g. a squad in Polish or Russian colours), its class, how it moves, its HP, Attack, Defense, Moves and Range, and the model's size in metres.

Below that are the animation buttons. Each unit only gets the ones it has:

| Button | Units | What it shows |
|---|---|---|
| Drive | vehicles | the unit drives on the spot, wheels or tracks turning, with dust and exhaust smoke (on/off) |
| March / Kneel / stand | infantry squads | the soldiers march (on/off); kneel down or stand up |
| Deploy | rocket artillery | stabiliser jacks down (Uragan: also the blast shields closed over the cab windows) (on/off) |
| Raise launcher / Traverse | rocket artillery | raises the launcher, turns it to the side (on/off) |
| Traverse | tanks | turns the turret to the side with the gun slightly raised (on/off) |
| Fire | rocket artillery, tanks | rocket artillery: the full battle salvo with its fire, smoke and trails, at a distant target off-screen: deploy, raise, turn, fire, then everything back to travel position; tanks: turn the turret, fire one shot with recoil and muzzle flash, turn back |
| Hit / Death | all | the hit reaction and the destruction (a vehicle leaves its burnt wreck) |
| Reset | all | rebuilds the model in its normal state, e.g. after Death |
| Auto-rotate | all | slowly turns the camera around the unit (on/off) |

While Deploy, Raise launcher, Traverse or Fire is running, the other pose buttons are greyed out. Fire is only available in travel position: for rocket artillery with Deploy, Raise launcher and Traverse all off, for tanks with Traverse off. After Death, only Reset brings the unit back.

| Action (catalog) | Control |
|---|---|
| Rotate around the unit | Left-drag (up and down tilts the view, within limits) |
| Zoom | Mouse wheel |
| Reset the view | Double-click, or Home |
| Back to the main menu | Esc, or the ‹ Back button |

## 13. Not in the game yet

To avoid confusion – these are **not** part of the current game: fog of war (you always see all enemy units), healing or repairing, line of sight, elevation effects, ammunition, unit experience, vehicles carrying the infantry squads, different maps, choosing your country or army, choosing the battle in the menu (the objective battle is only a start option), victory points, an options or graphics settings menu, and saving/loading a match to continue later.
