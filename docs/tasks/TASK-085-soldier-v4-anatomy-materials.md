# TASK-085: Soldier v4 (A + C) – anatomical body, real proportions, baked AO and fabric materials

- **Status**: done
- **Layers**: presentation (`models/parts/soldier.gd`, `models/pl_mech_infantry.gd`, `models/ru_motor_rifle.gd`, `ModelParts`, `MeshKit` if a primitive is missing, `assets/shaders/camo.gdshader` if needed), tests (`test_unit_model_contract.gd`, `test_unit_models.gd`, new soldier tests). Roles: **unit-modeler** (body, kits, render-compare), **presentation-engineer** (AO bake helper, materials) if needed.
- **Depends on**: – (soft: TASK-067 – builds on its code; its playtest folds into this one)
- **Model**: opus (organic shapes, anatomy, AO bake within the build-time budget)
- **Topic**: Visual realism

## Goal

The infantry stops looking like Playmobil toys: real human proportions and anatomy, natural static poses with weapons properly shouldered, and fabric / gear materials with ambient occlusion – both in the in-game unit catalog close-up and at the closest battle zoom (~50–100 px per soldier). Stage A + C of the "Soldier v4" plan (2026-10-24); B (skeleton, skinning, IK at runtime) and D (variants, walk cycle) are later tasks.

## Diagnosis (render of TASK-067, 2026-10-24)

- Limbs and torso are tubes of elliptic rings: no pelvis / glutes, thighs don't taper, the torso is an oval barrel.
- Head + helmet too big: helmet ~34 cm wide (real wz. 2005 / PASGT shell ~29 × 32 cm, oval), sits high on a long neck – the figure reads ~5.5 heads tall instead of ~7.5.
- Boots are blocks (pillow + flat sole slab); arms are thin noodles with elbows splayed out (the elbow is a pushed midpoint, so arm segment lengths change per pose); rifles float in front of the body – the butt is not in the shoulder pocket, no cheek weld.
- Materials read as plastic: vest, pouches and pack are one flat olive `StandardMaterial3D`; camo blotches too large and too contrasty; flat salmon skin; no occlusion under the helmet brim, in the armpits, between the legs or under pouches.
- Stiff symmetric stances: no weight shift, heads straight ahead.

## Design

### A – Anatomy and proportions (`parts/soldier.gd`)

- **Body from anatomical cross-sections**, not ellipses: torso, legs and arms as rings with real profiles (16–24 points per ring; chest flatter in front, shoulder blades and trapezius at the back, waist, pelvis with glutes, tapering thigh, calf belly, ankle; upper arm with biceps / triceps, forearm tapering to the wrist). A new `MeshKit` primitive (e.g. `sweep` with per-ring `Vector2` profiles instead of radii) is added to the kit with a test, not to the model files. Profiles are tables of constants in `soldier.gd` (presentation geometry, not balance data).
- **Proportions from ANSUR II** (US Army anthropometric survey, male means; approximate, scale to a 1.78 m body + helmet ≈ 1.82 m): stature 1756 mm, acromion (shoulder) height ~1440, crotch height ~840, knee (mid-patella) height ~500, bideltoid (shoulder) breadth ~510, biacromial breadth ~415, hip breadth ~360, chest circumference ~1060, waist circumference ~940, thigh circumference ~620, calf ~390, ankle ~230, neck ~400, head length ~197 / breadth ~156 / circumference ~572, upper arm (acromion–elbow) ~365, forearm (elbow–wrist) ~270, hand length ~193, foot length ~270 / breadth ~102. Body + helmet reads ≥ 7 head heights.
- **Two-bone IK for the static poses** (pure geometry at build time): arms from shoulder to the weapon grips and legs from hip to foot with fixed segment lengths (upper arm / forearm, thigh / shin) and a pole direction, so elbows point down and back, knees forward; no more stretching or shrinking limbs. The hands are the `dress` hook's grip points as today.
- **Weapon handling**: rifle butt in the shoulder pocket (between the deltoid and the chest, not floating in front), the head tilted forward to a cheek weld when aiming, support elbow under the handguard; the RPG on the shoulder, the MG at the hip with the sling taking the weight.
- **Natural stances**: contrapposto (weight on one leg, pelvis and shoulders tilted opposite), feet turned out, the head turned slightly per soldier (from the layout yaw / `TerrainNoise.hash`), small torso twist toward the weapon.
- **Head**: shorter neck; skull, jaw, brow ridge and cheekbones so the face reads under the brim at catalog zoom (no eyes / mouth detail – they read via AO); ears.
- **Hands**: mitten with a separate thumb wrapped around the grip (glove material), not a pillow.
- **Boots**: built from a last profile – narrower toe, heel, rounded toe cap, the sole following the outline (thin chamfered plate), blousing of the trousers over the boot top.
- **Clothing as a shell** over the body (trouser and sleeve shapes slightly looser than the body), with folds: bunching at the elbows, behind the knees, at the crotch, above the belt; trousers bloused into the boots. Folds may be geometry (a few ring offsets) or a normal-perturbation in the shader – whichever fits the budget.
- **Kit sizes**: helmets oval with real outer dimensions (wz. 2005 ~29 × 32 cm, 6B47 analogous; `lathe` `oval`), sitting low (rim at the brow / over the ears), not perched on top. Plate carriers, pouches and packs conform to the new torso (front plate follows the chest, cummerbund follows the waist), pouch sizes from real kit (magazine pouch ~8 × 13 × 4.5 cm). Both squads (`pl_mech_infantry`, `ru_motor_rifle`) are updated – the soldier is shared.

