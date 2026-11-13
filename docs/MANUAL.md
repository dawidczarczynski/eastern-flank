# Eastern Flank – Player's Manual

> This manual covers the game **as it plays today** (an early prototype). It is updated whenever a rule, unit or control changes.

## 1. Overview

Eastern Flank is a turn-based tactical battle on a hex map. You command **Poland** (blue) against **Russia** (red), which the computer plays. Poland starts with four units, Russia with five. (In the Polish version of the game the sides are called "Polska" and "Rosja".)

The two sides field different, real-world equipment with its own stats: Poland has fewer but stronger units, Russia has more of them. Both sides follow exactly the same rules. You and the opponent take turns moving and attacking.

**Goal:** every battle has its own victory conditions and may have a turn limit (see section 8). In the normal battle the goal is to destroy every enemy unit: the last side with units left on the map wins, and there is no turn limit. A second, objective battle (a debug option for now) is about taking and holding two marked hexes within 8 turns.

The game opens in a main menu, where you start the battle, pick the scenario, change the settings (language, sound) or browse the units in the unit catalog (see section 12).

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
- To try it, start the game with `--scenario=command_points_battle` (for example `tools/run.sh --scenario=command_points_battle`), then pick **Start scenario** and **Start** (the option preselects its entry): the normal battle with **N = 2** for both sides. It is a test battle; later, an operation's battle conditions will set N.

## 4. Units

| Unit | HP | Movement | Attack | Defense | Range | Look on the map |
|---|---|---|---|---|---|---|
| Mechanised Infantry Squad (Poland) | 10 | 3 | 4 | 3 | 500 m (2 hex), max 750 m | a squad of soldiers |
| Motor Rifle Squad (Russia) | 10 | 3 | 4 | 3 | 500 m (2 hex), max 750 m | a squad of soldiers |
| M1A2 SEPv3 Abrams (Poland) | 10 | 5 | 7 | 4 | 2.0 km (8 hex), max 3.5 km | an Abrams tank |
| T-72B3 (Russia) | 8 | 5 | 6 | 4 | 2.0 km (8 hex), max 3.0 km | a T-72 tank |
| Homar-K (Poland) | 6 | 3 | 6 | 1 | 70 km (whole map), min 750 m | a Homar-K truck with a turning rocket launcher |
| 9K57 Uragan (Russia) | 6 | 3 | 6 | 1 | 30 km (whole map), min 750 m | a BM-27 truck with sixteen rocket tubes over the cab |

- **HP**: the unit's strength – how much damage it can take, and how many shots it fires (see Combat). Every unit is a company: a unit that has lost HP also fights worse, because it fires fewer shots. At 0 HP it is destroyed and removed from the map. HP doesn't come back.
- **Movement**: movement points per turn (see Movement).
- **Attack** / **Defense**: used in the damage calculation (see Combat).
- **Range**: how far away the unit can attack, in metres or kilometres (one hex is 250 m). Out to the **effective range** the weapon hits at full chance; beyond it the hit chance falls steadily to half at the **maximum range**, the farthest it can fire at all (see Combat). Rocket artillery also has a **minimum range** of 750 m (3 hexes) and cannot fire at closer targets.

Roles in short: **infantry squads** are tough and slow but barely scratch a tank; **tanks** are fast, well armoured and hit hard – the Abrams is stronger and tougher than the T-72B3, which is why Russia brings two; **rocket artillery** hits from a distance (it reaches the whole map, never targets closer than 3 hexes and needs no line of sight) but dies quickly if the enemy reaches it. The two squads have the same stats.

Every unit has a small tag above it: a coloured tab for its side (blue for Poland, red for Russia), a short name – **INF** for the infantry squads (PIECH in the Polish version), the real designation for vehicles (**M1A2**, **HOMAR**, **T-72B3**, **BM-27**) – and an HP bar that turns from green to yellow to red as the unit loses HP.

The units themselves wear their army's camouflage: Polish vehicles and soldiers in olive green, brown and black, Russian ones in green, near-black and sand.

## 5. The map and terrain

| Terrain | Movement cost | Defense bonus |
|---|---|---|
| Plains | 1 | +0 |
| Forest | 2 | +1 |
| Hills | 2 | +2 |
| Water | impassable | – |
| Fields | 1 | +0 |
| Urban (villages) | 1 | +2 |
| Marsh | 2 | +0 |

- The **movement cost** is paid when a unit enters the tile.
- The **defense bonus** is added to the defense of a unit standing on that tile when it is hit.
- **Roads**: moving along a road from one hex into the next costs **1**, whatever the terrain of the next hex – a road through a forest or over a hill is as fast as open ground. It only counts *along* the road: a road in the neighbouring hex does not help, and a road does not let you enter water.
- **Rivers**: entering a hex with a river costs **1 more** than its terrain (plains 2, forest or marsh 3). There is no extra cost where a road crosses the river – a bridge. Leaving a river hex is free. You can move along a river, but you pay the +1 for every river hex you enter.
- The most expensive step is 3 (forest or marsh with a river), so every unit can always enter any hex that is not water from a full move.
- Fields, villages, marshes, roads and rivers appear only on **real-terrain maps** (below); the normal battle has none of them.
- Every tile also has an **elevation**, shown in metres in the terrain panel. Elevation has **no effect on the rules** yet; only the terrain type matters.

### Maps from real terrain

Battles are meant to be fought on the real ground of the eastern flank. A real-terrain map is built from open map data: forests, lakes and open ground come from OpenStreetMap, heights from the Copernicus elevation model. Each hex is about **250 m** across; a battle map of 30 × 24 hexes covers roughly 7.5 × 5 km.

- A hex takes the terrain that covers most of it: mostly lake → **water**, mostly forest → **forest**. Otherwise it is open ground, checked in this order: **urban** when buildings and yards cover at least a fifth of it, **marsh** when wetland covers at least a quarter, **hills** when the ground rises or falls 15 m or more within the hex, **fields** when farmland is the largest open cover, else **plains** (meadows and open ground the map data does not describe).
- Main roads and village streets count as **roads** (field and forest tracks do not); rivers, canals and named streams count as **rivers**. Wide rivers drawn as water areas are water.
- On a real-terrain map the terrain panel shows the hex's **real height above sea level**. The 3D relief is drawn 1.5 × taller than reality so that hills read on screen, and every lake sits at the same water level.
- To try it, start the game with `--scenario=suwalki_battle` (for example `tools/run.sh --scenario=suwalki_battle`), then pick **Start scenario** and **Start** (the option preselects its entry): the usual forces on the lakes and moraine hills around **Szurpiły** in the Suwałki Landscape Park (north-east Poland). Poland deploys in the west, Russia in the east; the usual objectives and win conditions apply (see the battle rules).
- Map data © OpenStreetMap contributors (ODbL), elevation © DLR e.V. / Airbus Defence and Space, provided under Copernicus by the European Union and ESA. Full credits: `data/maps/CREDITS`.

## 6. Movement

- Select one of your units and click a tile to move there. The unit walks the cheapest path and the cost is taken from its movement points.
- A unit can move several times in one turn as long as it has points left.
- A unit cannot enter **water** and cannot enter or pass through a tile with **any other unit** on it, friend or enemy.
- Moving next to an enemy does not stop you; there are no zones of control.
- **After a unit attacks, it can't move any more this turn.** Move first, then attack.

When a unit is selected, the area it can reach is outlined in your side's colour and the rest of the map is slightly darkened. Hovering a reachable tile tints it and shows the path as a line of dots, and the terrain panel shows the path cost, e.g. `2 / 3 MP` (cost / movement points left). The cost includes roads and rivers: three road hexes through a forest cost `3 / 3 MP`, and the path follows the road when it is cheaper.

## 7. Combat

### Attacking

- Any of your units can attack **one enemy unit per turn** that is within its reach: no farther than its maximum range and, for rocket artillery, no closer than its minimum range of 3 hexes (750 m).
- **Line of sight**: tanks and infantry (direct fire) need a clear line to the target. **Forests, urban hexes and hills block it**; units never do, and neither do plains, fields, marsh or water. Rocket artillery fires over everything and ignores line of sight.
- **Range and hit chance**: out to its effective range a shot has its normal hit chance. Farther out the chance shrinks in proportion, down to **half** at the maximum range. For example an Abrams (effective 8 hexes, maximum 14) firing from 11 hexes has 75 % of its normal hit chance.
- You can attack without moving, or move first and then attack. Attacking ends the unit's movement for the turn.
- When a unit is selected, enemies it can attack right now are marked in red. Click one to attack it at once.
- Hovering a red-marked enemy turns the cursor into an amber crosshair and shows a small **attack tag** beside it: your expected damage, the chance to destroy the target and its expected counterattack, so you don't have to work out the odds below by hand.
- **Right-click any enemy** to open the **unit ring** around it: its ATTACK action shows the full forecast and lets you attack from there, or tells you why you can't. See Screen for both.

### Damage

An attack is a roll of dice: you know the odds, never the exact result.

1. **Hit number** = attacker's Attack − (defender's Defense + defense bonus of the defender's tile + the defender's position bonus, if the battle came from the operational map), but at least 1. The attacker's own tile doesn't matter.
2. The attacker fires **one shot per HP it has right now**. Each shot rolls a die with as many faces as the attacker's **full** HP (a d10 for the squads and the Abrams, a d8 for the T-72B3, a d6 for the rocket launchers).
3. A roll **at or below the hit number** is a hit. **Damage = number of hits.** The defender loses that many HP (it can't go below 0).

So the hit chance of each shot is the hit number out of the attacker's full HP – for example an Abrams with hit number 3 hits on 1–3 of a d10, 30 % per shot.

What this means:

- A unit at **full strength deals on average exactly the hit number** (the damage table below). A unit at half its HP fires half the shots and deals half as much on average.
- **An attack can deal 0 damage.** With a hit number of 1, about one attack in three misses completely (e.g. a squad attacking a tank). Such an attack plays out normally, the target just loses no HP; there is no separate "miss" message.
- An attack can never deal more damage than the attacker has HP (one hit per shot at most).
- A unit can only be destroyed in one attack if the attacker fires at least as many shots as the target has HP left, and the more the attacker has to spare, the likelier it is. Against a full squad even a full Abrams has only a tiny chance (all ten shots must hit: about 1 in 10,000); against a full rocket launcher (6 HP) on plains it succeeds 63 % of the time.

### Counterattack

If the defender **survives** and the attacker is **within the defender's own reach** (maximum range, minimum range and, for direct fire, line of sight, exactly as for an attack), the defender immediately hits back once, with the same roll (now the original attacker's tile gives the defense bonus). It fires **only with the HP it has left after your attack**, so a defender you have hurt hits back weaker – striking first pays off.

