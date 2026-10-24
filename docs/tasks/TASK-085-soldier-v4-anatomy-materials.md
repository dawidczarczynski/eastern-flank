# TASK-085: Soldier v4 (A + C) – anatomical body, real proportions, baked AO and fabric materials

- **Status**: in progress
- **Layers**: presentation (`models/parts/soldier.gd`, `models/pl_mech_infantry.gd`, `models/ru_motor_rifle.gd`, `ModelParts`, `MeshKit` if a primitive is missing, `assets/shaders/camo.gdshader` if needed), tests (`test_unit_model_contract.gd`, `test_unit_models.gd`, new soldier tests). Roles: **unit-modeler** (body, kits, render-compare), **presentation-engineer** (AO bake helper, materials) if needed.
- **Depends on**: – (soft: TASK-067 – builds on its code; its playtest folds into this one)
- **Model**: opus (organic shapes, anatomy, AO bake within the build-time budget)

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

- [ ] Both squads pass `test_unit_model_contract.gd` for every faction (≤ 40 000 triangles, cold build ≤ 500 ms); triangle counts and build times recorded in the notes.
- [ ] Proportions test: for a standing soldier, the head + helmet height (chin to helmet top) is ≤ 1/7 of the figure height; the helmet's outer width is 0.27–0.31 m and its length 0.30–0.34 m (real metres, before `SOLDIER_SCALE`).
- [ ] IK test: for every carry and posture, the built upper arm and forearm lengths (shoulder–elbow, elbow–wrist) and thigh / shin lengths equal the anatomical constants within 1 cm; the elbow is below the shoulder–hand line.
- [ ] AO test: every soldier mesh carries vertex masks; on the body and helmet meshes some vertices have `COLOR.g` ≤ 0.6 (occluded) and most have ≥ 0.9; the vertices under the helmet brim are darker than the top of the helmet.
- [ ] Every soldier material reads the vertex masks (no plain `StandardMaterial3D` left on the soldier body / kit roles); existing material tests updated accordingly.
- [ ] Locomotion, kneel / stand and carry tests pass unchanged.
- [ ] `tools/render_unit.sh pl_mech_infantry` and `ru_motor_rifle` sheets (side, front, three-quarter), an in-game catalog-like close-up and a battle crop (`SCREENSHOT_CAMERA=1,-40,5`) listed in the notes; `docs/images/gameplay.png` re-rendered.

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

_Filled in by the agent when done: what was done, decisions, known limitations._
