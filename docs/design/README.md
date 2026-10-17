# Visual design reference – game screen

Source: "Ekran Gry" mock-up made in Claude Design (three.js + HTML HUD), extracted from the offline bundle. This is the **target look** of the battle screen. It is a reference, not code to run: port ideas and numbers to Godot, don't copy the web stack.

| File | Contents |
|---|---|
| `game_screen.scene.js` | three.js scene: terrain generation (fbm noise, river, cities, roads), terrain vertex colours, hex grid lines, scatter (trees, buildings, rocks), procedural unit models (`makeTank`, `makeInf`, `makeMLRS`), overlays (reach, hover ring, path dots), camera, lighting |
| `game_screen.template.html` | HUD layout and styles: top faction/turn bar, terrain panel, end-turn button, unit hover popup, turn banner, loading screen |
| `reference.png` | Screenshot of the mock-up (to be added by the human) |

UI text in the mock-up is Polish. Per CLAUDE.md, UI strings in code are English; the Polish version comes through Godot translations.

## Key values

**Palette (HUD)**: background `#11130f`, panels `rgba(17,19,15,.84)` with 1px border `rgba(235,232,223,.12)`, text `#ebe8df`, secondary text `#a8a598` / `#d8d5cb`, accent yellow `#e2c069`, HP colours `#b9d38a` (>60%), `#e2c069` (>35%), `#e07c5e`.
**Factions**: player 0 `#5b93d6` (uniform `0x4f5934`), player 1 `#d76a52` (uniform `0x7a7354`).
**Fonts**: IBM Plex Sans Condensed (400–700) for text, IBM Plex Mono (400–600) for numbers/labels – in `assets/fonts/ibm_plex/` (OFL).
**Scene**: sky/fog `#a9b4b2`, fog 38–90, ACES tone mapping, exposure 1.05, hemisphere light `#dde7ee`/`#4b4534` 1.0, sun `#fff0d8` 2.7 from (-18, 26, 14) with soft shadows; camera FOV 34°, distance 7–46, pitch grows with distance.
**Terrain colours**: deep water `#17323b`, shoal `#5d8778`, sand `#c6b78a`, grass `#627c33`/`#87974b`, forest `#2f4a26`/`#3f5a2d`, hills `#837b50`, rock `#756e5e`/`#a29c8f`, snow `#eef0ef`, urban `#86837b`; water plane `#2c5866`, opacity 0.84; grid lines `#0d120c` at opacity 0.2.