- A counterattack doesn't use up the defender's attack or movement. A unit counterattacks **every** attack it survives, any number of times per turn.
- A counterattack never triggers another counterattack.
- A counterattack can destroy the attacker.
- A counterattack is shot at the same reduced hit chance as an attack from that distance. Infantry and tanks can't hit back at rocket artillery that fires from beyond their maximum range or from a hex they can't see.
- Rocket artillery can't counterattack a target closer than 3 hexes (its minimum range); anything that attacks it from 3 or more hexes away is answered, sight or no sight.

### Worked examples

Your Abrams (Attack 7, Defense 4, on plains) attacks an enemy T-72B3 (Attack 6, Defense 4) on **plains** (+0).

1. Your hit number: 7 − (4 + 0) = **3**. Your Abrams fires 10 shots with a d10, each hitting on 1–3 (30 %). On average **3** damage, usually 1 to 5 (only about 3 % of attacks miss completely); the T-72B3 goes from 8 HP to about 5.
2. If the T-72B3 survives (it almost always does), it hits back, because your Abrams is adjacent (within range 1): hit number 6 − (4 + 0) = **2** on a d8 (25 % per shot), one shot per HP it has left. With about 5 HP left that is **1.25** damage on average; about a quarter of the time it doesn't hit at all.
3. The attack tag sums this up as `DIST 1 hex (250 m)`, `ATTACK ~3.0 (1–5)`, `DESTROY <1 %`, `COUNTER ~1.3`; the unit ring's ATTACK card also gives the counter's range, `COUNTER 1.3 (0–3)`.

Your Abrams attacks an enemy Motor Rifle Squad (Attack 4, Defense 3) standing in a **forest** (+1).

1. Your hit number: 7 − (3 + 1) = **3**: on average **3** damage, usually 1 to 5. The squad goes from 10 HP to about 7.
2. The squad hits back: 4 − (4 + 0) = 0, raised to the minimum hit number of **1**, so each of its remaining shots hits on a 1 of a d10. On average **0.7** damage to your Abrams; about half the time nothing.

The same attack on a squad standing on plains would deal 4 damage on average, on hills only 2. Attacking units in good terrain is costly.

Your Homar-K (Attack 6) fires at the Uragan (Defense 1) on plains from 6 hexes away (1.5 km, inside both ranges and past the 3-hex minimum): hit number 6 − (1 + 0) = **5**, six shots with a d6, each hitting on 1–5. On average **5** damage, usually 4 to 6, and a 33 % chance that all six hit and the Uragan is destroyed. Otherwise the Uragan, which also ignores sight, hits back with its remaining HP, about 0.8 damage on average. Attack tag: `DIST 6 hex (1.5 km)`, `ATTACK ~5.0 (4–6)`, `DESTROY 33 %`, `COUNTER ~0.8`.

Your Abrams (full strength) fires at an enemy T-72B3 on plains from 10 hexes away (2.5 km), in a clear line of sight. That is 2 hexes beyond its effective range of 8, with maximum 14: the hit chance is multiplied by (12 − 2) / 12 = 0.83, so 30 % per shot becomes 25 % and the average damage about **2.5** instead of 3. The tag adds `RANGE -17 %`. The T-72B3 (effective 8, maximum 12) also hits back at 0.75 of its normal chance. At 14 hexes the Abrams would hit at only half its normal chance (`RANGE -50 %`), and at 15 hexes it can't fire at all.

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

Each battle sets its own victory conditions and, optionally, a turn limit. The game has two battles: the **normal battle** (the Iron Shore scenario) and the **objective battle**.

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
- To play it, start the game with `--scenario=objective_battle` (for example `tools/run_windows.sh --scenario=objective_battle` or `tools/run.sh --scenario=objective_battle`), then pick **Start scenario** and **Start** (the option preselects its entry). Without the option you get the normal battle.

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
- **Bottom bar**: a full-width bar docked to the bottom edge. Left: the operation name and the terrain strip for the hovered hex (hex, terrain, move cost, defence modifier, elevation, tags, and the path cost `PATH 3 / 5 MP` when a unit is selected; `HOVER A HEX` when none). Centre: icon buttons, same effect as the keys (hover one for its name, key and a short description): **grid** (G, lit while the grid is on), **reset view** (Home, resets the camera tilt), **deselect** (Esc), **save** (F5, saves the match record). Right: the **READY** counter (your units that can still do something / all your units, one block per unit: filled = can still act; once your command points run out, units that have not acted no longer count as ready) and the **End turn** button in your side's colour, greyed out while animations play and during the enemy turn. The **hamburger** (top left, or Esc with nothing selected) opens the battle menu: **Save** (F5; scenario battles only) and the exit row, which asks first. In a battle fought for the operation the exit is **Leave battle**: the fight is finished automatically from the positions reached (current company strengths, turns already played) and the result goes to the operation as if the battle had ended; in any other battle it is **Exit to main menu**. The staff map has its own bar (see the operational map chapter).
- **Unit card**: shown only through the unit ring's **INFO** action (see Unit ring below) – hovering a unit on the map does not show it. It appears beside the ring and is framed in the unit's side colour. From top to bottom:
  - **Tab**: the unit's class (INFANTRY, TANK or ROCKET ARTILLERY) on the left and its side (POLAND / RUSSIA) on the right.
  - **Name**: the unit's real name in capitals (e.g. M1A2 SEPv3 ABRAMS), with its short designation in small grey type below it (M1A2, HOMAR, BM-27). Squads and the T-72B3 have no designation line, because it would only repeat the class or the name. In the Polish version the class and the squad names are translated (Drużyna piechoty zmechanizowanej, Drużyna zmotoryzowana); vehicle names stay as they are.
  - **Portrait**: a lit 3D picture of the unit in its side's camouflage (rendered once per unit type and side at the start of the battle), behind amber corner brackets and a crosshair. Until it is ready the box is plain dark.
  - **Strength**: HP as `current/max` and a row of slanted segments, one per maximum HP point. Lost points are empty; the remaining ones are green above 60 % HP, yellow above 35 % and red at 35 % or less.
  - **Stats**: Attack, Defense, Moves (left / per turn) and Range, each with its number and a short bar. Attack and Defense bars are full at 10, Moves and Range bars at 6. Range shows the effective range in kilometres (or metres) with hexes, e.g. `2.0 km (8 hex)`. Defense includes the terrain bonus of the unit's tile, e.g. `5 (3+2)` on hills, and its bar shows that total.
  - **Mobility tag**: how the unit moves – FOOT (infantry), WHEELED (rocket artillery) or TRACKED (tanks). For now this is information only; all units pay the same movement costs.
  - **Status**: a small hexagon and a line saying READY (green), READY · ALREADY ATTACKED (green), DONE THIS TURN (grey) or ENEMY UNIT (in the enemy's colour).
- **Attack tag**: while one of your units is selected and you hover an enemy it can attack right now, the cursor becomes an amber crosshair and a small tag appears next to it. Anything else (your own unit, an enemy out of range, nothing selected) shows the normal cursor and nothing extra. The numbers follow the dice rules in Combat, including a weakened attacker firing fewer shots and the target's terrain:
  - `DIST 6 hex (1.5 km)`: the distance to the target.
  - `RANGE -25 %`: shown only when the target is beyond your effective range – how much the hit chance is reduced there (down to -50 % at maximum range).
  - `ATTACK ~3.0 (1–5)`: your attack's average damage and, in brackets, the range it lands in 8 times out of 10. It never exceeds the HP the target has left.
  - `DESTROY 63 %`: the chance your attack destroys the target outright. Shows `<1 %` or `>99 %` near the edges and `100 %` when certain; the line is left out when it is impossible (you fire fewer shots than the target has HP).
  - `COUNTER ~1.3`: the average damage of the enemy's counterattack, counting only the HP it would have left after your attack (a destroyed target doesn't hit back). `NO COUNTER` when your unit is outside the enemy's reach, e.g. a Homar-K firing at an infantry squad from 20 hexes, or a tank firing from a forest the squad can't see into.
  - Examples on plains, both units at full strength: Abrams → T-72B3 `ATTACK ~3.0 (1–5)`, `DESTROY <1 %`, `COUNTER ~1.3`; Abrams → Motor Rifle Squad `ATTACK ~4.0 (2–6)`, `DESTROY <1 %`, `COUNTER ~0.6`; Abrams → Uragan `ATTACK ~5.4 (4–6)`, `DESTROY 63 %`, `COUNTER ~0.2`; Homar-K → Uragan from 6 hexes `ATTACK ~5.0 (4–6)`, `DESTROY 33 %`, `COUNTER ~0.8` (each also has the `DIST` line first).
- **Unit ring**: right-click (without dragging) any living unit – yours or the enemy's – during your turn to open a ring of six segments around it. It stays on the unit when you pan, rotate or zoom. Beside the ring is a card: with nothing hovered it shows the unit's name and Strength under a UNIT tab (your own unit) or a TARGET tab (an enemy); hovering a segment shows that action's description instead. On an enemy the first two segments are used (1 ATTACK, 2 INFO); on your own unit only 2 INFO is used for now and segment 1 is empty (its orders come later). The remaining segments are empty and dimmed.
  - **1 ATTACK**: the card shows the full forecast for your selected unit – the average damage as a big number (AVG DAMAGE), a bar with the range it lands in 8 times out of 10 (RANGE 10–90 %), DESTROY, COUNTER with its range (e.g. `COUNTER 1.3 (0–3)`) or NO COUNTER, and the cost: ENDS MOVEMENT. Click the segment or press **1** to attack; the ring closes and the attack plays. When the attack isn't possible the segment is red and the card says UNAVAILABLE with the reason: NO UNIT SELECTED, TARGET OUT OF RANGE, NO LINE OF SIGHT, TARGET TOO CLOSE, ALREADY ATTACKED THIS TURN or NO COMMAND POINTS LEFT THIS TURN (or THE BATTLE IS OVER).
  - **2 INFO** (any unit): hovering it only shows the action's card (`ACTION [2] INFO` – "Show the unit's card: strength, stats and status."). Click it or press **2** to show the unit's card (see Unit card) beside the ring; click it or press **2** again to hide it.
  - **Closing**: Esc, a click anywhere outside the ring, or another right-click closes it; that click does nothing else (a right-click on another unit opens the ring there instead). It also closes when your turn ends or the unit is destroyed.
  - In the Polish version the labels read ATAK, INFO, ZNISZCZENIE, KONTRATAK, BEZ KONTRATAKU, KOŃCZY RUCH and NIEDOSTĘPNE.
