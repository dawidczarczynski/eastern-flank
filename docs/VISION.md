# Eastern Flank – Game Vision

> English version of the human's vision document "Eastern Flank – Dokument Wizji Gry" (working draft, 2026), added 2026-10-30. It sets the direction; the decided rules live in [GDD.md](GDD.md), the work in [tasks/BACKLOG.md](tasks/BACKLOG.md). Decisions taken while reviewing it are in GDD "Vision decisions (2026-10-30)".

## 1. Basics

- **Working title:** Eastern Flank
- **Genre:** classic turn-based strategy (I-go-you-go)
- **Theme:** a present-day military confrontation between NATO and Russia on Europe's eastern flank
- **Core feeling:** the player runs a real military operation, not a series of disconnected tactical battles
- **Priority:** decision realism – every serious decision has a cost, a risk and consequences

## 2. Structure – two maps

### 2.1. Operational map (the main scene)

The centre of the game; the player spends most of the time here.

- Movement of formations (battalion / brigade level)
- Logistics and supply
- Reconnaissance
- Air defence and electronic warfare (EW) management
- **Deep strikes** – a full, important action (not a meta-game)
- Reacting to the enemy's deep strikes
- Political events and their consequences

**Deep strikes:**

- The player picks the means (cruise and ballistic missiles, aircraft, strike drones, …) and the targets.
- Effectiveness depends on reconnaissance, SEAD, the enemy's air defence, the quality of the means and chance.
- Effects are visible on the operational map at once.
- Effects last and shape later tactical battles (a damaged airfield = less air support, a damaged depot = ammunition problems, a strike on C2 = a longer command delay).

Deep strikes are expensive, risky and strategically important. Both running your own strikes and defending against the enemy's are key parts of the game.

### 2.2. Tactical map (battle)

Starts when formations make contact on the operational map.

- Classic turn system (I-go-you-go)
- Combat at platoon / company level
- Continuous WARNO-style zoom: far out → tactical symbols, close in → detailed 3D models
- Battle conditions depend strongly on the operational situation (deep strikes, supply, C2 state, morale, air support, equipment shortages)
- Maps large enough for realistic tube and rocket artillery use

**Planned tactical systems (after the MVP):**

| System | Role |
|---|---|
| **Drones** (recon, strike, FPV, larger) | Reconnaissance, precision strikes, wearing down defences |
| **Electronic warfare (EW)** | Jamming communications, drones, radars and guidance |
| **SIGINT / ELINT** | Locating radars, communications and command posts |
| **Camouflage** | Making units and positions harder to detect |
| **Digging in / field fortification** | Survivability at the cost of time and mobility |
| **Artillery radars + counter-battery fire** | Finding and destroying enemy artillery |
| **Attack and transport helicopters** | Fire support, air assault, evacuation, logistics |
| **Aircraft and bombing** | Close air support (CAS), battlefield isolation |
| **Mining** | Channelling and slowing the enemy, protecting flanks |

**Realism rules for tactical systems:**

- Drones are effective but very vulnerable to EW and short-range air defence.
- Artillery is very dangerous but can be located – mobility and counter-battery radars matter.
- Camouflage and fortification cost time – survivability vs. mobility.
- EW cuts both ways (it can jam your own or allied systems).
- Aircraft and helicopters need the right conditions (suppressed air defence, limited EW, an operational window).

## 3. Strategic systems

### 3.1. Technology tree

Realistic paths, e.g. C4ISR / reconnaissance, EW, precision weapons, logistics and mobility, air defence, doctrine and training. It unlocks new deep strike means, better defence against them and upgrades for ground formations.

### 3.2. Building the army

- Mobilisation and replacements
- Production limited by time, resources and politics
- Quality of formations and rebuilding losses rather than mass production

### 3.3. Political events

Examples: escalation / de-escalation, allied support, ROE (rules of engagement) limits, internal problems, international incidents. Events strongly shape how aggressively deep strikes may be used and what striking sensitive targets costs.

## 4. Core loops

1. On the operational map the player shapes the situation (formation moves + deep strikes + rear-area defence).
2. Formations make contact → switch to the tactical map.
3. The battle is fought in the conditions shaped at the operational level.
4. The result goes back to the operational map (losses, fatigue, change of initiative).
5. Technology and political decisions change the available tools and limits over time.

## 5. Target feelings

- Deep strikes are one of the main tools of war.
- Every serious decision has a real cost and consequences.
- Ground combat matters but is rarely decided in isolation from operational actions.
- The player feels the difference between NATO and Russian doctrine.
- Precision weapons, missiles and air support are valuable and limited.

## 6. Project state at the time of writing

A small tactical map; 3 unit types per side (infantry, tank, rocket artillery); basic movement and combat; terrain generation; 3D hex view.

## 7. MVP scope

- **Operational map:** one small/medium map, formation movement, simplified logistics, deep strikes (2–3 kinds of means, several target types, simple resolution), basic defence against deep strikes.
- **Tactical map:** the existing map as the base, classic turns, operational effects carried into battle conditions, basic fog of war and a simplified C2 delay.
- **Strategic systems (minimal):** a simplified tech tree (3–4 paths), basic replacement / reinforcement of formations, a few political events.
- **AI:** classic operational and tactical AI, no LLM in the MVP.
- **Content:** NATO (e.g. Poland + support) vs. Russia, 1–2 scenarios or a short campaign.
- **Deliberately outside the MVP:** a full deep tech tree, an advanced economy and production, WeGo, a local LLM, a full tactical-symbol LOD system, many units and maps, the advanced tactical systems (drones, EW, counter-battery, helicopters, aircraft, mining, fortifications) – added in stages after the MVP.

## 8. MVP success criteria

1. Deep strikes feel important and the player really weighs them in decisions.
2. Tactical battle conditions clearly depend on operational actions.
3. The basic loop "operation → deep strikes → battle → consequences" is satisfying.
4. The game stays readable and keeps a good pace.

## 9. Recommended order

**Phase 1 – MVP (core loop):** simple operational map + formation movement → contact → tactical battle → minimal deep strikes and their effects → formation state carried into the battle → basic AI on both layers → minimal tech tree and events → polishing the loop and balance.

**Phase 2 – tactical layer expansion (after the MVP):** larger tactical maps + realistic artillery ranges → recon and strike/FPV drones → camouflage and digging in → artillery radars + counter-battery fire → basic EW → attack and transport helicopters → tactical aviation and bombing → mining → SIGINT/ELINT.