### C – Materials and light

- **Baked ambient occlusion** into the vertex mask `COLOR.g` (openness, ADR 0012 – `camo.gdshader` already darkens by it) at build time, cached with the variant mesh. Cheap analytic occlusion from proxy capsules / spheres of the known body parts and kit (torso, limbs, head, helmet, pack, plates) is enough – no brute-force ray casting in GDScript. Visible results: dark under the helmet brim and on the face sides, armpits, between the legs, under pouches and the pack, inner thighs / crotch.
- **Every soldier material reads the masks**: vest / pouches / pack (single-colour weathered paint per faction, `vest_color`), skin and gun move to mask-reading materials (camo shader one-colour or a small dedicated shader) so the AO applies everywhere. Per-part tint (`COLOR.b`) stronger on the gear so pouches, pack and carrier aren't one flat colour.
- **Fabric look**: camo at real scale (wz. 93 Pantera / Russian patterns: dominant blotches ~5–15 cm in real metres before `SOLDIER_SCALE`), lower contrast and saturation than now; high roughness with a cloth rim / sheen term; a fine fabric / weave normal perturbation (procedural in the shader, no texture required). Gear (webbing, straps) slightly different roughness from the uniform.
- **Skin**: subsurface scattering where available (Forward+), darker under the brim via AO; the LOW quality level (Compatibility renderer) falls back to plain shading.
- **Performance**: 60 FPS on the target GPU (CLAUDE.md budget) – any new per-pixel term must be cheap or behind a quality level (`GraphicsQuality`).

### Contract and budget (unchanged)

- `Soldier0…4`, `Rig`, kneelers `Kneel` + hidden `Stand`, carries `READY` / `AIM` / `LOW` (TASK-068), `SOLDIER_SCALE`, `LABEL_HEIGHT`, `UnitModels.pose_infantry`, marching.
- Squad ≤ **40 000 triangles** including the hidden `Stand` variants (ADR 0010), cold build ≤ **500 ms** (target ≤ 250 ms including the AO bake).

## Acceptance criteria (testable)