- **Terrain panel** (bottom left): the hovered tile's terrain, hex position (column·row), movement cost (the terrain's own cost), defense bonus and elevation, tags such as `IMPASSABLE`, `ROAD` (a road leaves this hex) and `RIVER +1` (entering this hex costs 1 more), plus a `PATH · 2 / 5 MP` row (in your faction colour) when you have a unit selected and the tile is reachable. Above the panel, `■ OP. IRON SHORE` names the operation.
- **Selection**: selecting a unit outlines the area it can reach in your colour and slightly darkens the rest of the map; the tile under the cursor is tinted when the unit can move there. Water is never darkened, and unreachable tiles inside the area (such as a lake) get their own outline.
- **Beyond the map edge**: the land around the map (a little greyer and paler, with trees on HIGH graphics) is scenery only. You can't hover or click tiles there, units can't go there, and the camera can't be panned off the map.
- **Roads and rivers** (real-terrain maps only): roads are drawn at their real width as narrow gravel roads (a 5 m carriageway with two darker wheel ruts and grassy-earth verges that fade into the ground; they never get thinner than about a pixel and a half on screen, so they stay visible when zoomed out), and rivers as thin blue-grey lines, each running from hex centre to hex centre across the hex sides it links. Trees, rocks and grass don't grow on them. Fields are drawn as large straight strips of one crop each (150–400 m wide, up to over a kilometre long, parallel within a region) – muted olive and grey-green young cereal, maize, potatoes and beet, golden grain, pale stubble, brown ploughed soil and meadows – with faint rows and hedgerow strips between neighbours; nothing grows on the crops themselves (no trees, rocks or tall grass), only the hedgerows carry some trees and shrubs; a parcel does not have to follow hex borders (a hex counts as a field when most of it is), and forests, villages, marshes and water stay unpainted. Villages look like farmyards (gravel, bare soil and grass mixed), marshes wet and muddy. Marshes are also covered by dense stands of tall reeds with brown seed heads, and reeds grow in patches along river banks (not in villages) – they are only decoration (marsh rules stay: move 2, no defense bonus). (Houses, bridges and a proper river look come later.)
- **Hex grid**: a faint light grid marks the hexes on land (not over water). It fades as you zoom out and is a little stronger while a unit is selected. Press **G** to hide or show it.
- **Objective hexes** (only in a battle that has them): each is outlined by a coloured ring along its edge, with a small flag on a pole near one corner and an **OBJECTIVE** tag above the flag (visible even over forest). Ring, flag and the tag's tab are in the colour of the side that holds the hex (red for Russia, blue for Poland) and change colour when the hex is captured.
- **Done units**: a unit that can neither move nor attack any more this turn has a dimmed tag. This includes units that have not acted once your command points run out.
- **Weapon range**: selecting a unit outlines its effective range in amber and the extended band out to its maximum range in a paler outline; hexes it can't see (blocked by forest, urban or hills, for direct fire) are dimmed. With nothing selected, hovering any unit (yours or the enemy's) shows its range the same way. A target out of sight gets no crosshair, and the right-click ring's ATTACK says NO LINE OF SIGHT (or TARGET TOO CLOSE inside a rocket artillery's minimum range).
- **Ground marks**: tanks leave dark tread marks and rocket artillery trucks thinner tyre marks behind them as they move, rocket strikes leave small craters and a scorched patch around the target, and a destroyed unit leaves a scorched patch on its tile. They are only decoration – they don't change movement or defense. Old marks fade away to make room for new ones (fewer are kept on LOW graphics).
- **Rocket salvos**: rocket artillery fires its full salvo, one rocket after another: 12 rockets for the Homar-K, 16 for the Uragan. The target's HP bar drops as the rockets land. Smoke hangs over the target for a few seconds (on HIGH graphics only). The salvo is only for show: the damage is the same as for any other attack (see Combat). Its counterattacks are full salvos too. In the enemy turn most animations play much faster, but salvos are sped up to only 1.5× normal speed.
- **Tank fire**: before a tank fires – also when it fires back at an attacker – it turns its turret towards the target and raises or lowers its gun to it; as the shot lands, the barrel kicks back and a flash appears at the muzzle (the glow only on HIGH graphics); then the turret turns back to the front. Purely visual.
- **Wrecks and smoke**: a destroyed vehicle (tank or rocket artillery truck) leaves a burnt-out wreck on its tile, standing on a wide patch of black burnt ground where no plants grow (rocks are blackened with soot), with its turret or launcher knocked askew, and a column of smoke rises from it. Smoke is shown on HIGH graphics only. It thins after the first turn start and stops after the third (each player's turn start counts), but the wreck stays. Destroyed infantry leave only the scorched patch, no wreck. Wrecks are scenery only: they don't block movement, give no cover, and can't be selected or attacked. A wreck fades away when a unit ends its move on its tile; a unit that only passes through the tile leaves it standing.

- **Graphics**: the game picks a graphics quality by itself when it starts. On a computer with a real graphics card it uses **HIGH** (full look). On software or compatibility rendering (for example a virtual machine or WSL without GPU) it uses **LOW**: no grass or reeds, no trees, bushes or rocks (forests and other terrain show only by the ground colour), no shadows, no ambient occlusion or edge smoothing (MSAA), and the 3D view rendered at half resolution, so the game stays playable. The chosen level is printed in the console as "Graphics quality: …". There is no settings screen. To force a level, start the game with `--quality=low` or `--quality=high` (for example `tools/run.sh --quality=low`, or `tools/run_windows.sh --quality=high`).

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
- **F5** in a battle saves a record of the match so far (the moves made, for reporting bugs; it is not a save of the operation, and a battle in progress cannot be saved); the game also does this automatically when the battle ends. There is no way to load a saved match in the game yet. Match records saved by earlier versions of the game (before the real Polish and Russian units) can no longer be replayed: they are refused with a clear "unsupported match record version" message instead of replaying a different battle.

## 12. Main menu and unit catalog

The game opens in the main menu with five buttons. Every other screen has a **‹ Back** button, and Esc does the same.

- **Continue** (top) loads the saved operation (see **Saving** in section 12b). It is greyed out until you have saved one.
- **Start scenario** opens the scenario screen: the available battles (Iron Shore, Objective battle, Command points battle, Szurpiły Lakes) are listed on the left, and a flat map preview of the selected one (terrain, roads, rivers, and a dot per starting unit) is shown on the right. **Start** starts the selected battle; **Back** returns to the main menu. There is no way back to the menu from a battle; restart the game for that.
- **Operation** opens the operational map (section 12b).
- **Unit catalog** opens a viewer where you can look at every unit in the game.
- **Settings** opens the settings screen:
  - **Language** (the button shows the current one, e.g. "LANGUAGE: ENGLISH") switches between English and Polish (Polski) at once. The choice is saved and used the next time you start the game.
  - **Sound** switches all sound on or off; **Master volume** and **Ambient volume** are sliders (0-100 %). They apply at once and are saved for the next start. See section 12a.

**Unit catalog.** The list on the left has every unit, grouped by class; a unit without a finished 3D model is marked `(!)` and shown as a simple placeholder. The selected unit stands on a ground disc in the middle. The panel on the right shows its name, its side (with buttons to switch sides when more than one army fields it, e.g. a squad in Polish or Russian colours), its class, how it moves, its HP, Attack, Defense, Moves and Range (the full line, e.g. `2.0 km (8 hex), max 3.0 km`; the Uragan `35 km (whole map), min 750 m`; infantry `500 m (2 hex), max 750 m`), and the model's size in metres.

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

## 12a. Sound

The battle has sound; there is no music yet.

- **Clicks.** Buttons click when pressed and tick softly when you hover over them; selecting one of your units, giving a move order and giving an attack order each have their own short cue, and an order the game refuses plays a low error sound.
- **Weapons.** Every kind of unit fires with its own sound: tank cannon, infantry fighting (a random few seconds of a firefight recording per squad attack), rocket launchers (one launch sound per rocket of a salvo). Shells and rockets explode where they land; a destroyed unit gets a bigger explosion. A complete miss of a tank or squad makes no impact sound.
- **Engines.** A moving vehicle rumbles for the whole length of its move (tanks with a low track rumble, rocket trucks with a tyre hum); the engine rises in pitch when it sets off and drops when it stops. Infantry moves silently. Sounds are positional: they are louder and pan to the side when the unit is near the camera's view.
- **Forest.** When you zoom the camera in close (roughly the closest third of the zoom range) over a forest, birdsong and the rustle of trees fade in over a second or two, with random bird calls on top; they fade out when you zoom out or pan to open ground.
- **Volume.** Master volume, Ambient volume (the forest sound only) and the Sound on/off switch are in the Settings screen of the main menu, and are remembered. With the volume at 0 or sound off, nothing is played.

## 12b. Operational map

**Operation** in the main menu first asks **which side you command**: a window shows NATO and Russia side by side (flag, short briefing, lead faction, alliance decision, whether the side has a nuclear option, number of formations). Click a card (or ←/→ and Space) to pick it – the picked card says *You command*, the other *Opponent · AI* – then **Start operation** (Enter); **Back**, ✕, Esc or a click outside returns to the menu. The other side is played by the AI. **Continue** skips this screen (a save remembers your side). The staff map of the Suwałki theatre then opens: a dark, clean digital map laid over a gently raised relief and seen at a slant, covering the Baltic coast and the Curonian Lagoon in the north-west, the Kaliningrad oblast, Lithuania, the Suwałki Gap, Poland's Masuria and Podlasie and western Belarus (one hex is 5 km). A loading screen shows while the map is drawn. The formations of the operation stand at their start positions and can be inspected (see **Formations** below); orders: see **Orders** below, turns: see **Turns** below. The **hamburger** (top left, or Esc when nothing is selected) opens the menu with **Save** and **Exit operation**; exiting asks for confirmation and offers to save first when there is unsaved progress.

**Camera.** North is always up (the map does not rotate). The view starts tilted by 35°: the relief stands out, and hexes at the top of the screen are exactly as big as at the bottom (the camera has no perspective shrink). **Ctrl** + mouse wheel or holding **Q** / **E** changes the tilt between flat (0°, straight down) and 50°; **V** switches between flat and the last tilt. Drag with the left (or middle) mouse button, press W A S D or the arrow keys, or move the cursor to the edge of the window to pan. The mouse wheel zooms towards the cursor. Zoomed out fully the whole theatre fits in the window; zoomed in fully you see about 10 hexes across the shorter side of the window. The camera stops at the map border.

**What you see.** Lines keep the same width on screen at every zoom and tilt. The more you zoom in, the more detail fades in: zoomed out you see only the main roads and the large rivers, in the middle range the secondary roads and medium rivers join them, close in also the minor roads and streams. Place names fade in the same way: cities show from far away, towns closer in and large villages only close in; names are written in the local language, so places in Belarus and the Kaliningrad oblast appear in Cyrillic.

| Drawn as | Meaning |
|---|---|
| Dark grey-green | open ground (plains, fields, hills) |
| Slightly greener patches with a faint edge | forest |
| Small grey patches with a lighter edge | towns and cities |
| Very dark blue with a thin blue-grey shore line | the sea, lagoons and lakes |
| Short blue-grey dashes | marsh |
| Light and dark shading | relief: slopes lit from the north-west (a hint of hills and valleys; heights are exaggerated) |
| Light sand line with a dark outline | main road |
| Grey-brown line, thinner | secondary road (middle and close zoom) |
| Dark brown thin line | minor road (close zoom) |
| Blue lines, from thick and light to thin and dark | large, medium and minor rivers |

The terrain is drawn from real geography, not from the hexes: the coastline, the lagoons and the lakes, forests, fields, marshes and towns are their real shapes (to about 250 m) with soft edges, and the relief shading comes from real heights. A lake smaller than a hex (Wigry, Hańcza) shows although its hex counts as land. The hexes underneath only decide movement and borders, so a hex's terrain on the card can differ from what is drawn under part of it. Which road is "main" is worked out from how far it runs on the map, not from its real road category yet, so the hierarchy is approximate; roads and rivers still run along the hexes.

**Grid and hex card.** The hex grid is hidden; **G** shows or hides a thin, faint helper grid over the map (press it again to hide it). Pointing at a hex outlines it in amber and shows a small card: its coordinate (column·row), terrain, elevation in metres, and whether a road and a river cross it. Picking follows the raised relief, so the card names the hex really under the cursor at any tilt. The card disappears when the cursor leaves the map.

| Action (operational map) | Control |
|---|---|
| Pan | Left-drag, W A S D, arrow keys, or the cursor at the window edge |
| Zoom | Mouse wheel (towards the cursor) |
| Tilt | Ctrl + mouse wheel, or hold Q (flatter) / E (steeper) |
| Flat / tilted | V |
| Grid on / off | G |
| Place names on / off | N |
| Country borders and names on / off | B (while no battle is pending) |
| Air defence coverage on / off | C |
| Country card | K |
| Play the pending battle | B, or **Play battle** on the contact card |
| Close the battle result card | Enter or Esc, or **Continue** |
| Journal on / off | J, or the **JRN** (log book) button on the bottom bar; Esc or ✕ closes it |
| End turn | Enter, or the **End turn** button |
| Save the operation | F5, or **SAVE** in the menu (hamburger, top left) |
| Select a formation | Left click on its counter |
| Next own formation | Tab |
| March the selected formation to a hex | Left click on the hex |
| Attack an enemy formation | Left click on its counter or hex |
| Bottom bar (staff map) | Full-width bar: the hovered hex on the left (hex, terrain, elevation, road, river, country, stance), icon buttons **map options** (opens a window with six toggle rows – grid G, place names N, borders B, political tint P, air defence cover C, flat view V – each showing ON / OFF and its key; the map stays live behind it), **strike** (S, lit while strike mode is open), next formation (Tab), cancel order (X), turn report (R) – hover one for its name, key and description; toggles stay lit while on. The End turn button is in the bar at the far right, in the same place as in a battle |
| Order ring (March / Attack / Defend / Cancel) | Right click on the hex; 1-4 pick a segment, Esc closes |
| Cancel the order | Delete, Backspace or X |
| Deselect | Esc, or a click on empty map |
| Exit the operation | Esc (nothing selected) or the hamburger opens the menu: **Save** (F5) and **Exit operation** (asks first; offers to save when the progress is not saved) | |

### Countries

Every land hex belongs to one of four countries: Poland, Lithuania, Belarus or Russia (the Kaliningrad oblast). A warm dash-dot line follows the real state border – along the south edge of the oblast, along the Neman, across the Suwałki Gap and along the Belarusian border – and a very faint, large name (POLSKA / LITWA / BIAŁORUŚ / ROSJA, or the English names) lies over each country. Hexes in the sea or in a large lake belong to none. Pointing at a hex adds a **Country** line to the hex card (a dash for a hex without a country). The line is drawn from the real border (OpenStreetMap), not along the hexes; the hexes only decide which country a hex counts as for the rules. Press **B** to hide or show the borders and the names (on at the start).

### Politics

**Allied contributions.** Two countries lean towards a side and bring troops of their own to it: **Lithuania** leans to NATO and **Belarus** to Russia. A contribution comes once, at the moment the country becomes **belligerent** (goes to war) on the side it leans to; it does not come while the country is neutral or only aligned, and never comes twice. A country that goes to war on the other side brings nothing.

| Country | Joins | Formations | Total strength |
|---|---|---|---|
| Lithuania | NATO | 3 battalions (two Iron Wolf battalions and a NATO brigade battalion) | 120 |
| Belarus | Russia | 3 battalions (two 6th mechanised battalions and a tank battalion) | 110 |

**Where they appear.** The formations stand on the ally's own territory, at their set start hexes, at full strength, with no orders and in the starting posture. If a start hex is taken by another formation or cannot be entered, the formation is placed on the nearest free hex of the same country within 3 hexes. If there is none, that formation is lost: it does not come.

**The join notice.** When allies arrive, a notice appears: "<Country> joins <side> – N formations" (N counts the formations that really appeared), with a **Show** button that moves the camera to them. The new counters pulse with a ring for a moment and carry a small tag with the country's code, so you can tell them apart from the original formations.

**The escalation ladder.** The tension between the blocs is one **shared** level with seven steps, numbered 0 to 6 as on the chip; both sides push it up and it belongs to neither. "Suwałki Gap" starts at level 1, Limited war.

| Level | Name | What may be struck | Notes |
|---|---|---|---|
| 0 | Contained clash | formations | |
| 1 | Limited war | formations, air defence, depots | |
| 2 | Open war | formations, air defence, depots, airfields, command posts | the enemy sanctuary opens |
| 3 | Regional war | the same as Open war | allies join |
| 4 | General war | the same as Open war | no automatic effect |
| 5 | Strategic alert | the same as Open war | no automatic effect; the highest level incidents and decisions can reach |
| 6 | Nuclear attack | nothing | only by Russia's *Use nuclear weapon*; ends the operation |

A strike is refused if its target is on your own soil, in a country that is closed to you, or of a kind the current level does not allow.

**What raises it.** The rules are in place for: the first breach of an enemy sanctuary (Russian soil for NATO, and the other way round) raising the level by one, once per country and bloc, and a bloc's **first** strike on a town hex in the operation raising it by one (its later town strikes add nothing; the other bloc's first town strike still counts). The game records which bloc caused each rise. Strikes (see **Deep strikes**) are in the rules, launched in strike mode (key S); ground entry is described under **Borders and movement** below, and the level can also be changed from the debug panel.

