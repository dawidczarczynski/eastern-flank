# Visual design reference v2 – detailed terrain and units

Source: second iteration of the "Ekran Gry" mock-up made in Claude Design (three.js + HTML HUD). It keeps the v1 layout and palette (`docs/design/README.md`) and raises the level of detail of the terrain, scatter and unit models. Like v1, it is a **reference, not code to run**: port ideas and numbers to Godot, don't copy the web stack.

Everything is procedural – there are no imported 3D models or image textures. The detail comes from techniques that all have Godot equivalents (TASK-026 … TASK-033).

| File | Contents |
|---|---|
| `game_screen.scene.js` | three.js scene (line numbers below refer to this file) |
| `game_screen.template.html` | HUD template (same layout as v1, plus the portrait area in the unit popup) |
| `shots/v2-map.jpg` | Overview of the map: terrain detail, forests, cities, river |
| `shots/01-v2-zoom.jpg`, `02-v2-zoom.jpg` | Close camera: tree crowns, terrain texture |
| `shots/01-v2-units.jpg`, `02-v2-units.jpg`, `hover*.jpg` | Unit popups with rendered portraits (tank, MLRS) |

## What is new compared with v1 (and where)

| Technique | Lines | Task |
|---|---|---|
| Sky-gradient environment map (IBL) for ambient light and reflections, hemisphere light lowered to 0.45 | 352–360, 444–454 | TASK-026 |
| Tileable detail heightmap → greyscale albedo + normal map repeated 44× over the terrain; terrain mesh 6 vertices / unit; macro dry/moist colour variation | 361–379, 457–497 | TASK-027 |
| Water with a tileable normal map, roughness 0.07 | 499–501 | TASK-027 |
| Tree crowns from several noisy lobes / jagged cones with baked AO in vertex colours and bent normals; bush layer | 380–403, 562–580 | TASK-028 |
| Procedural camouflage shader (object-space 3D noise, grain, dirt near the ground, roughness variation); PBR materials (steel, glass, rubber) | 188–205, 162 | TASK-029 |
| Geometry helpers: profile extrusion with bevel (`prof`, `plan`, `rbox`), lathe, taper, rods/capsules, gears; baking all parts into one mesh per material (`bake`) | 163–186 | TASK-030 |
| Detailed tank (first tank model, adjusted to a real vehicle) | 207–266 | TASK-031 |
| Detailed soldiers (capsule limbs, helmet, vest, pack, rifle, AT launcher) | 267–299 | TASK-032 |
| Detailed MLRS truck (6 wheels with lugs, cab, 12-tube pod) | 300–350 | TASK-033 |
| Unit portraits rendered from the 3D model for the popup | 414–431 | TASK-034 |
| (not in the design) Real units with a model each, faction camouflage, unit catalog tool, render-compare pipeline for the `unit-modeler` agent | – | TASK-036 … TASK-039, `docs/design/units/` |
| Rivers, roads, named cities with instanced buildings (window shader, gable roofs) | 41–130, 504–533, 581–594 | idea – needs a GDD decision (TASK-035) |

## Key values (v2 only – the rest as in v1)

**Lighting**: hemisphere `#dde7ee` / `#4b4534` intensity **0.45** (v1: 1.0); environment = gradient sphere: top `#7f9bb5`, horizon `#d5d8cc`, ground `#4f4a3a` (reaches ground colour at 20 % below the horizon), sun disk `#fff0d0` × 20 toward (-18, 26, 14); `envMapIntensity`: terrain 0.55, foliage 0.4, units 1.0.
**Terrain detail**: heightmap 256², value-noise octaves with periods 8/16/32/64 (amplitude × 0.55 per octave), seed 201; albedo `v = 0.76 + 0.34·H ± 0.03` (blue × 0.97); normal strength 7, `normalScale` 0.9; repeat 44 across the terrain width; anisotropic filtering.
**Macro variation**: `mac = fbm(x·0.12 + 5, z·0.12, seed 91, 3 octaves)`; lerp to dry `#9c9558` by `smooth(0.55, 0.75, mac)·0.45`, then to moist `#4c6a2c` by `smooth(0.42, 0.28, mac)·0.4`.
**Water**: colour `#264f5c`, roughness 0.07, metalness 0.1, opacity 0.84, normal map periods 4/8/16/32, seed 303, strength 5, repeat 36, `normalScale` 0.3.
**Camouflage** (per faction, three colours): player 0 `#4c5632`, `#3b3325`, `#22251d`; player 1 `#8a7f5a`, `#6b6446`, `#a89c76`; dirt `#5b4a35`.
**PBR materials** (colour, roughness, metalness): dark `#24251f` 0.85/0.15, steel `#55564f` 0.42/0.75, rubber `#171715` 0.95/0, glass `#0b1820` 0.06/0.9, lamp `#e8e2c4` 0.2/0.2, track `#2f2d28` 0.7/0.55, tail light `#7a1c14` 0.4/0.1, faction accent 0.55/0.1; soldiers: skin `#a87c5f` 0.75/0, boots `#1d1b17` 0.8/0.05, gun `#1b1c19` 0.45/0.55, AT tube `#434a30` 0.7/0.2.
