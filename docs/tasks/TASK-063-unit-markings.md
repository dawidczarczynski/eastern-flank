# TASK-063: Unit markings – national markings per faction and tactical numbers on vehicles

- **Status**: ready (one open question with a proposed default, see below)
- **Layers**: core data (`FactionDefinition` Presentation group + `data/factions/*.tres`), presentation (`MarkingTextures`, `UnitModels` applies markings at anchors), model files (`Marking*` anchors), tests. Roles: **presentation-engineer** (system), **unit-modeler** (anchors in each vehicle model, render check).
- **Depends on**: TASK-038 (factions as data, done), TASK-036 (model pipeline + contract test, done); soft **TASK-062** (markings sit on the worn paint), soft TASK-043 (model metadata conventions)
- **Model**: sonnet

## Goal

Vehicles carry the markings a real army paints on them: the Polish red-and-white checkerboard and a white three-digit tactical number, Russian vehicles their tactical number – small details that make the models read as real equipment, not toys.

## Open questions / decision needed (human)

- **Russian national marking**: Russian Ground Forces vehicles usually carry no consistent national insignia (tactical numbers and unit symbols vary). Proposed default **[ASSUMPTION]**: Russia = **tactical number only, no national marking**. Explicitly **no** "Z"/"V" invasion symbols (political, and not a stable real marking). Alternative: a small Russian tricolour on the hull rear. The human decides; the data field makes either a one-line change.
- **Polish marking**: proposed the red-white checkerboard ("szachownica") as used on Polish army vehicles, small, on both hull sides and/or turret. Confirm placement per vehicle with the unit catalog references (`docs/design/units/units/<id>/`).
- Tactical numbers are cosmetic and derived from the unit id (below); they are not shown in the HUD.

## Design

- `FactionDefinition` (Presentation group): `@export var national_marking: StringName` (`&"pl_checkerboard"`, `&"ru_flag"`, `&"none"`), `@export var number_color: Color` (Poland `#e8e8e0`, Russia `#e8e8e0`), `@export var number_style: StringName` (`&"stencil"`). Set in `data/factions/poland.tres` / `russia.tres` (Russia `&"none"` per the default above). Core/AI never read these (ADR 0007 rule unchanged).
- **Textures** – pure `MarkingTextures` (static, cached): `checkerboard(size)` (2×2 red `#d4213d` / white squares with a thin red-white border, as the Polish military checkerboard), `flag_ru(size)` (white/blue/red stripes). Slightly desaturated + faint noise so they look painted; alpha-cut edges.
- **Tactical number**: `UnitModels.tactical_number(unit_id: int, faction_index: int) -> String` – 3 digits, deterministic: `100 + (unit_id · 37 + faction_index · 500) % 900` (37 is coprime with 900, so unit ids 0–899 of one side never collide); a different formula is fine if it keeps these properties – record it. Rendered with a `Label3D` (non-billboard, `shaded = true`, `alpha_cut` discard, a stencil-like mono font from the HUD theme or a bundled OFL stencil font, colour `number_color`, pixel size so digits are ≈ 0.35 m tall at model scale).
- **Anchors** in each **vehicle** model file (unit-modeler): `Marker3D` nodes named `Marking_*` (national marking) and `Number_*` (tactical number) on flat surfaces, oriented with −Z out of the surface; the markings/labels are offset 0.002 off the surface to avoid z-fighting. Infantry models have none. Models without anchors simply get no markings (no error).
- Markings are attached under the anchor's pivot, so they move with turrets/pods.
- **Anchor pass**: the vehicle anchors of TASK-063 (`Marking_*`, `Number_*`) and TASK-064 (`Exhaust`, `Dust_L`/`Dust_R`) are added to the four vehicle models in **one** `unit-modeler` rework per vehicle when the two tasks run close together (feedback lists both anchor sets; for the Homar-K / Uragan also the TASK-045 jacks / shields if that rework is still pending). The task done second only checks the anchors already exist.

## Acceptance criteria (testable)

- [ ] `test_marking_textures.gd`: checkerboard has 4 equal quadrants alternating red/white (sample centres), border pixels red or white, deterministic; flag has 3 horizontal stripes in the right order.
- [ ] `tactical_number`: always 3 digits in [100, 999]; deterministic; the 4 units of each side in the default scenario get 4 different numbers.
- [ ] `FactionDefinition` loads with the new fields from both faction `.tres`; Russia `national_marking == &"none"` (or the human's choice).
- [ ] `test_unit_model_contract.gd`: every vehicle model (`unit_class` tank / mlrs) has ≥ 1 `Number_*` anchor and ≥ 1 `Marking_*` anchor; anchors are inside the model AABB.
- [ ] A built Polish tank has checkerboard quads at its `Marking_*` anchors and `Label3D`s with its number at `Number_*`; a Russian tank has numbers but no national marking quads (default); a marking under a turret anchor is a descendant of the `Turret` pivot.
- [ ] unit-modeler check: `tools/render_unit.sh <id> --faction=<id>` for every vehicle and its factions – sheets read, markings placed on plausible surfaces, not floating or clipping.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. Zoom in on the Polish Abrams and Homar-K: small red-white checkerboards and white three-digit numbers on the hull/turret.
2. Russian T-72B3 and Uragan: white numbers, no national insignia (unless you chose the flag).
3. Turn a turret (attack with a tank): markings on the turret move with it.
4. No flickering on the markings when the camera moves; they are lit like the paint (dark in shadow).
5. Different vehicles of one side have different numbers.

## Player manual

Section on units/the unit tag: one line – "Vehicles carry their army's markings (Polish vehicles the red-and-white checkerboard) and a tactical number; the number is only decoration."

## Out of scope

- Unit/formation symbols, slogans, kill markings, custom player numbering, HUD display of the number.

## Implementation notes

_Filled in by the agent when done._