**What lowers it.** After 3 quiet rounds in a row (a round in which nobody raised the level) it falls back by one step, and the quiet count starts again. The **Stand down** decision (below) lowers it too.

**Allies.** When the level first reaches Regional war, allied countries join automatically: aligned countries go to war on their side, and neutral countries that lean to a side become aligned with it.

**The cap at level 5.** Incidents and ordinary decisions never take the level above 5, Strategic alert. A rise that would go further stops at 5; at level 5 a sanctuary breach still counts as a breach (the country is marked breached) and a town strike still does its damage, but the level does not move. Warnings then read "Already at the highest level – no further escalation". Escalate, Declare hostilities and Invoke alliance are refused at the cap ("Already at the highest level").

**Collapse.** An army **collapses** when it is broken: its present strength is **35 % or less** of all the strength it has fielded in the operation (formations that joined later count from when they arrived; destroyed ones stay in the total), **or** its strength is 55 % or less while the average readiness of its surviving formations is **25 or less**, or it has no formation left. The rule is the same for both sides.

**The end: the nuclear attack.** Level 6 is reached only one way: **only Russia, only at level 5, only while its army is collapsing,** may take the decision *Use nuclear weapon*. This ends the operation at once, any waiting contact battles are dropped, and **nobody wins** – in a nuclear war there are no winners (Russia is judged to have crossed the line). NATO has no such decision. A full-screen **Operation over** notice says "Russia used a nuclear weapon. The operation ends.", and "Nobody wins.", with a **Back to menu** button. The map first fades to grey and then to black, and the notice appears on the black with a **mushroom-cloud pictogram** above it.

**Borders and movement.** A formation cannot enter a country that is closed to its side: a neutral or hostile country. Such an order is refused. **Russia is closed to NATO until Open war**. The first entry of a formation into the enemy sanctuary raises the escalation level by 1. Attacking out of an aligned country gives the enemy a **casus belli** against that country, shown as a toast. Battles themselves never raise the level.

**On screen.** A chip under the turn bar shows the current level; click it to open the Politics screen, where the ladder is the first block of the **Political overview** (below). Each change of level shows a short notice, such as "Open war – NATO entered enemy sanctuary", or "Calm: level 2 → 1".

**Political decisions.** Instead of waiting for events, you can choose to widen or narrow the war. There are five decisions, the same for both sides, plus Russia's last resort *Use nuclear weapon*. You may take **one decision per turn** (the count resets when your turn starts); a decision is refused while a contact battle is waiting. Open the **Politics screen** with **H** (High command) or the Decisions button on the bottom command bar; the map is dimmed and idle while it is open. Five cards sit in two groups, *Widen the war* and *Keep it small*. Each shows its key (1-5), its escalation cost (LEVEL +1 / LEVEL -1 / FREE), the effect in one line, the countries you can pick (with their stance to you: ally, hostile or neutral) and a Take button; a card that cannot be used is dimmed and says why (amber BLOCKED and the reason). Press **1-5** (**6** for the nuclear card) to pick a card, **left / right** to change the country, **Enter** to take it. A decision that raises or lowers the level asks you to confirm inside the card and shows the new level on the ladder ticks; one that reaches level 5 says so in red ("the highest level of escalation").

