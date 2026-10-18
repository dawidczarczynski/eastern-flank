# TASK-029: Unit materials – procedural camouflage shader and PBR material palette

- **Status**: done
- **Layers**: presentation (`assets/shaders/`, `src/presentation/unit_models.gd`; material set-up tested in `tests/unit/`)
- **Depends on**: TASK-019 (unit models), soft: TASK-026 (reflections make metal and glass read correctly). Reference: `docs/design/v2/README.md` ("Camouflage", "PBR materials"), `docs/design/v2/game_screen.scene.js` lines 188–205 (`GLSL_NOISE`, `camo`), 162 (`mat`), 208, 294, 301 (material lists per unit).
- **Model**: sonnet

## Goal

Vehicles and uniforms get a real three-tone camouflage with grain and mud near the ground, and metal, glass and rubber parts look like those materials. It improves the existing models right away and is the material base for the new models (TASK-031 … TASK-033).

## Design → Godot

- **`assets/shaders/camo.gdshader`** (spatial): `varying vec3 obj_pos;` set in `vertex()` from `VERTEX` (model space – with baked meshes in TASK-030 this is the model root space, so the pattern is continuous across parts). Port `GLSL_NOISE` (`h3`, `n3`, `fb`). Uniforms: `color_a/b/c` (source_color), `pattern_scale` (S), `dirt_height`, `base_roughness`, `metallic`, `dirt_color = #5b4a35`. Fragment:
  - `q = obj_pos·S; ca = fb(q); cb = fb(q·1.27 + vec3(17, 3, 9))`
  - `col = mix(color_a, color_b, smoothstep(0.52, 0.55, ca)); col = mix(col, color_c, smoothstep(0.6, 0.63, cb))`
  - `gr = n3(obj_pos·S·18); col *= 0.88 + 0.24·gr`
  - `dirt = smoothstep(dirt_height, 0, obj_pos.y)·(0.45 + 0.55·n3(obj_pos·S·5)); col = mix(col, dirt_color, dirt·0.85)`
  - `ALBEDO = col; ROUGHNESS = clamp(base_roughness + (gr − 0.5)·0.25 + dirt·0.1, 0, 1); METALLIC = metallic`.
  - `pattern_mode` uniform: `0` = blotches (as above), `1` = **digital** – quantise `q` to a grid (`floor(q·cells)/cells`, cells ≈ 6 per pattern unit) before the noise, so the pattern becomes pixel squares. Needed for Russia's EMR ("Tsifra") uniforms; Poland's wz. 93 Pantera uses blotches.
  - Note: the model root is scaled by `MODEL_SCALE`; object space is unaffected, so the design's S values apply directly.
- **Camo instances** (one shared `ShaderMaterial` per owner and preset, cached like the existing materials): vehicle hull/turret S 9, dirt 0.12 (MLRS 0.11), roughness 0.8, metallic 0.12; uniforms S 70, dirt 0.03, roughness 0.95. Faction colours: player 0 `#4c5632`, `#3b3325`, `#22251d`; player 1 `#8a7f5a`, `#6b6446`, `#a89c76`. Keep them in one owner-indexed constant: TASK-038 moves them into `data/factions/*.tres` (`camo`), and from then on the materials are cached per faction id. If TASK-038 is already done, read them from the faction right away.
- **PBR palette** as named constants in `UnitModels` (colour, roughness, metallic): `DARK #24251f 0.85/0.15`, `STEEL #55564f 0.42/0.75`, `RUBBER #171715 0.95/0`, `GLASS #0b1820 0.06/0.9`, `LAMP #e8e2c4 0.2/0.2`, `TRACK #2f2d28 0.7/0.55`, `TAIL_LIGHT #7a1c14 0.4/0.1`, faction accent `0.55/0.1`, `SKIN #a87c5f 0.75/0`, `BOOT #1d1b17 0.8/0.05`, `GUN #1b1c19 0.45/0.55`, `AT_TUBE #434a30 0.7/0.2`. The old `TANK_DARK`, `TANK_METAL`, `SOLDIER_DARK`, `SKIN` constants are replaced.
- **Apply to the current models** (no geometry changes): tank and MLRS bodies → vehicle camo; uniforms → uniform camo; vests stay plain faction vest colours; wheels → steel hubs / rubber; gun barrels → steel; existing glass-like parts (if any) → glass.
- The hit flash (TASK-019 `test_hit_reset_leaves_no_flash_behind`) must keep working with `ShaderMaterial`s – check how the flash is applied (material override vs. albedo change) and adapt it (e.g. a `flash` uniform or `material_overlay`). Document the choice.

