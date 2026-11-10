# Visual design reference – game screen

Source: "Ekran Gry" mock-up made in Claude Design (three.js + HTML HUD), extracted from the offline bundle. This is the **target look** of the battle screen. It is a reference, not code to run: port ideas and numbers to Godot, don't copy the web stack.

| Folder / file | Status | Contents |
|---|---|---|
| `hud_v3/` | **current** (battle HUD) | HUD v3 tactical C2 look – spec, tokens, `hud-elementy.html`; supersedes the v1 HUD palette and fonts below |
| `operational_map/` | **current** (staff map) | Style spec and mock-ups of the operational map |
| `units/` | **current** (unit catalog) | Unit catalog: classes, mechanisms, per-unit data and reference images (`tools/unit_catalog.sh`) |
| `v2/` | reference | Second iteration of the battle-screen mock-up: detailed terrain, scatter and unit models (`game_screen.scene.js`, template, `shots/`) |
| `v1/` | legacy | First "Ekran Gry" mock-up: `game_screen.scene.js` (terrain generation, scatter, `makeTank`/`makeInf`/`makeMLRS`, overlays, camera, lighting) and `game_screen.template.html` (old HUD layout). Source of the palette and scene values below; the source code ports cite it |
| `showcase/` | reference | Model detail study (2026-10-21) |
| `proposals/` | proposals | HTML proposals from `/design-ui`, not accepted until the human picks a variant |

UI text in the mock-up is Polish. Per CLAUDE.md, UI strings in code are English; the Polish version comes through Godot translations.

## Key values

**Palette (HUD)**: background `#11130f`, panels `rgba(17,19,15,.84)` with 1px border `rgba(235,232,223,.12)`, text `#ebe8df`, secondary text `#a8a598` / `#d8d5cb`, accent yellow `#e2c069`, HP colours `#b9d38a` (>60%), `#e2c069` (>35%), `#e07c5e`.
**Factions**: player 0 `#5b93d6` (uniform `0x4f5934`), player 1 `#d76a52` (uniform `0x7a7354`).
**Fonts**: IBM Plex Sans Condensed (400–700) for text, IBM Plex Mono (400–600) for numbers/labels – in `assets/fonts/ibm_plex/` (OFL).
**HUD v3 (tactical C2 look)**: supersedes the HUD palette and fonts above; spec and reference render in [hud_v3/](hud_v3/README.md), decisions in ADR 0013 (Chakra Petch + JetBrains Mono in `assets/fonts/`, tokens in `UiPalette`, shapes in `HudShapes`).
**Scene**: sky/fog `#a9b4b2`, fog 38–90, ACES tone mapping, exposure 1.05, hemisphere light `#dde7ee`/`#4b4534` 1.0, sun `#fff0d8` 2.7 from (-18, 26, 14) with soft shadows; camera FOV 34°, distance 7–46, pitch grows with distance.
**Terrain colours**: deep water `#17323b`, shoal `#5d8778`, sand `#c6b78a`, grass `#627c33`/`#87974b`, forest `#2f4a26`/`#3f5a2d`, hills `#837b50`, rock `#756e5e`/`#a29c8f`, snow `#eef0ef`, urban `#86837b`; water plane `#2c5866`, opacity 0.84; grid lines `#0d120c` at opacity 0.2.

**Operational (staff) map**: style spec and mock-ups (Claude Design, 2026-11-07) in [operational_map/](operational_map/README.md).