**Use nuclear weapon (Russia only).** Russia's Politics screen has a sixth card under *Last resort*; NATO never sees it. It is greyed out with the reason "Only at the highest level of escalation" below level 5, and "Only while the army is collapsing" when Russia is not in collapse. When it can be used, the card, its cost chip and its Take button turn **red**; Take opens a heavy red confirmation – a red **▲ THIS ENDS THE OPERATION** tag and "Use a nuclear weapon? This ends the operation. Russia is judged to have crossed the line." – with a red **Use nuclear weapon** button. It uses the turn's decision and is not blocked by standing down. The header shows decisions left this turn, the level, the stand-down counter and, after a decision, a result line. The right-hand column is the read-only **Political overview** (below). **Esc** (first cancels a confirmation), **X** or **H** close the screen; it also closes when your turn ends.

| Decision | Effect | Escalation cost | Not available when |
|---|---|---|---|
| Escalate | Raises the shared level, which authorises wider strikes | +1 | standing down; already at level 5 (the cap), for both sides |
| Stand down | Lowers the level by 1 and starts a cooldown | -1 | level is already the lowest; you raised the level this turn or last turn; your troops stand in a country you breached or declared hostilities on |
| Declare hostilities (pick a country) | A neutral or aligned country that is not yours goes to war against you (you may now enter it) | +1, free if you already hold a casus belli against it | standing down; the country is yours or already at war with you; the level would go above 5 |
| Invoke alliance (pick a country) | An aligned country of your bloc goes to war on your side | +1 | not your ally, or already at war; standing down; the level would go above 5 |
| Demand neutrality (pick a country) | An ultimatum: a country aligned with the enemy becomes neutral, closed to both sides | none | the country is not hostile to you; it refuses ultimatums; the level is above 2 (Open war or higher); enemy troops stand on its soil |
| Use nuclear weapon (Russia only) | Level 5 → 6: the operation ends, nobody wins | +1 | not Russia; the level is below 5; Russia's army is not collapsing |

**Invoke alliance** is named per side: NATO calls it **Invoke collective defence**, Russia **Invoke the Union State**. Declaring hostilities on a neutral country makes it join the other side. **Lithuania refuses ultimatums**: it is a NATO member with allied troops on its soil, so Demand neutrality on it is always greyed out (the other countries accept).

**Stand down and the cooldown.** After you stand down, you cannot take the escalating decisions (Escalate, Declare hostilities, Invoke alliance) for **2 turns**, counted on the panel. Stand down and Demand neutrality stay available. Calm decay does not raise the level again.

**Political overview.** The right-hand column of the Politics screen shows three read-only blocks; it exists only on the staff map, never in a battle, and nothing in it can be clicked.

- **Escalation ladder.** Folded to your **current level** (name, what may be struck); the **All levels** button unfolds one row per level 0 to 6 with the automatic effect of reaching it (enemy sanctuary opens, allies join, highest level for incidents and decisions, ends the operation), and **Hide levels** folds it again. Level 6 is red. Under the table, each side's **caused** and **de-escalated** counts and the **net** (caused minus de-escalated, never below 0). These are totals for the whole operation, not per level. Below them is your army's **collapse line**, for example "Russia · strength 72 % · readiness 80 · collapse at ≤ 35 %", turning red with **COLLAPSE** while your army is collapsing.
- **Countries.** One row per country: its stance seen from your side (own, allied, neutral, hostile, enemy), whether it is open or closed to you, your formations / the enemy's formations on its soil, and, while its contribution has not come, "N formations when it joins".
- **Event log.** Newest first, at most 60 lines: stance changes, level changes, decisions taken, sanctuary entries and reinforcements arriving, each with its turn ("T3 Level 2 -> 3 Regional war"). "Nothing yet" while empty.

The log and the countries list show **effects only** and never say who decided; only the ladder footer shows what each side caused. The overview refreshes whenever you open the screen and after every political event.

### Deep strikes

As leader you can hit the enemy far behind the front with missiles and drones. A strike is not a battle: it is resolved at once, damages an installation or a formation, and always raises the tension. You launch strikes in **strike mode** on the staff map (see below); the debug panel (F9, `--debug`, block **Strikes**) still works for testing, and **+stock** adds missiles. A hit-chance forecast comes later.

**Weapons.** Strikes use real, named weapons. **A weapon belongs to one side**: NATO and Russia each have their own list, and a side can never fire or be given the other side's weapons. **Stock is per side**: each side keeps its own count of each of its weapons. A strike spends the missiles it launches whether or not they hit. One hex is about 5 km; a range above 120 hexes means "anywhere on the operation map".

NATO:

| Weapon | Type | Range | Largest salvo | Accuracy | Interception | Damage (installation / formation, per hit) | Start stock |
|---|---|---|---|---|---|---|---|
| JASSM-ER | air-launched cruise missile | 925 km (185 hexes, whole map) | 4 | very high (90%) | fairly easy (70% of the normal chance) | 40 / 2 | 6 |
| ATACMS | ballistic missile | 300 km (60 hexes) | 2 | good (80%) | hard (45%) | 35 / 3 | 4 |
| PrSM | ballistic missile | 500 km (100 hexes) | 2 | very high (85%) | hard (40%) | 40 / 3 | 2 |
| Homar-K | rocket artillery | 290 km (58 hexes) | 6 | moderate (70%) | almost normal (90%) | 20 / 2 | 6 |
| Warmate | loitering munition (drone) | 50 km (10 hexes) | 6 | low (60%) | easy (130%) | 8 / 1 | 6 |
| Storm Shadow | cruise missile | 560 km (110 hexes) | 3 | very high (85%) | fairly easy (85%) | 40 / 2 | 0, arrives only from allies |
| Tomahawk | ship-launched cruise missile | 1 600 km (whole map) | 3 | very high (85%) | almost normal (90%) | 40 / 2 | 0, arrives only from allies |

Russia:

| Weapon | Type | Range | Largest salvo | Accuracy | Interception | Damage (installation / formation, per hit) | Start stock |
|---|---|---|---|---|---|---|---|
| Iskander-M | ballistic missile | 500 km (100 hexes) | 2 | good (80%) | hard (40%) | 45 / 3 | 6 |
| Kinzhal | air-launched ballistic missile | 2 000 km (whole map) | 1 | good (75%) | very hard (25%) | 45 / 3 | 2 |
| Kalibr | ship-launched cruise missile | 1 500 km (whole map) | 4 | good (80%) | normal (100%) | 35 / 2 | 4 |
| Kh-101 | air-launched cruise missile | 2 500 km (whole map) | 4 | very high (85%) | fairly easy (80%) | 40 / 2 | 4 |
| Geran-2 | long-range strike drone | 1 800 km (whole map) | 8 | low (55%) | very easy (150%) | 12 / 1 | 16 |

Accuracy is the chance that a missile that was not intercepted hits. "Interception" is how much of the air defence's normal chance applies to the weapon: ballistic missiles are hard to stop, cruise missiles and rockets are closer to normal, drones are easy to stop. "Start stock" is what a side holds when "Suwałki Gap" begins; **arrives only from allies** means the side starts with none and gets that weapon only through outside support (a support package can add it to the stock). The launching platform (ship, aircraft, truck, drone site) does not change the rules, but the map shows it (see **Launch markers** below).

**Launch markers.** Each launch on the staff map shows what fired it at the launch point: a fighter, a bomber, a ship, a truck launcher or a drone site (a submarine silhouette exists but no weapon uses it yet). Next to the marker a label names the platform, for example "fighter-launched (F-16 Block 52+)"; it is readable when you zoom in. A ring at the launch point pulses once as the weapon fires. A launcher, ship or drone site appears about a second before the first missile leaves, stays while the missiles are in flight and then fades out in under a second. An aircraft flies in from behind the launch point facing the target, fires as it passes the ring, then banks away in a U-turn and fades. You see markers only for launches you can see; launches hidden by fog leave none. Several launches from the same hex stack next to each other instead of overlapping.

The launch point is the nearest own site within the weapon's range of the target: an airfield for fighters and bombers, an artillery formation for truck launchers, a sea hex next to your coast for ships (a ship is always shown at sea). If there is no such site, the weapon fires from a standoff point at about its range from your home border. Drones always use the standoff point.

**Stock and resupply.** At the end of each full round (after both blocs have moved) each side receives more of some weapons: NATO 1 JASSM-ER, 1 Homar-K and 1 Warmate; Russia 1 Kh-101 and 2 Geran-2. The other weapons are not resupplied, so use them with care. There is no upper limit.

**Strikes per turn.** Each bloc may make 2 strikes per turn (one strike is one salvo of 1 to the largest salvo at one target). Strikes are separate from the political decisions of the turn. The count is restored when the bloc's turn begins.

**Targets.** You can strike enemy installations that are not yet destroyed, and enemy formations. Installation kinds are airfields, depots, command posts (C2) and air defence; the escalation level decides which kinds may be hit (see the ladder above: formations from level 1, air defence and depots from level 2, airfields and command posts from level 3). A strike is refused with a reason when:
- the target is unknown, already destroyed, or on your own soil;
- the country is **closed**: enemy soil (for example Kaliningrad or Belarus for NATO) stays closed until the level reaches Open war; a country allied with the enemy is likewise closed;
- the level does not yet allow that kind of target;
- the target is **out of range**: the range is counted from the nearest hex of your own country or of a country aligned with you or at war on your side (a country that joins you counts from then on);
- you have too few missiles of that means, a salvo of 0 or above the largest, or no strikes left this turn.

A refused strike costs nothing.

**Interception.** Air defence sites of the target's owner whose reach covers the target hex try to shoot missiles down. There are three types of site:

| Type | Examples | Reach | Cruise | Ballistic | Air-launched ballistic (Kinzhal) | Rocket | Drone | Loitering |
|---|---|---|---|---|---|---|---|---|
| Short-range | Pilica+, Pantsir-S1 | 4 hexes (20 km) | 50% | 0% | 0% | 40% | 60% | 60% |
| Medium-range | NASAMS / Narew, Buk-M3, Tor | 10 hexes (50 km) | 60% | 20% | 10% | 50% | 60% | 50% |
| Long-range | Patriot / Wisła, S-400 | 30 hexes (150 km) | 55% | 50% | 30% | 50% | 40% | 30% |

