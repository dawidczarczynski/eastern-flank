# TASK-173: Allied factions within a side (Russia and Belarus are not one party)

- **Status**: idea
- **Layers**: core (data) + presentation
- **Depends on**: TASK-160
- **Sections**: to be filled when specified (GDD "Sides", "Countries and stances", "Factions and units")
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

NATO may be treated as one side (a bloc), but Russia and Belarus are formally separate states: allied factions with shared goals, not one party. The game should show and name them that way instead of calling a Belarusian battalion "Russia".

## Notes for the later specification

Raised by the human after TASK-160 (2026-11-16, contact notice showed "ROSJA · OBROŃCA" for a Belarusian battalion). Proposal discussed, not decided:

1. Side = bloc (rules unit: player, goals, AI); faction = state (identity, allied, shared goals). `SideDefinition.factions` already models this; the gap is presentation and naming.
2. The Russian side gets a neutral bloc name ("Russia and Belarus") instead of "Russia"; NATO unchanged. Name still to be decided.
3. Contact notice role line shows the formation's faction ("BELARUS · DEFENDER"), not the side's; national flag already shown (TASK-160 follow-up fix).
4. Battle result window (title flag, tabs, outcome lines, aftermath) shows the faction flag and name when the side fielded one faction, the side flag when both factions fought.
5. Wider option, separate design question: Belarus (and Lithuania) as independent parties with their own relations, goals and possibly own player in the operation. Needs GDD work first (`game-designer`).

Check also other places that print the side name for a formation (turn bar, formation panel, side-select window). Then `/refine-task TASK-173`.

## Player manual

To be decided when specified.

## Out of scope

- To be decided when specified.

## Implementation notes