- [x] Both squads pass `test_unit_model_contract.gd` for every faction (≤ 40 000 triangles, cold build ≤ 500 ms); triangle counts and build times recorded in the notes.
- [x] Proportions test: for a standing soldier, the head + helmet height (chin to helmet top) is ≤ 1/7 of the figure height; the helmet's outer width is 0.27–0.31 m and its length 0.30–0.34 m (real metres, before `SOLDIER_SCALE`).
- [x] IK test: for every carry and posture, the built upper arm and forearm lengths (shoulder–elbow, elbow–wrist) and thigh / shin lengths equal the anatomical constants within 1 cm; the elbow is below the shoulder–hand line.
- [x] AO test: every soldier mesh carries vertex masks; the body + helmet mesh (uniform) has some vertices with `COLOR.g` ≤ 0.6 (occluded) and a majority ≥ 0.9; the skin (face and neck, mostly under the helmet – dark by design) and the vest (under the pouches and the pack) have occluded vertices (≤ 0.6); the vertices under the helmet brim are darker than the top of the helmet.
- [x] Every soldier material reads the vertex masks (no plain `StandardMaterial3D` left on the soldier body / kit roles); existing material tests updated accordingly.
- [x] Locomotion, kneel / stand and carry tests pass unchanged.
- [x] `tools/render_unit.sh pl_mech_infantry` and `ru_motor_rifle` sheets (side, front, three-quarter), an in-game catalog-like close-up and a battle crop (`SCREENSHOT_CAMERA=1,-40,5`) listed in the notes; `docs/images/gameplay.png` re-rendered.

## Playtest (for the human)

1. Main menu → Unit catalog → Polish and Russian infantry: orbit close. Bodies with hips, tapering legs, real shoulders; helmets sit low and are not oversized; boots look like boots; rifles are in the shoulder with the head on the stock; elbows hang down; the pouches and the pack are distinguishable from the plate carrier; shadowed face under the brim, dark armpits and crotch.
2. Battle, closest zoom: squads read as soldiers, not toys; the camo is fine-grained, not big blotches.
3. Move a squad: marching, kneelers standing up and kneeling again work as before.
4. HIGH quality, focused window: still 60 FPS with several squads on screen.

## Player manual

None (visual only).

## Out of scope

- Runtime skeleton, skinning, IK and new animations (stage B), body / kit variants per soldier and walk cycle (stage D).
- Faces with eyes / mouth, fingers, cloth simulation, third-party body meshes (would need a new ADR over ADR 0011).

## Implementation notes

**What was built** (both squads share it; the kits were rewritten around the new body):

- `parts/soldier_pose.gd` (`class_name SoldierPose`): the static pose solved at build time. ANSUR II
  proportions for a 1.75 m body in 3 cm boots (hip joints 0.94 ± 0.088, knee 0.52, ankle 0.11,
  shoulder joints (−0.005, 1.435, ±0.172), chin 1.562, scalp 1.776); fixed segments thigh 0.42,
  shin 0.41, upper arm 0.30, forearm 0.26 (+ 0.075 wrist to grip). `two_bone` IK (exact lengths,
  pole direction) for legs and arms. Stances per kit (`STANCES` in each model: shouldered rifle,
  RPG on the shoulder, GPMG at the hip): bladed stance with the hips turned right and the chest
  twisted back towards the weapon, feet turned out, the pelvis lowered until both legs reach with
  soft knees; relaxed (non-aiming) soldiers get a per-slot weight shift / pelvis and shoulder roll
  (contrapposto) and head turn (`TerrainNoise.hash`). Kneeling: right knee on the ground, right
  foot pitched until its toe touches. Aiming: the butt sits in the shoulder pocket
  (`SoldierPose.shouldered`) and the head's pitch / roll are solved so the right eye lies on the
  sight line (cheek weld, capped at 0.45 / 0.3 rad); the RPG eye goes to the launcher's sight.
- `parts/soldier_body.gd`: the body from constant tables of anatomical cross-sections (superellipse
  half sizes per side + Gaussian bumps: pectorals, shoulder blades, glutes, spine groove, patella,
  nose, cheekbones, brow ridge, eye sockets; fold ripples at the knee, elbow, cuff and the boot
  blousing). Torso 13 rings × 20, legs 11 × 12, arms 9 × 12, head 13 × 20 (points crowded to the
  face), boots from a last profile + chamfered sole plate following the outline, glove mittens with
  fingers curled around the grip and a separate thumb, ears, short hair shell, cargo pockets, knee
  pads, sleeve patches. Torso-surface helpers for the kits: `on_torso` (frames for pouches / packs),
  `torso_shell` (carriers, cummerbund, belt; lower at the armholes), `shoulder_pads`.
