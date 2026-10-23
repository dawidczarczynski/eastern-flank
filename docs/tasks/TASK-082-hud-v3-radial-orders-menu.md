# TASK-082: HUD v3 – radial orders menu (RMB on own unit)

- **Status**: blocked
- **Layers**: presentation (new `OrdersMenu` control + detail card, `BattleController` input routing, `CameraRig` RMB drag vs. click), `HudModel`/new pure `OrdersMenuModel`, localisation, tests, docs. Role: **presentation-engineer**.
- **Depends on**: **TASK-076**, **TASK-081** (orders to offer) (soft: TASK-080 targeting bar + toast, TASK-078 popup suppression)
- **Model**: opus (input arbitration with camera drag, screen-space follow, targeting mode)

## Goal

Right-click (without dragging) on an own unit opens the six-segment radial orders menu from README section 04 ([hud-elementy.html](../design/hud_v3/hud-elementy.html), icons in [icons.svg](../design/hud_v3/icons.svg)); keys 1–6 trigger the slots; the detail card explains the hovered order.

## Design

- **Geometry** exactly as the README: 400×400 canvas, six trapezoids (inner vertex r 84, outer 160, 3 px gaps, points listed in the README), inner dashed hex r 75, tick ring r 168→172 every 5° (→178 every 30°), key numbers 1–6 at r 190, drop shadow. Pure `OrdersMenuGeometry` (segment polygons, label centres, hit test point → segment index) with unit tests. Drawn in `_draw`; icons from `icons.svg` converted to `Curve`/polyline drawing or imported as SVG textures (check Godot SVG import; stroke 24×24).
- **States**: normal / hover (fill+stroke faction colour, ink dark) / disabled / hover-disabled (reddish) with colours from the README; cursor not-allowed on disabled.
- **Follow**: menu centre = `camera.unproject_position(unit)` every frame (clamped inside the viewport); detail card 272 px at x + 206, flips left near the edge: tab `ROZKAZ` (faction colour, red when disabled) + `[n]`, title, description, `▸` effects, footer `KOSZT` / cost or `NIEDOSTĘPNE` + reason; with no hover: unit summary and "Wybierz rozkaz…".
- **Input**: RMB click (press-release without drag beyond a threshold) on an own unit opens it; RMB drag keeps rotating the camera; 1–6 and LMB on a segment trigger; Esc / LMB elsewhere closes; opening hides the hover card. Triggering Move enters the existing move selection; blind fire (and any targeted order) enters a targeting mode: hexes in range highlighted in `#e2c069` (fill .16, ring .6), LMB fires, RMB/Esc cancels, using TASK-080's targeting bar. The menu issues only commands from TASK-081 via `GameSimulation.execute()`; availability, cost, reason and texts come from a pure `OrdersMenuModel` (queried from the core's `validate()`), never from view rules.
- Existing RMB behaviour (deselect) is kept when the click is not on an own unit.

## Acceptance criteria (testable)

- [ ] `OrdersMenuGeometry`: hit-test at each label centre returns its slot; points in the gaps, inside r < 84 or > 160 return none.
- [ ] `OrdersMenuModel`: six slots per unit class in the README order, slot 3 depends on class, disabled slots carry the `validate()` reason, costs from data.
- [ ] Input test: click vs. drag threshold; 1–6 keys; Esc closes; commands only through `GameSimulation.execute()`; enemy/AI-turn units don't open it.
- [ ] Menu follows a moving camera (test with a fake projection); stays on screen.
- [ ] Targeting mode: highlighted set equals the legal targets of the command; cancel leaves state unchanged.
- [ ] Strings in en + pl; `tools/check.sh` passes; screenshot hook for the open menu; README screenshot unaffected unless visible.

## Playtest (for the human)

1. RMB-click an own unit: ring appears on it and follows the camera when you pan/rotate; RMB-drag still rotates without opening the menu.
2. Hover each segment: detail card updates; disabled ones show the reason in red; keys 1–6 work.
3. Use blind fire: range highlight, LMB fires, Esc cancels.

## Player manual

Orders menu, keys 1–6, targeting mode, each order (from TASK-081).

## Out of scope

Order rules (TASK-081), order visuals (smoke, camo, trenches).

## Implementation notes

_Filled in by the agent when done._