Short-range sites are good against drones and low-flying cruise missiles but cannot touch ballistic missiles; long-range sites cover a wide area and are the only real answer to ballistic missiles. The figures are first estimates and will be tuned.

Each site's chance is the figure above scaled by its **integrity**, so a damaged site defends worse (a site at 50% integrity has half the chance). **All covering sites act together as one interception roll** per missile: the chances combine (two sites of 50% give 75%), the result is capped at **90%**, and then it is multiplied by the weapon's interception figure from the weapon table (JASSM-ER 70%, Iskander-M 40%, Geran-2 150%, and so on). Every missile is rolled separately: first interception, then, if it got through, the hit. Battles and aircraft are not affected by air defence yet.

**Suppression.** A strike that hits an air defence site without destroying it **silences it for the rest of that round and the whole next round**; a silenced site does not take part in interception at all. It still repairs, can still be hit, and a destroyed site never returns. So striking the air defence first is how you prepare a strike on what it protects.

**Escalation.** Every accepted strike is an incident on the ladder. The first strike into a country that is the enemy's sanctuary raises the level by one (once per country and bloc); a bloc's first strike on a town hex in the operation raises it by one, later ones add nothing. This happens **even if all the missiles were intercepted or missed**. A strike never takes the level above 5 and never ends the operation; at level 5 the confirm card reads "Already at the highest level – no further escalation".

**Damage is lasting.** An installation has integrity from 100 to 0. Each hit takes off the means' damage; at 0 it is **destroyed** and stays so. A damaged but not destroyed installation recovers 5 points at the end of each full round (up to 100). A formation hit loses strength from its strongest company; when all its companies reach 0 the formation is destroyed and removed from the map. What a damaged installation does to battles (fire support, ammunition, command points) is not in the game yet.

**Installations in "Suwałki Gap".** Each side has 8: 2 airfields, 2 depots, a command post and 3 air defence sites. NATO: airfields near Olsztyn and Białystok, depots at Ełk and Kaunas (Lithuania), a command post at Białystok; air defence: long-range at Białystok, short-range at Suwałki, medium-range near Olsztyn (next to the Olsztyn-Mazury airfield). Russia: airfields at Chernyakhovsk and Lida (Belarus), depots at Kaliningrad and Grodno (Belarus), a command post at Kaliningrad; air defence: long-range at Kaliningrad, medium-range at Grodno, short-range at Chernyakhovsk (by the airfield). In practice, at the first level NATO can reach only Russian formations standing in Poland; Kaliningrad targets open at Open war and Belarusian ones at Regional war.

**Installation markers.** The staff map shows every installation of both sides (there is no fog yet) as a small marker in the bloc's colour, with a glyph for its kind (airfield, depot, command post, air defence) and a thin **integrity bar** beneath. A destroyed installation is shown as a grey crossed glyph. Markers update when an installation is hit or repaired. Point at a marker for a card with its name, kind, country, integrity in per cent and what it gives: an airfield – fire support in nearby battles, and similarly for the other kinds.

**Strike mode.** Press **S**, or click the **STRIKE** button on the bottom bar, to open strike mode. **Esc** or the **✕** in the panel corner leaves it. Strike mode also closes by itself once a strike has been launched (press **S** again for the next one); a rejected strike keeps it open.
- **Panel.** A docked window on the right, titled "STRIKE" with your side's name in its colour. It lists **only your own side's weapons**, one row each: a small **glyph** of the weapon's kind (ballistic missile, cruise missile, rocket, drone, loitering munition), the name, a line with the designation, the class and the **range in km**, and your **stock** on the right. Rows with stock first, then by range (longest first). A weapon you have none of (Storm Shadow and Tomahawk until allies deliver them) stays in the list **greyed with "ALLIES ONLY"** and cannot be picked (clicking it says it arrives only from allies). A range above 120 hexes reads "WHOLE MAP", for example JASSM-ER.
- **Weapon card.** Under the list a detail card follows the weapon you point at, then the one you picked, then the first row. It shows the weapon as an amber technical drawing (side view with a grid and its real length, diameter and, for winged weapons, wingspan) and four chips: **RANGE**, **SALVO** (largest salvo), **ACCURACY** and **INTERCEPT** (HARD for 50% or less, NORMAL up to 110%, EASY above), plus a platform line; point at it for the long wording ("hard to intercept").
- **Salvo.** Pick a weapon, then set the salvo with the stepper (1 up to the largest salvo, never more than your stock). The hint and the confirm card name the weapon, for example "3 × JASSM-ER on Chernyakhovsk airfield". The panel also shows **Strikes: n/N**, the strikes you still have this turn.
- **Targets.** Every legal target is marked with a double ring in your side colour. An **amber** target is *conditional*: it becomes legal only after you raise the escalation level (raise-and-strike); the strike then includes an Escalate decision first (for airfields it starts from level 1). Illegal targets are **dimmed**; point at one to see the reason (closed country, level too low, out of range, too few missiles and so on).
- **Confirm card.** Clicking a legal target opens a card with the means, salvo and target, the escalation lines (what the strike and any needed Escalate raise, or "Already at the highest level – no further escalation" at level 5). Confirm to launch, or cancel; a cancelled strike costs nothing.
- **Closing.** The strike panel and the confirm card each have an **X** in the corner; it does the same as Esc or cancel.
- **Result report.** About 0.4 s after the strike, a **strike result report card** appears on the left, under the turn bar. It shows:
  - the weapon name and ×N (the salvo) and the target;
  - one pictogram per missile: a solid disc with ✕ is a **hit**, a ring with a bar is **intercepted**, a dashed ring is a **miss**, with the count of each;
  - the target's **integrity** (installation) or **strength** (formation), before → after;
  - the interceptor sites that fired, with counts;
  - the escalation ticks with the new level, and lines such as "+n sanctuary breach" or "+n urban hex";
  - your stock of that means before → after, and "strikes left" this turn.

- **Card behaviour.** After 9 s the card collapses to a small **chip** (pointing at the card or chip pauses the timer). **Enter** (or a click on the card or the chip) opens the **Journal** at this strike's line, **Esc** collapses the card, and **◂ ▸** browse the earlier reports. The chip is a compact tab (weapon ×N and a short result such as "2 HIT") placed under the turn bar's button row at the left edge; it never covers other HUD. The **X** on the card or chip dismisses it.
- **Enemy strikes.** Strikes by the other bloc during its turn appear one after another, 3.5 s each, marked "1/n" on the chip. Their stock is unknown, so it is not shown. All reports are cleared when your next turn begins.
- **Arcs and impacts.** Each missile flies its own arc: a hit ends at the target, an intercepted missile bursts in mid-air at an air-defence site, and a miss lands beside the target. The impact looks different for an installation, a formation and a town hex. The traces stay on the map until your next turn begins, and at most 8 are kept (a whole salvo counts as one; the oldest drop first), and they keep the weapon's arc.
- **Reading a trace.** Every missile of a salvo is drawn separately (at most 6 are drawn; a "+n" at the target counts the rest), launched a fraction of a second after the previous one, in your side's colour with a head in the weapon's glyph. The shape tells the weapon apart at a glance: a **ballistic** missile (ATACMS, PrSM, Iskander-M, Kinzhal) climbs in a **high arc** and arrives very fast, Kinzhal the fastest with a lower arc; a **cruise** missile (JASSM-ER, Storm Shadow, Tomahawk, Kalibr, Kh-101) flies **low and flat** on a thin long line; a **drone** (Geran-2, Warmate) crawls slowly on a low **wobbling dotted** line; a **rocket** (Homar-K) makes a **short, thick** medium arc. On a short strike every flight takes about the same minimum time, so compare the weapons on long shots.
- **How a missile ends.** A trace that **stops short** of the target (about 70% of the way, with the interception mark) was **intercepted**. A small **puff of dust beside the target** is a **miss**. A hit ends in a burst: a **blast** for cruise missiles, a **heavy blast** with a second shockwave for ballistic ones, a small flash without smoke for drones, and a scatter of **cluster bomblets** for Homar-K rockets.