- `parts/occlusion_bake.gd`: analytic AO from proxy capsules / spheres (cosine-weighted r²/d²
  towards the normal, fixed value inside a proxy) and caps (helmet rims), capsules culled with an
  8 cm grid; multiplied into COLOR.g of the uniform, skin and vest meshes (committed indexed so
  each shared vertex is baked once). Proxies: pelvis / belly / chest, thighs, shins, boots, arms,
  neck, skull, brow ridge, nose, mouth line, pack, pouch row; a cap under every helmet rim (its plane
  3 cm up inside the shell so the brow under a tilted front rim is shaded).
- `MeshKit`: new `sweep_profile` (per-ring Vector2 profiles, parallel-transported frames) and
  `loft_rings` (smooth loft of arbitrary rings, optional caps, `outward = false` for the inside of an
  open shell), tested in `test_mesh_kit.gd`. Faster shared paths (all models): `_tri` caches
  `_map * xf` per primitive and sets the colour once per triangle; `_grid` maps each vertex once.
  `MeshKits.commit_all(indexed)` commits chosen roles indexed.
- Kits: helmets are smooth turned shells (`Soldier.oval_rings` + `loft_rings`) at real outer size
  (wz. 2005 0.32 × 0.29 m, 6B47 ~0.31 × 0.285 m), the lip and inside as a cavity, sitting low (rim
  at the brow, over the ears); carriers / armour are shells around the torso with pouches of real
  size on the front plate; packs on the back plate; the RPG rests on the shoulder with its grips
  ahead of it. The `dress` hook is now `dress(k: MeshKits, pose: SoldierPose)` (public static in
  both models) and returns the grips plus the fingers' curl directions.
