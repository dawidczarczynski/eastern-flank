# TASK-124: Main menu reorganisation – scenario screen, settings screen

- **Status**: ready
- **Layers**: presentation (`src/presentation/ui/main_menu.gd`, two new screens), tests
- **Depends on**: – (builds on TASK-084 main menu and TASK-123 sound settings)
- **Sections**: MANUAL "12. Main menu and unit catalog"
- **Model**: sonnet

## Goal

The main menu becomes a short list that opens separate screens: the scenario is picked on its own screen with a map preview, and language and sound live in a settings screen. Every screen has a way back.

## Acceptance criteria (testable)

- [ ] Main menu has three buttons: **Start scenario**, **Unit catalog**, **Settings** (the scenario cycling button, language and sound controls are gone from it).
- [ ] **Start scenario** opens the scenario screen: a list of scenarios on the left (names from `BattleOptions.LABELS`, one selected), a map preview of the selected scenario on the right, a **Start** button and a **Back** button (returns to the main menu). Selecting another scenario updates the preview; the choice goes through `BattleOptions.menu_choice` as today, and the `--scenario` command-line argument preselects its entry.
- [ ] The preview is a flat top-down render of the scenario's terrain (terrain colours, water, roads, unit start markers optional) built from the scenario's map data without building a full `MapView`; shown within one frame of selection (no visible stall; budget: ≤ 100 ms per scenario on the dev machine, cached per scenario).
- [ ] **Unit catalog** opens the catalog as now; its Back button returns to the main menu (check it does, and that Esc does the same).
- [ ] **Settings** screen: language switch (English / Polski, applies at once, saved), Sound on/off, Master and Ambient volume sliders (apply at once, saved) – the existing behaviour of those controls, moved. **Back** returns to the main menu.
- [ ] All new texts in the localization files (EN and PL); the language switch re-translates the settings screen immediately.
- [ ] Menu tests (`tests/unit/test_main_menu.gd`) are updated for the new structure: each screen reachable from the main menu and back, scenario selection changes `menu_choice`, settings controls still persist through `GameSettings`.
- [ ] `tools/check.sh` passes.

## Playtest (for the human)

1. Start the game: the main menu shows Start scenario, Unit catalog, Settings.
2. Start scenario: click through the scenarios – the preview changes with each; Back returns to the menu; Start launches the chosen battle.
3. Unit catalog: open it, Back returns to the main menu.
4. Settings: switch the language (the screen changes at once), toggle sound, move both sliders; Back, restart the game – the settings are kept.

## Player manual

Rewrite the list in docs/MANUAL.md section 12 (and the sound section 12a where it names the menu) for the new three-button menu and the scenario / settings screens.

## Out of scope

- Returning from a battle to the menu (still restart the game).
- New scenarios, campaign / operation start (TASK-093+ add their entries later).
- Reworking the look of the menu beyond the existing `MenuStyle`.

## Implementation notes

_Filled in by the agent when done._