**Strike forecast.** The confirm card shows two rows under the interception line. **Expected hits** is the average number of missiles that get through the air defence and hit (after interception and the weapon's accuracy), with the chance that **at least one hit** lands, i.e. that the strike achieves anything. The second row is the average result on the target: **Expected integrity 100 → 41** for an installation or **Expected loss ~3 strength** for a formation, followed by **destroyed ~N%** when there is a chance to destroy it. These are **averages, not guarantees**: a single strike can do much better or worse. The forecast follows the salvo size and air-defence suppression, uses the capped salvo when your stock is lower than the salvo, and is not shown for targets you cannot strike.

### Air defence on the map

Press **C**, or use the **Air defence cover** row in the map options, to show where air defence reaches. It is off at the start. While you have a weapon picked in strike mode the overlay shows by itself, and when strike mode closes the map returns to the state it had before.
- **Zones.** Each air defence site draws its reach as a **solid zone in its owner's colour**. A **suppressed** site's zone is drawn **dashed, grey and hatched**.
- **Marker.** A suppressed site's marker turns **grey with an amber slash** and shows the **number of rounds left** until it fires again.
- **Hover card.** Pointing at a site shows its type with examples, its reach, and for a suppressed one "Suppressed – n rounds left".
- **Odds line.** The confirm card shows the forecast for the target: "Interception ~X% per missile", "Air defence suppressed" or "No air defence cover". The strike panel shows the same as an **AT TARGET** chip.
- **Report.** When a strike silences a site, the report card adds "Suppressed for n rounds".

### Turns

The operation is played in turns of 12 hours. Each turn both blocs move, one after the other: in "Suwałki Gap" Russia moves first, then NATO, and then the next turn begins. The **turn bar** at the top centre shows the bloc you are viewing with its number of formations, the turn number, the date, whether the turn is day (odd turns, 06:00–18:00, sun) or night (even turns, 18:00–06:00, moon), and which bloc is to move. **End turn** (or **Enter**) hands the move to the other bloc; a banner names the bloc to move. The button is greyed out, with a tooltip, while a contact battle is waiting to be fought.

You can play both blocs. NATO is always blue and Russia always red, whoever is viewing. Your own formations are drawn as rectangles with a cut corner and the enemy's as diamonds; the view stays on the bloc you picked after each End turn. `--side=nato` or `--side=russia` picks the bloc you start with. Ending a turn carries out your orders (see **End of turn**); the enemy playing by itself comes later.

### Formations

The operation "Suwałki Gap" places 18 battalions on the map: eight Polish (NATO) – two facing the Kaliningrad oblast near Bartoszyce and Lidzbark Warmiński, three in the Gap around Suwałki, Augustów and Ełk, three facing Belarus around Białystok, Sokółka and Mońki – and ten Russian, five in the Kaliningrad oblast (Chernyakhovsk, Gusev, Sovetsk, Nesterov, Gvardeysk) and five in Belarus around Grodno. You view the map as NATO; starting the game with `--side=russia` shows it from the Russian side instead.

**Counters.** Each formation is a counter of fixed size on screen (it does not grow or shrink with the zoom), standing on its hex:

| Part of the counter | Meaning |
|---|---|
| Rectangle with a cut corner | your formation |
| Diamond | enemy formation |
| Blue / red fill | NATO / Russia (never swapped) |
| Cross with an oval inside | mechanised infantry (or motor rifle) battalion |
| Oval | tank battalion |
| Dot between two upward arrows | rocket artillery (MLRS) |
| `II` above | battalion |
| Number beside, e.g. `2/15` | battalion / its brigade or higher formation (2nd battalion of the 15th Mechanised Brigade) |
| Five slanted bars below | strength: lit bars ≈ fifths of full strength (rounded; one bar stays lit while anything is left). Green from 75 %, yellow from 50 %, red below |
| Darker fill with a red outline | low strength (below half) |
| Small number in an amber box at the top-right | a stack: that many formations of the same side stand so close on screen that only one counter is shown – zoom in to separate them |
| Amber corner brackets | the selected formation |

Pointing at a counter brightens it; the hex card keeps working underneath.

**The six formation types.**

| Type | Side | Companies | Strength |
|---|---|---|---|
| Mechanised Battalion | NATO | 3 × Mechanised Infantry Squad, 1 × M1A2 SEPv3 Abrams | 40 |
| Tank Battalion | NATO | 3 × M1A2 SEPv3 Abrams, 1 × Mechanised Infantry Squad | 40 |
| Rocket Artillery Squadron | NATO | 3 × Homar-K | 18 |
| Motor Rifle Battalion | Russia | 3 × Motor Rifle Squad, 1 × T-72B3 | 38 |
| Tank Battalion | Russia | 3 × T-72B3, 1 × Motor Rifle Squad | 34 |
| MLRS Battalion | Russia | 3 × 9K57 Uragan | 18 |

Strength is the sum of the companies' hit points – the same units that fight when a battle starts.

**Formation panel.** Clicking a counter opens the panel on the right edge: name, the brigade or corps above it, type, side (enemy formations are marked **HOSTILE** in red – for now you see everything about them; reconnaissance and fog come later), total strength with the five bars, location (hex coordinate as on the hex card) and the companies, each with its unit type, strength and reference (e.g. `pl_mech_1/4` – the 4th company of the 1st Mechanised Battalion). **Tab** jumps to your next formation (the camera moves to it if it is off screen); Esc or a click on empty map closes the panel. The panel has an **✕** in its corner that does the same.

**Docked windows.** The map options, the country card, strike reports and the formation panel share one frame: a tab, an ✕ in the corner, the same dark plate. Left-edge windows come one at a time (opening one closes the other); the formation panel docks on the side opposite the selected counter (on the right when the left edge is taken, then the map eases the unit clear of it), and the map never lets the top and bottom bars hide a unit: you can always pan it fully into view. A click on the map, **Esc** or the ✕ closes them, and the bottom-bar button that opened a window stays lit while it is open.

### Front line

A thick light line with small teeth runs between the two blocs. It is a **display, not a rule**: every land hex within 3 hexes of a formation counts as held by the side of the *nearest* formation (a tie, water and hexes out of reach are held by nobody), and the line follows the border between the two zones. The teeth point towards the enemy as seen by the side you view the map from, so they swap sides when the viewer changes. The line is smoothed; with the grid shown (**G**) at the closest zoom it follows the exact hex edges. It is redrawn after every move and while the counters slide it is hidden. Press **T** to show or hide a very faint blue / red tint of each side's zone (on at the start). There is no line while the blocs are further than 6 hexes apart.

### Orders

With one of your formations selected, point at a hex to see how it would get there, and left click to order it there. A formation has at most one order; a new order replaces the old one. Orders are carried out when you end your turn (see **End of turn**).

**Giving an order.** With one of your formations selected (on your turn), **left click** a hex to send it there: the default order is **March**, whatever the formation did before. **Right click** a hex to open the **order ring** on it, the same ring as the unit ring in battle (it follows the hex when you pan, zoom or tilt, and stays on screen):

| Segment | Order |
|---|---|
| 1 MARCH | go there, around enemy zones of control |
| 2 ATTACK | go there and attack, entering enemy zones and stopping in contact |
| 3 DEFEND | go there in the defensive posture, around enemy zones |
| 4 CANCEL ORDER | only while the formation has an order: drop it |

Hovering a segment shows a card with what the posture does, the route cost, the points per turn, the number of turns and how the route ends (arrived / contact / no progress), and the route preview on the map switches to that posture. Click a segment or press **1-4** to give the order; **Esc**, a click elsewhere or another right click closes the ring. On an enemy-held hex only ATTACK is available; a segment that cannot be used is dimmed and its card says why (UNAVAILABLE and the reason). A short message confirms "Order given", or says why the order was refused:

- a contact battle has to be fought first;
- not your formation;
- cannot go there (for example a lake);
- hex occupied (another of your formations stands on the target);
- only the Attack posture can target an enemy formation (March and Defend refuse it);
- no route in this posture (for example, the way is blocked by enemy zones of control while marching);
- already in this posture (when you pick the posture it already has);
- the country is closed to you (neutral or hostile; see **Borders and movement** under Politics).

**Attacking.** Select your formation and **left click** the enemy counter (or its hex), or right click the enemy hex and choose 2 ATTACK. The formation marches towards it, never enters the enemy hex, stops next to it ("contact") and the battle starts at the end of your turn. If it is already next to the enemy, it does not move and fights at the end of the turn. The order stays after the battle, so an undecided fight is repeated next turn. If the enemy has moved away by then, the formation simply goes to the hex it left; if one of your own formations stands there, the order is dropped.

**Postures.** The formation panel of your own formations (not the enemy's) has two extra rows, **POSTURE** (the posture of the last order you gave it) and **POINTS**. The posture comes with the order: choose it in the order ring. The points are what the formation can spend in one turn (for a formation with 8 move points):

| Key | Posture | Points | Enemy zone of control |
|---|---|---|---|
| ring 1 | March | 8 (100 %) | the route goes around it |
| ring 2 | Attack | 6 (75 %) | the route may enter it, but the formation stops there ("contact") |
| ring 3 | Defend | 4 (50 %) | the route goes around it |

Giving a new order replaces the old one.

**Cancelling.** With the formation selected, choose 4 CANCEL ORDER in the ring, or press **Delete**, **Backspace** or **X**. The message "Order cancelled" appears, or "No order to cancel" if it had none.

**Reading the orders.** March orders are drawn as a dashed line, attack orders as a solid line. A defend order is a line that ends in a defence arc at the destination. Each **+n** cross-bar marks where the formation will stand after n turns (the per-turn stops). Orders you have issued are drawn slightly faded (82 % opacity) so they differ from the preview; the enemy's orders are never shown. A counter with an order carries a small amber tab. The **End turn** button shows **ORDERS n / m**: n of your m formations have an order.

**Step costs.** Road 1, open ground and towns 2, forest and hills 3, marsh 4. Crossing a river without a bridge costs +2 more. Lakes cannot be crossed. Only one formation can stand in a hex, but you can pass through your own formations. The zone of control is the ring of hexes next to an enemy formation. Unused points are lost at the end of the turn, and a formation can always move at least one hex per turn, even if that costs more than its points.

**Reading the preview.** Before you click, a ribbon runs along the route. A label at the target gives the total cost, the number of turns and the reason the route ends there (for example, arrival or contact). If there is no way, a red cross with the reason appears: a lake, an enemy formation on the target hex, a country closed to you, or no route. A route that crosses a closed country shows a red cross there. At the first hex of each incident (entering the enemy sanctuary, or attacking out of an aligned country) the route shows an amber warning triangle with a label. An order with an incident needs confirmation: **Enter** confirms, **Esc** cancels.

### End of turn

When you press **End turn**, your orders are carried out one formation at a time, in the order of battle. Each formation spends its points for the turn on its route and slides along it. **Space** or a click skips the slide.

An order stays on the formation: it keeps following it on later turns until one of these happens.

- **Arrived** – the formation reaches the destination and the order is done.
- **Contact** – a formation in the Advance posture comes next to an enemy and halts. It keeps its order.
- **Dropped** – the order is cancelled and reported when the destination has been taken, no route is left, or the way is blocked by your own formations. If a country on the way has become closed, the report says "Order dropped: country closed".
- **Halted** – a formation that would attack into a country it may not attack into stops, and the report says "Halted – cannot attack into <country>".

**Turn report.** After the turn, press **R** to open (or close) the turn report: one row per order carried out, with what happened to it. Click a row to centre the map on that formation.

**Journal.** Press **J** (or the log book button on the bottom bar) to read what happened to your side, turn by turn. The window sits on the left edge like the turn report; only one such window is open at a time. Entries are grouped under a header for each turn (`TURN 5`, the date and DAY or NIGHT with its hours; the current turn carries **NOW**), newest turn first, and every entry of the operation is kept. Each entry has a shape (a square for your side, a diamond for the enemy, a circle for politics), a tag (STR strikes, BTL battles, MOV moves, POL politics), a sentence in your side's words ("We struck the enemy airfield with Iskander-M ×2: 2 hit, 1 intercepted", "Enemy … on our depot") and the place. The journal writes down everything your side did and what the enemy did **to you** (a strike or a battle against you, an enemy halted in contact with your formation); enemy moves far away are not written. Political lines are bare facts (a country moved to a side, the escalation level changed, a decision taken) and never say who decided. The chips **ALL / STRIKES / BATTLES / MOVES / POLITICS** filter the list. Click an entry that has a place and the map centres on it and rings the hex for two seconds. Entries added since you last closed the window carry a thin amber bar on the left until you point at them. In a strike report, **Enter** (or a click on the card or chip) opens the journal at that strike's line.

### The opponent's leader

The enemy leader is played by the computer. On its turn it gives formation orders, launches strikes and takes political decisions, all under the same rules as you: the same costs, closed countries, incidents and limits. Its turn plays out at once after you press **End turn**; there is nothing to click.
The computer never decides for you whether a battle is played or auto-resolved: for every contact you choose **Play battle** or **Auto-resolve**. In a played battle the enemy companies go for the objectives. Start the game with `--hotseat` to keep both sides human-controlled.

### Contact

A **contact** starts a battle. At the end of a turn, after all orders are carried out, every formation that halted because of contact (see **End of turn**) attacks an enemy formation standing next to it. Arriving next to an enemy at the end of an order does not start a battle. Each formation takes part in at most one battle per turn; a formation left out stays halted, keeps its order and is checked again next turn. Right now every contact leads to a battle (a border rule and fog of war come later).

**Sides and conditions.** The formation that halted is the **attacker**; its mission is *Attack* and its goal is the hex it was heading for. The formation it hit is the **defender**: its mission is *Defend*, unless it was in the March posture, when it is *Caught on the march* (mission *Hold out*). The battle takes place on the terrain of the defender's hex. Each side brings the companies of its formation at their current strength, and its posture gives a position bonus for the battle: **Defend +1**, **Advance 0**, **March −1**.

**The battlefield.** The battle is fought on the real terrain around the contact point – roads, rivers, lakes and forest – on an area of about 10 × 7.5 km. The defender holds the objective hex in the centre of the map; the attacker must take it by ending its turn on that hex. The battle lasts at most 12 turns from the first contact. If the limit runs out (a draw), the defender holds.

**The contact notice.** When a battle is pending the camera centres on the defender's hex and the map dims. A card appears in the middle of the screen (a dashed ring marks the hex), titled "Attack – Suwałki, 5 km east" (you attack) or "Enemy attack – …" (the enemy attacks you) – the place is the nearest town or village of the map with the distance and direction from it (the bare name when it is closer than 1.5 km; the hex number when the map has no places). It shows both sides (your frame is a rectangle, the enemy's a diamond), with their names, role, posture and strength, the forces as a ratio of attacker to defender strength, the place and the attacker's mission.

**The queue.** If several battles start in one turn, a list on the left shows them (for example `1 OF 2`) with the active one marked. The notice always shows the first; when it is settled, the next appears.

**What you can do.** While a battle is pending you cannot give orders or end the turn. Press **Play battle** (or **B**) to fight it yourself. Started with `--debug`, the card also has **Resolve as draw (debug)**, which settles the battle as a draw with every company at its starting strength; the dimming ends and End turn works again.

**Auto-resolve.** Instead of playing, press **Auto-resolve** on the card to let the staff settle the battle at once, with no penalty. It uses the same companies at their current strength, the postures (Defend +1, Advance 0, March −1 to the defender's defense), the defender's terrain and the command points. The companies fire in up to 12 rounds with the same dice as in a played battle. A side that has lost nine tenths of its strength breaks, and the other side wins at once; if 12 rounds pass with neither side broken, the defender holds. A battle can be auto-resolved only from the contact card: a battle you started to play cannot be switched to auto-resolve.

**Two roles, one player.** On the staff map you are the **leader** – the government and general staff: you give the formations their orders and decide which battles to fight. In a battle you are the **commander** of the companies on the field: you move and fight them to carry out the mission the leader's order gave you, and you cannot change the forces, the terrain, the objectives or anything on the staff map from there. The result of the battle is your report back to the leader.

**Playing the battle.** The 3D battle opens on the real terrain around the contact, with exactly the companies of the two formations at their current strength (the formation panel on the staff map lists the same ones). You command the side you were viewing on the staff map; the enemy is played by the computer. A **briefing** opens first: the formation you command, your **Mission** – the task (Attack, Defend or Hold out) and the objectives in words (take or hold the objective hex, or destroy every enemy company, and the turn the battle ends) – and the **Intent**, the leader's order behind it (for example "Advance to hex 06·01"). Press **Take command** (or **Enter**) to start. During the battle a line under the turn bar reminds you of the mission.

**How a battle ends.** As any battle: the attacker takes the objective, one side destroys the other, or the turn limit runs out (then the defender holds the field). The end screen is your **commander's report** with the result; press **Report to staff** (or **Enter**).

**Back on the staff map.** The staff map comes back as you left it – the same camera, selection and view settings – and a short **battle result** card shows the winner and, for each formation, its companies' total strength before and after the battle. After an auto-resolve the same card also gives the reason for the result (for example, a side broke or the rounds ran out) and says who holds the field and which side retreats. Below the winner it has an **after-action report** (see below). Press **Continue** (or **Enter**). The battle is closed, the dimming ends and, when no other battle waits, you can end the turn. Leaving a battle with **Esc** returns to the main menu and ends the operation without a result.

**After the battle.** The result is applied to the staff map as soon as the battle is settled. A battle you played and one you auto-resolved count exactly the same: only the final state of the companies and who holds the field matter, not how the battle was fought.

- **Losses by company.** Every company keeps the strength it ended the battle with. Strength lost in the battle stays lost on the staff map: the formation is weaker in later battles and its strength total drops. A company reduced to 0 is removed from the formation.
- **Destroyed.** A formation that has no company left is destroyed and disappears from the map.
- **Retreat.** The side that did not hold the field retreats one hex. It goes to a free, passable neighbouring hex, preferring one outside the enemy zones of control and, among those, the one farthest from the enemy. The formation's order is cancelled (reported as "retreated"). If there is no such hex it stays where it is and the report says the retreat is blocked. The winner stays in place and keeps its order. A beaten formation never retreats into a country closed to it.
- **Closed countries.** No battle is fought against a formation standing in a country closed to the attacker; your advance still stops there (contact), but nothing is fought. Battles never raise the escalation level.
- **Readiness.** Every formation has a readiness of 0–100 %, starting at 100 %. Taking part in a battle costs readiness: **15 points for the attacker, 10 for the defender**, whoever wins. At the start of your next turn, a formation that did not fight since your previous turn began regains **10 points** (up to 100 %); a formation that fought does not recover that turn.
- **Readiness and movement.** A formation's move points for a turn under an order are its posture's allowance scaled by its readiness, rounded down and never below 1. Readiness never counts as less than **40 %**, so even an exhausted formation moves at least 40 % of the normal distance. The route preview and the carried-out order use the same figure.

**The after-action report.** The battle result card now lists, for each side (the attacker first), a line with the formation name, its strength before and after (with a bar) and its readiness before and after (for example "READINESS 100 → 85"). The end of the line shows what happened to it: **RETREATED TO** a hex, **RETREAT BLOCKED**, or **DESTROYED** (instead of the readiness). The line **Losses: own N · enemy M** adds up the strength points lost by your companies and by the enemy's in this battle. The strip above it names who holds the field and who retreats. Formations that do not appear in the battle are not affected.

### Saving

**Saving.** Press **F5** or the **SAVE** button on the staff map to save the whole operation: the turn, every formation and its order, the politics, a battle waiting to be fought, and the battles already fought. A "Saved" message confirms it. There is one save slot for the operation "Suwałki Gap": a new save replaces the old one. Saving does not end the turn and you can save as often as you like.

**Continue.** The **Continue** button at the top of the main menu loads the save and opens the staff map exactly where you left off, viewed from the side you were viewing when you saved. When there is no save yet the button is greyed out and says "No saved campaign yet". If the save file is damaged, the message "The saved campaign is damaged" appears and nothing is loaded.

**A pending battle.** If a contact battle was waiting when you saved, it is saved too: after Continue the map is dimmed again and the contact notice comes back, so you can play the battle as before.

**Limits.** A battle in progress cannot be saved: **F5** in the battle scene only writes the match record (section 11), not the operation, so finish the battle (or return to the staff map) first. The view is not saved: the camera position, zoom and tilt, the selection and the display toggles (grid, borders, zone tint) start from their defaults after Continue.

Map data: © OpenStreetMap contributors (ODbL); elevation © DLR e.V. / Airbus Defence and Space, provided under Copernicus by the European Union and ESA. Full credits: `data/maps/CREDITS`.

## 12c. Objectives, scoring and the end of an operation

**Starting.** The side window lists **NATO first, then Russia**. The choice decides whose side you see and command; it changes nothing in the operation itself (same map, same forces, same rules; the AI plays the other side). Starting the game with `--side=nato` or `--side=russia` skips the window; an unknown value shows it as usual. A save remembers your side.

**Who holds a hex.** The last side that had a formation on a hex holds it. Points are counted only when the operation ends.

**Points** (from `data/operations/suwalki_gap.tres`):

- Chernyakhovsk airfield 5 for NATO while NATO holds it; Białystok command post 5 and Vilnius 5 for Russia while Russia holds them.
- Grodno depot 40 for whoever holds it at the end.
- The **Gap road link** (the chain of road hexes through the Suwałki Gap): **open** at the end = 10 for NATO, **closed** (every hex of the chain held by Russia) = 10 for Russia.
- **Escalation**: −3 for each net step of the ladder a side caused (steps it took back count against that).

**Endings.** Russia wins at once when the Gap stays closed for **2 full rounds** in a row. After **30 rounds** the totals decide: the higher total wins; a difference under **5** is a draw. A nuclear attack ends the operation and nobody wins (a defeat for the side that used it).

**The end notice.** When the operation ends a window shows the headline for your side – **Victory**, **Defeat**, **Draw** or, for the opponent's nuclear attack, **Nobody wins** – the reason, the rounds played and a table of points per side (objectives, escalation, total). **Review map** closes the window; the map stays readable but no orders can be given. **Back to menu** leaves the operation. Loading a save of an ended operation shows the same window once.

## 13. Not in the game yet

To avoid confusion – these are **not** part of the current game: fog of war (you always see all enemy units), healing or repairing, elevation effects, ammunition, unit experience, vehicles carrying the infantry squads, different maps, choosing your country or army, choosing the battle in the menu (the objective battle is only a start option), victory points, a graphics settings menu, music, and saving/loading a match to continue later. On real-terrain maps: bridges over lakes and wide rivers (a road across water does not make it passable), houses in villages, and field or forest tracks as roads.
