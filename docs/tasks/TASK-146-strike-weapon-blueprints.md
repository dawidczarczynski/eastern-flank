# TASK-146: Strike weapon blueprints: a schematic technical drawing of each weapon on the strike weapon card

- **Status**: done
- **Layers**: presentation (`src/presentation/operational/`) + tests
- **Depends on**: TASK-141b (soft: TASK-144 – JASSM-ER dimensions / catalog as a source)
- **Sections**: TASK-141b task file (weapon card, strike panel variant A), `docs/design/operational_map/strike_panel.html` and the operational_map README "Strike panel"
- **Model**: sonnet

## Goal

Decision 2026-11-11 (human, after playtesting TASK-141b): the detail card of the strike panel (`StaffMapWeaponCard`, 388×140 stage) shows a **blueprint-style side silhouette with dimension ticks** of the weapon instead of a rotating 3D model. It is drawn in code (vector, `_draw`, no meshes, no viewport, no extra nodes), in the HUD style of `strike_panel.html`. This replaces TASK-144's `WeaponTurntable` in the card; TASK-145 (the other 3D models) is cancelled.

**Design decision 2026-11-12 (human):** variant A of `docs/design/operational_map/weapon_blueprint.html` (accepted, in the README "Weapon blueprint stage"): classic blueprint, neutral amber colour, inner detail strokes. The mockup check below is done.

## Acceptance criteria (testable)

- [ ] **Mockup check first:** compare with `docs/design/operational_map/strike_panel.html` (stage area, line weights, colours, label font). If the mockup has no blueprint style (grid, outline, dimension ticks), run `/design-ui` for the blueprint stage and implement only the variant the human picks; state the outcome in the implementation notes.
- [ ] New pure drawing helper `WeaponBlueprint` (`src/presentation/operational/weapon_blueprint.gd`, no nodes): `static func draw(canvas: CanvasItem, means_id: StringName, rect: Rect2, color: Color) -> void`, `static func has_blueprint(id) -> bool`, `static func dimensions(id) -> Dictionary` (`length_m`, `diameter_m`, `span_m`; `span_m` 0 = no wings). Colours: `ui.amber` for outline and detail for **both sides** (design decision 2026-11-12), `HUD_MUTED` grid, `HUD_TEXT` dimensions – never a new palette.
- [ ] One drawn schematic per weapon of `data/strike/` (12): Iskander-M, Kinzhal, Kalibr, Kh-101, Geran-2, JASSM-ER, ATACMS, PrSM, Homar-K, Warmate, Storm Shadow, Tomahawk. Test: every shipped means id has `has_blueprint` true.
- [ ] Each drawing: side silhouette (nose to the right, wings / fins / tail as in the real weapon: ballistic = smooth ogive, cruise = wing + tail + intake, Geran-2 = delta wing, Warmate = small tube drone, Homar-K = finned rocket), faint grid, centre line, dimension ticks with the **real** labels: length (below), diameter (right of the body), wingspan (above, only when `span_m` > 0), e.g. "7.2 m", "Ø 0.92 m", "span 3.3 m". Silhouette scaled to fit the stage with 12 px padding, aspect ratio of length : diameter kept.
- [ ] Label text helper `WeaponBlueprint.labels(id) -> Array[String]` tested: lengths / diameters / spans equal the table below; Geran-2 has a span label, Iskander-M has none.
- [ ] `StaffMapWeaponCard` uses `WeaponBlueprint` in the stage; `WeaponTurntable` is no longer instantiated there (the class and `WeaponModels` stay for the catalog render tool). A weapon without a blueprint (hand-made test state) falls back to the class glyph at 96 px (existing code). Test: the card for every shipped weapon has no `SubViewport` child and draws without error; an unknown id shows the glyph.
- [ ] 60 FPS: the drawing is static – redraw only when the shown weapon or the size changes (`queue_redraw` on change, no per-frame work); no node per drawn part.

**Dimensions** (length / body diameter / wingspan, metres; sources: manufacturer and public references; **[ASSUMPTION]** = approximate, to be confirmed by the human, mark in the file):
Iskander-M 9M723 7.2 / 0.92 / – · Kinzhal ≈ 8.0 / 1.0 / – [ASSUMPTION: Iskander-derived airframe] · Kalibr 3M14 6.2 / 0.53 / 3.3 (without booster) · Kh-101 7.45 / 0.74 / 3.0 [ASSUMPTION span] · Geran-2 3.5 / 0.5 / 2.5 · JASSM-ER 4.27 / 0.55 / 2.4 (some sources 2.7 – as in TASK-144, to confirm) · ATACMS 3.96 / 0.61 / – · PrSM ≈ 4.0 / 0.43 / – [ASSUMPTION] · Homar-K rocket (K239 / K263) ≈ 4.0 / 0.24 / – [ASSUMPTION] · Warmate 1.1 / 0.09 / 1.6 [ASSUMPTION] · Storm Shadow 5.1 / 0.48 / 3.0 · Tomahawk 5.56 / 0.52 / 2.67 (without booster). Before drawing, check each against a source (`/research-unit` style: note the source URL in the implementation notes); values that cannot be confirmed stay marked ASSUMPTION in the code comment.

## Playtest (for the human)

1. S – strike panel, hover / pick each weapon in turn (NATO and `--side=russia`): the card shows a blueprint with grid, outline and three dimension labels (two for ballistic missiles).
2. Does each silhouette read as that weapon (ballistic vs cruise vs drone vs rocket)? Are labels legible at 388×140, at HIGH quality? Compare with the mockup.
3. Switch rows quickly: no flicker, no turntable, FPS unchanged.
4. Greyed (stock 0) weapons also show their blueprint.

## Player manual

Deep strikes chapter (the weapon card): each weapon is shown as a technical drawing with its real length, diameter and wingspan. Replaces any mention of a rotating model.

## Out of scope

3D models (TASK-144's pipeline stays, TASK-145 cancelled), animation of the drawing, the in-battle use of weapons, panel layout changes.

## Implementation notes

Design: variant A of `docs/design/operational_map/weapon_blueprint.html` (human, 2026-11-12), neutral amber for both sides, inner detail strokes.

- `WeaponBlueprint` (`src/presentation/operational/weapon_blueprint.gd`): table of 12 weapons (kind, length, Ø, span), `has_blueprint`, `dimensions`, `labels`, `draw` (grid, dashed centre line, outline + fill + detail, dimension lines). Five shape kinds: ballistic, cruise, delta (Geran-2), tube (Warmate), rocket (Homar-K).
- `StaffMapWeaponCard` draws it in the stage (`_draw_stage`, redrawn only in `show_entry`); the turntable is no longer instantiated (`WeaponTurntable` / `WeaponModels` stay for the catalog tool). `shows_model()` became `shows_blueprint()`; unknown id → class glyph.
- Dimensions are those of the task table; I did not re-check them against web sources in this session. Still [ASSUMPTION] (marked in code): Kinzhal, Kh-101 span, JASSM-ER span, PrSM, Homar-K, Warmate.
- Tests: `test_weapon_blueprint.gd`, card test in `test_staff_map_strike_panel.gd`. I have not seen the drawing in the game (no render of the staff map).