- Materials (every soldier role reads the masks): uniform = faction camo with `CAMO_UNIFORM`
  (pattern scale 80 → 150, `pattern_contrast` 0.72, `fade` 0.22, new `fabric` term: crease / weave
  bump by surface-gradient bump mapping that fades below ~1 px, plus a rim sheen; `mask_ao`: COLOR.g
  also as the shader's `AO` / `AO_LIGHT_AFFECT`); vest, gun, gear and accent = `weathered_paint`
  (vest in the faction `vest_color` with per-part tint 0.55; gun with edge wear); skin = new
  `assets/shaders/skin.gdshader` (AO, redder occlusion, per-soldier tone from `part_origin`,
  `SSS_STRENGTH` on Forward+; checked that it compiles and renders with the Compatibility renderer).
  Vehicles are unaffected (`pattern_contrast` 1, `fabric` 0, `mask_ao` 0 by default).

**Numbers** (`test_unit_model_contract.gd`, any faction): `pl_mech_infantry` 38 844 triangles,
`ru_motor_rifle` 38 304 (7 figures incl. the 2 hidden `Stand`s; before: 28 804 / 27 672), 42 mesh
instances each; cold build 242 / 240 ms (before 109 / 105 ms; the first prototype of v4 took
~620 ms before the MeshKit / bake optimisations). Head + helmet ≈ 0.24 m of a ~1.78 m figure
(~7.3 heads). Battle frame time with the squads in view (`SCREENSHOT_MEASURE_FRAMES=240`,
`SCREENSHOT_CAMERA=1,-40,5`, Windows GPU build): avg 16.60 ms, max 16.73 ms – at the 60 FPS cap
(FramePacing re-caps the probe). Uncapped (scratch script: battle processing off, vsync off,
`Engine.max_fps = 0`, same camera, HIGH, Radeon RX 580, 300 frames): 14.15 ms (~71 FPS) vs 13.6 ms
for HEAD before TASK-085 in the same setup – +0.55 ms, ~2.5 ms headroom to 16.7 ms; switching the
fabric term off changed nothing measurable (14.17 ms).

**Tests**: new `tests/unit/test_soldier_anatomy.gd` (limb lengths within 1 cm and elbows below the
shoulder–hand line for every slot and posture of both squads, the built sleeve / trouser / glove /
boot meshes within 8 cm of the solved elbows, knees, wrists and ankles, head + helmet ≤ 1/7 of the
figure, helmet outer width / length, AO masks of uniform / skin / vest, brim darker than the crown,
every soldier material a ShaderMaterial reading COLOR.g – camo materials with `mask_ao` > 0, the
skin shader using COLOR.g as AO), `tests/unit/test_occlusion_bake.gd`, new MeshKit tests; updated
`test_unit_models.gd` (the vest is now weathered paint in `vest_color`; the TASK-067 smoothness
test reads indexed meshes). `tools/check.sh` passes (997 tests).

**Renders**: `.screenshots/units/pl_mech_infantry_poland_sheet.png`,
`.screenshots/units/ru_motor_rifle_russia_sheet.png`; in-game catalog close-ups
`.screenshots/task085_catalog_pl.png`, `.screenshots/task085_catalog_ru.png`; battle crop
`.screenshots/task085_crop.png` (4× zoomed: `.screenshots/task085_crop_zoom.png`); single-soldier
close-ups `.screenshots/closeup/v5_pl0.png` (cheek weld), `v6_ru1.png` (RPG), `v8_head2.png` (face
under the brim); `docs/images/gameplay.png` re-rendered.

**Decisions / deviations**:

- The AO criterion was reworded to what is tested: the "most vertices ≥ 0.9" part applies to the
  body + helmet mesh (uniform); skin (mostly face and neck under the helmet, shaded by design) and
  vest only need occluded vertices.
- Gear (boots, gloves, straps, hair), guns and patches keep their masks as built (no bake): dark
  already, and it keeps the cold build under 250 ms.
- AO also dims part of the direct light (`AO_LIGHT_AFFECT`): the helmet brim's real shadow on the
  face is finer than the shadow map resolves.
- Cache key: an aiming pose does not depend on the slot, so an aiming kneeler's hidden `Stand`
  shares the standing aimer's meshes (6 builds per squad instead of 7).
- Folds are ring offsets in the sections plus the shader's crease bump (no extra geometry).
- ADR 0012 got an "Amendment (TASK-085)" section: baked AO in COLOR.g (`OcclusionBake`), the
  opt-in `mask_ao` AO output, the skin shader as a second mask-reading family, indexed AO meshes,
  the new primitives.
- With `mask_ao` the camo shader darkens by the mask twice on purpose (albedo – creases stay dark in
  full sun – and the AO output for the ambient light); documented in the shader.
- `MeshKit._min_cross` scales the degenerate-triangle threshold by |det|^(4/3), exact for uniform
  scale; every caller maps with a uniform scale (Frame = mirror + uniform k, rigid pivots, soldiers
  0.1).
- Quality: `GraphicsQuality.features()["fabric"]` (HIGH on, LOW off) →
  `GraphicsQuality.apply_materials` → `ModelParts.set_fabric` switches the uniform camo's fabric
  bump / sheen off at LOW (existing and later materials; `mask_ao` stays); `apply_viewport` calls it,
  so the battle and the catalog apply it without changes (battle_controller.gd is at the 1000-line
  lint limit); tested in `test_graphics_quality.gd`.

**Known limitations**: no eyes / mouth (the face reads by its shape and the AO under the brim);
analytic proxies only (no sky visibility term – downward faces are darkened only by proxies and the
helmet's cavity flag); the Russian EMR pattern uses the shared blotch mode with the faction's
colours (its light third colour makes the uniform read pale; a digital pattern per faction would be
a data / shader task); bodies are rigid per variant (runtime skeleton, walk cycle and per-soldier
variants are stages B / D).
