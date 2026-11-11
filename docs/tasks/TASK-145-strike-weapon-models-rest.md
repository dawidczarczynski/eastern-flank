# TASK-145: Strike weapon 3D models (2/2): the remaining eleven weapons

- **Status**: done (superseded by TASK-146: cancelled, never built)
- **Layers**: presentation (`src/presentation/models/weapons/`) + tests
- **Depends on**: TASK-144
- **Sections**: TASK-144 (pipeline, pattern), GDD "Deep strikes"
- **Model**: opus
- **Agent**: unit-modeler

## Goal

Models for Iskander-M (9M723), Kinzhal, Kalibr (3M14), Kh-101, Geran-2, Storm Shadow, ATACMS, PrSM, Homar-K rocket (K239 / K263), Warmate and Tomahawk, built with the TASK-144 pipeline and registered in `WeaponModels`. Several can share a base mesh (cruise missiles, ballistic missiles) with per-weapon proportions. May be split into one task per class (cruise, ballistic, drone / loitering, rocket) when it is started; each weapon needs its own catalog entry with real dimensions first.

## Acceptance criteria (testable)

- [ ] Every shipped `data/strike/*.tres` weapon has `WeaponModels.has_model(id)` (test over the shipped list) and a catalog entry; bounding boxes match the catalog (±5 %), ≤ 400 triangles each.

## Out of scope

Panel and look data (TASK-141b).

## Implementation notes

**Cancelled 2026-11-11** (human decision after playtesting TASK-141b): strike weapon cards show a schematic blueprint drawing of each weapon instead of a 3D turntable model, so the remaining eleven 3D models are not built. Replaced by TASK-146 (`WeaponBlueprint`). Nothing was implemented; the status uses the project's `done (superseded …)` convention.
