# TASK-144: Strike weapon 3D models (1/2): the model pipeline for missiles and the first model, JASSM-ER

- **Status**: done
- **Layers**: presentation (`src/presentation/models/weapons/`) + tests
- **Depends on**: TASK-141a (done)
- **Sections**: docs/design/operational_map/README.md "Strike panel" (model card), GDD "Deep strikes"; TASK-036 / TASK-043 (model pipeline and mechanisms contract)
- **Model**: opus
- **Agent**: unit-modeler

## Goal

The strike panel (TASK-141b, variant A) shows a **turntable 3D model** of the picked weapon in a 388×140 px `SubViewport` card. This task builds the small shared pipeline for weapon models and the first model – the AGM-158B JASSM-ER – as the pattern for the 11 others (TASK-145). Procedural meshes like the unit models (`src/presentation/models/`), no imported assets.

## Acceptance criteria (testable)

- [ ] `src/presentation/models/weapons/weapon_models.gd` (`WeaponModels`): `build(means_id: StringName) -> Node3D` returns the procedural model or `null` for a weapon without one (the panel then shows the class glyph); `has_model(id)`.
- [ ] `jassm_er` model: real proportions (length 4.27 m, span 2.4 m, diameter ≈ 0.55 m; box-like faceted fuselage with the flat chined nose, small swept wing, V-tail, dorsal intake), built from the existing `ModelParts` helpers, 1 unit = 1 m, origin at the centre of mass, nose along +X; ≤ 400 triangles; matte olive-grey material in the project's model palette.
- [ ] `WeaponTurntable` (a `Node3D`/`SubViewportContainer` helper): one camera, one directional light, slow spin (12 s per turn, 18° tilt), auto-fit of the model to the viewport; renders only while visible (`UPDATE_WHEN_VISIBLE`), no shadows. Test: a headless scene smoke test builds the turntable with `jassm_er` and a weapon without a model (null → no crash).
- [ ] A catalog entry `docs/design/units/units/jassm_er/` (real dimensions, silhouette features, reference notes) like the unit catalog entries; the dimension test of the model compares its bounding box with the catalog values (±5 %).
- [ ] `tools/render_unit.sh` (or a documented variant) can render the weapon for the compare loop; a render of the model is stored next to the catalog entry.

## Playtest (for the human)

Open the render (or the strike panel once TASK-141b lands): does the silhouette read as a JASSM-ER from the side and from above (flat nose, small swept wings, V-tail)? Does the turntable stay smooth at 60 FPS?

## Player manual

Not player-facing until TASK-141b shows it.

## Out of scope

The panel (TASK-141b); the other models (TASK-145); animation of flight / launch effects.

## Implementation notes

**Note 2026-11-11:** the 3D model is superseded as the card's picture by the blueprint drawings of TASK-146 (`WeaponBlueprint` replaces `WeaponTurntable` in the weapon card). The task stays done; the JASSM-ER model, catalog entry and dimensions remain a source for the blueprint.

- **Pipeline**: `src/presentation/models/weapons/weapon_models.gd` (`WeaponModels`: `MODELS` registry `{means_id: preload(model)}`, `has_model`, `build` → `ModelParts.cached("weapon:<id>")` copy or `null`, `MAX_TRIANGLES = 400`). Weapon model contract in its header: 1 unit = 1 m, origin at the centre of mass, nose +X, wings deployed, plain PBR materials (no faction, mechanisms, footprint or battle registration). TASK-145 adds one file + one `MODELS` line per weapon.
- **JASSM-ER** (`jassm_er.gd`): `MeshKit.stack` body of 5 stations of a 6-point trapezoid section (flat belly, chines, narrow flat top; 0.55 × 0.45 m), wedge nose with the tip low, boat tail; wings and fin as `MeshKit.plate`; ventral intake scoop; dark exhaust and seeker window. 112 triangles, 3 mesh instances (body olive grey #5d6157 r 0.78, `ModelParts.DARK`, `ModelParts.GLASS`). AABB 4.27 × 2.40 × 0.76 m vs. catalog 4.27 × 2.4 × 0.75 (+0.1 % / 0 % / +1.9 %).
- **Shape deviation from this task's wording**: the sources (Wikipedia, Air & Space Forces, photographs) show a **single vertical fin** and an intake **under** the body, not a V-tail / dorsal intake, so the model follows the sources (see the blueprint). Span: 2.4 m per this task; Wikipedia/CSIS give 2.7 m for the JASSM-ER – to be confirmed by the human.
- **Catalog**: `docs/design/units/weapons/jassm_er/` (`unit.json` shaped like a unit entry, `blueprint.md`, `render.png`). Not under `docs/design/units/units/`: the catalog schema (`tools/unit_catalog/catalog.py`, `test_every_shipped_unit_validates`) only accepts classes from `classes.json` and mobility tracked/wheeled/foot. No reference image stored yet.
- **WeaponTurntable** (`weapon_turntable.gd`, `SubViewportContainer`, 388 × 140 default): own world, one camera (18° tilt, FOV 30°), one directional light without shadows, `UPDATE_WHEN_VISIBLE`, MSAA 4×, transparent background; `show_weapon(id) -> bool` (false = no model, show the glyph), spin 12 s/turn only while visible (`spin(delta)`), auto-fit by the spin circle and height. Checked in a throwaway GPU render at 388 × 140-ish: the model fills the card at every yaw.
- **Render workflow**: `tools/render_unit.sh --weapon <id>` runs `tools/render_weapon.gd` (extends `render_unit.gd`; `_build_model` extracted there as the override point), model scaled to the 1 m grid and set on the ground, `Real` line from the weapons catalog; documented in docs/TOOLS.md.
- **Tests**: `tests/unit/test_weapon_models.gd` – registry / null, every registered weapon is a strike means with a catalog entry, bounding box vs. catalog ±5 %, nose at +X and triangle budget, independent copies, turntable smoke test (jassm_er and warmate without a model, spin, hidden = no spin).
