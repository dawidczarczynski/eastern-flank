# TASK-132: Baltic naval operations – NATO navies vs the Russian Baltic Fleet

- **Status**: idea
- **Topic**: Baltic naval operations (epic, after the MVP)
- **Epic**: yes – a separate topic outside the `mvp` tag (human, 2026-11-10); `/refine-task` splits it into 132a, 132b, … child tasks, and this file stays as the epic overview
- **Layers**: core / ai / presentation (to be split when refined, e.g. 132a naval core, 132b sea/air/missile strikes, 132c UI + AI)
- **Depends on**: TASK-092b, TASK-092c, TASK-092d, TASK-092e (operational core); soft: TASK-097a (deep strike), TASK-114, TASK-115, TASK-118, TASK-122
- **Sections**: GDD "Operational layer", "Theatre", "Escalation ladder", "Outside support" (via `tools/doc.py gdd`), ARCHITECTURE "Commands"
- **Model**: opus

## Why

Kaliningrad is Russia's Baltic bastion: the Baltic Fleet at Baltiysk, coastal anti-ship missiles (Bastion-P, Bal) and anti-air (S-400) cover the sea and the Gap's flank. Sea lines of communication (Gdynia, Karlskrona–Gotland–Bornholm, the Danish Straits, Finland / the Gulf of Finland) decide reinforcement and supply. Without the naval dimension the Kaliningrad scenario is unrealistic (human, 2026-11-10).

## Goal

The player commands (or faces) a small naval and maritime-air campaign in the Baltic next to the land operation: sea control decides supply, reinforcement and fire support at the coast.

## Sides (first guess, to refine)

- **NATO**: Polish Navy (Gdynia; Kormoran II mine hunters, Orka submarines, Miecznik frigates, NSM Coastal Missile Unit), German Navy (Corvettes K130, F125 / F126 frigates, mine countermeasure vessels, Kiel), Swedish Navy (Visby corvettes, Gotland submarines, Karlskrona; Gotland island), Finnish Navy (Hamina missile boats, Pohjanmaa minelayers, Gulf of Finland), Danish Navy (Absalon / Iver Huitfeldt, the Straits and Bornholm). Allied maritime air: Poland / Germany / Sweden / Denmark / Finland (F-16, Gripen, F-35, Eurofighter, P-8, NSM-armed aircraft). Which nations are playable as AI-controlled allies vs. commanded: **[open]**.
- **Russia**: Baltic Fleet (Baltiysk; Karakurt and Buyan-M missile corvettes with Kalibr, Steregushchiy corvettes, Gepard frigates, minelayers, landing ships), Kaliningrad coastal defence (Bastion-P / Bal anti-ship missiles, S-400, Iskander), naval aviation (Su-30SM, Su-24 / Su-34).

## Topics (each to become acceptance criteria when refined)

1. **Mining** – both sides lay mines (sea lanes, ports, the Straits, the Gulf of Finland approaches); mine clearing by minehunters takes time; mines damage / sink ships; minefields are hidden until detected **[open]**.
2. **Blockades** – sea-lane and port blockade (Baltiysk, Gdynia / Gdańsk, the Straits); effects on supply, reinforcements and outside support; an escalation cost on the shared ladder (TASK-115).
3. **Missile corvettes** – small surface ships with anti-ship and land-attack missiles (Kalibr vs NSM / RBS-15 / Harpoon); ranges in km, salvos, magazine depth, stealth / detection.
4. **Reconnaissance** – radar, ELINT / SIGINT, maritime patrol aircraft, drones, satellites, submarines; detection and the fog of war at sea; ties to TASK-122 / the future recon task.
5. **Air strikes** – maritime strike aircraft vs ships and ports; air defence of ships and of Kaliningrad's coast (S-400 umbrella); ties to TASK-097.
6. **Anti-ship missiles** – coastal batteries (Bastion-P, Bal, NSM Coastal Missile Unit, Swedish / Finnish RBS-15 and Gabriel), missile defence, saturation; shore targets (Baltiysk, Kaliningrad port) as targets of deep strikes.
7. **Seaborne supply** – supply and reinforcements by sea (Gdynia / Gdańsk, Klaipėda, Karlskrona, Kiel, the Danish Straits, Baltiysk as Russia's only Kaliningrad port with sea access for resupply) as an alternative to the Gap's land road; convoys, escorts, merchant losses; port capacity in supply points; ties to TASK-096 (supply) and TASK-105 (replacements), and to the blockade topic (2).
8. **Amphibious landings** – landing ships and naval infantry (Russian Baltic Fleet naval infantry, Polish 7th Coastal Defence Flotilla / Navy marines, German Seebataillon, Swedish Amphibious Corps, Finnish Coastal Brigade): embarking, sea transit, a landing on a coast hex, the beachhead as a vulnerable state, escort and naval fire support; the Sambian / Vistula Spit coast, Gotland, Bornholm and the Danish islands as likely objectives **[open]**.
9. **Capturing ports** – a port is an operational object (capacity, state, owner): taking it from the sea or land, damage and demolition (blocked harbour, mined approaches), time to clear and make it usable for supply (topic 7); Baltiysk, Kaliningrad, Pionersky, Gdynia, Klaipėda, Visby, Rønne as candidates; capturing a Russian port is an act on Russian soil, so it needs a place on the escalation ladder (TASK-115).

## Open questions for /refine-task

- **Map**: `suwalki_theatre` has only a sea corner in the north-west; the Baltic needs a separate maritime map layer or an enlarged / second theatre map (sea hexes, ports, straits, islands: Gotland, Bornholm, Öland, Rügen) – scale, importer support (TASK-092a / TASK-126), operational vs separate naval layer.
- **Abstraction level**: formations (flotillas) on a sea hex grid with auto-resolved clashes, or a tactical naval battle mode like the land battle? (Recommended start: operational only, resolved by the same auto-resolve idea as TASK-120.)
- **Command**: does the player command all five NATO navies, or only some while the others are allies handled by the AI (TASK-118 pattern)?
- **Escalation**: which naval acts (mine laying in the open sea, blockade, sinking a ship, striking Baltiysk) sit on which rung of the ladder; is the Baltic Fleet at Baltiysk a sanctuary (Russian soil) like the rest of Kaliningrad?
- **Effects on land**: supply (TASK-096), reinforcement arrival (TASK-105), naval gunfire / missile support to land formations.
- **Ports and landings**: ports as map data (importer: harbour polygons / `harbour`, `landuse=port`) with a capacity value; how beachheads and port capture fit the operational hex grid and the formation model (092b / 092c).

## Acceptance criteria (testable)

_To be written by /refine-task._

## Player manual

Naval section in docs/MANUAL.md once the mechanics exist (by `game-designer`).

## Out of scope (first guess)

- Submarine warfare detail beyond detection / ambush, nuclear weapons.

## Implementation notes

_Filled in by the agent when done._