## Acceptance criteria (testable)

- [ ] `test_unit_models.gd`: the tank's hull mesh instance uses a `ShaderMaterial` whose shader is `res://assets/shaders/camo.gdshader`, with `color_a` = `#4c5632` for owner 0 and `#8a7f5a` for owner 1 and `pattern_scale` = 9; an infantry soldier's torso uses camo with `pattern_scale` = 70; camo materials are shared between two instances with the same owner (same object).
- [ ] Some barrel/wheel part uses a `StandardMaterial3D` with metallic ≥ 0.7 and roughness ≤ 0.45 (steel).
- [ ] `test_hit_reset_leaves_no_flash_behind` (or its updated version) passes: after a hit animation finishes, no override/overlay remains and uniforms are back to their defaults.
- [ ] With `pattern_mode = 1` the shader compiles too (test sets the uniform); the agent renders one unit with each mode for the visual check.
- [ ] The shader compiles headless (the test instantiates the material and reads a uniform; Godot logs no shader errors – check the test output).
- [ ] Agent visual check: screenshot – vehicles show a blotchy three-tone pattern, mud-coloured lower edges, the two factions are clearly different (green vs. sand). Compare with `docs/design/v2/shots/01-v2-units.jpg` portrait.

## Playtest (for the human)

1. Zoom in on your tank: three-colour blotches, finer grain, and brownish mud along the bottom of the hull.
2. Compare with an enemy tank: sand-coloured pattern.
3. Rotate the camera around a tank: the barrel and wheel hubs show sharp metallic highlights; the hull stays matte.
4. Attack a unit: the hit flash still shows and disappears afterwards.

## Out of scope

- New geometry (TASK-030 … TASK-033), decals/markings, damage wear.

## Implementation notes

- `assets/shaders/camo.gdshader`: port of `GLSL_NOISE`/`camo()`, uniforms as in the spec plus `digital_cells` (6) and `pattern_mode` (0 blotches, 1 digital). `pattern_mode` is not per faction in the data yet (it is a plain uniform, set to 0 in `UnitModels._camo_material`); Russian EMR can be switched on by one data field later.
- `UnitModels`: PBR palette constants (`[colour, roughness, metallic]` arrays) replace SKIN/SOLDIER_DARK/TANK_DARK/TANK_METAL. Camo `ShaderMaterial`s are built from `FactionDefinition.camo` and cached per faction id in `_faction_materials` (roles `body`, `truck_body` for the MLRS dirt 0.11, `uniform`). Null faction / fewer than 3 camo colours = neutral grey tones. Vests stay `StandardMaterial3D`. Tank: wheels rubber with steel hubs, barrel steel, tracks `TRACK`. MLRS: wheels rubber, windscreen glass, cradle/rails steel. Rifles use `GUN`. LAMP, TAIL_LIGHT, BOOT and AT_TUBE from the spec are not added yet (no matching geometry – dead code); add them with the parts in TASK-031 … TASK-033. The MLRS pod's large top/bottom plates use DARK, not STEEL: a big flat metal panel only mirrored the dark ground and read black (review finding).
- Parts are separate primitives, so model-space `VERTEX` would restart the pattern and the mud line per box. A per-instance uniform `part_origin` (sum of the ancestors' local positions at build time, rotation ignored) is added in the shader, which keeps the mud height and pattern roughly continuous. TASK-030 (baked meshes) can drop it.
- Hit flash: unchanged. It is a shared unshaded `material_overlay`, applied on top of any surface material, so `ShaderMaterial` surfaces flash like before and `material_override` is never touched. `test_hit_reset_leaves_no_flash_behind` still passes; `test_hit_reset_works_on_camo_surfaces` checks it on real camo surfaces.
- Headless tests use the dummy renderer, so they cannot prove the shader compiles on a GPU; that was checked with `tools/screenshot.sh` (OpenGL fallback) – no shader errors logged, camo visible.
- Camo presets and the palette are code constants (presentation-only, as the spec asks); faction colours come from `data/factions/*.tres`.
- Review: removed unused palette constants, pod plates → DARK, renamed the headless shader test to `test_camo_shader_exposes_both_pattern_modes` (the dummy renderer compiles nothing), documented the pivot-ordering requirement of `_model_offset`.
- Playtest focus: mud along the lower hull at close zoom, steel highlights on barrel/hubs, MLRS pod brightness (Poland), hit flash on camo units.
