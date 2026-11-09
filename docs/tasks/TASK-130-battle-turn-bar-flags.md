# TASK-130: Side and faction flags in the tactical battle turn bar

- **Status**: ready
- **Layers**: data (`FactionDefinition.flag`, Poland flag asset) + presentation
- **Depends on**: – (TASK-127 is done: `SideFlag`, `SideDefinition.flag`, `assets/flags/`)
- **Sections**: none (UI only; look = HUD v3, `docs/design/hud_v3`)
- **Model**: sonnet

## Goal

The top turn bar of the tactical battle (`BattleHud`) shows, for each player, two flags: the **side** flag (NATO / Russia, as on the staff map) and the **faction** flag (Poland / Russia), so the player sees both who they fight for and which army fights. When the side and the faction are the same country (Russia), only **one** flag is shown, never two identical ones. Today it shows only the hexagonal "PL" / "RU" `HexBadge`.

## Acceptance criteria (testable)

- [ ] `FactionDefinition` gets a `flag` texture (data, like `SideDefinition.flag`); `poland.tres` and `russia.tres` set it; Polish flag added to `assets/flags/` (SVG, listed in `assets/flags/README.md`, rasterised like TASK-127).
- [ ] The turn bar shows both flags per player next to the name; the side is found from the faction (the `SideDefinition` whose `factions` contains it); a faction without a side shows only its own flag, no crash; if the side flag and the faction flag are the same (Russia: side `russia`, faction `russia`) one flag is drawn – compare the two flag textures / resource paths, not the ids, so it also holds for a future pair that shares an asset.
- [ ] `SideFlag` (or a shared flag component) is reused for both; sizes and spacing follow docs/design/hud_v3 (state any deviation); the `HexBadge` is kept or replaced – decide against the mockup and say which.
- [ ] Text in the bar does not overlap or clip with the extra flags (e.g. "POLAND · ACTIVE · 4 UNITS", "RUSSIA · WAITING").
- [ ] Unit test for the faction → side lookup, the missing-side case and the dedup rule (Russia → one flag, Poland → two: NATO + Poland).
- [ ] 60 FPS budget unchanged; `tools/readme_screenshot.sh` re-run, `gameplay.png` checked and committed.

## Playtest (for the human)

1. Start a tactical battle (Start scenario).
2. Expect: Poland has two flags (NATO + Poland), Russia has exactly one; names stay readable; active player highlight still works.

## Player manual

none (cosmetic)

## Out of scope

- Per-country flags elsewhere (staff map, result notice stay per side).
- Other factions beyond Poland and Russia.

## Implementation notes

_Filled in by the agent when done._
