# TASK-153: Staff map – order gesture "Armed line" (stages 1 + 2: MVP and preview)

- **Status**: to playtest
- **Layers**: presentation
- **Depends on**: – (soft: TASK-154 free re-aim; the MVP works without it)
- **Sections**: GDD "Orders and postures"; design/operational_map/order_lines_analysis.md sections 4, 5, 7 (the spec); order_lines.html (variant D); operational_map README ("Order gesture")
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Ordering a formation becomes a safe, readable click–click gesture: click the own counter (armed), move the cursor (live line to the hex), click the hex (order issued). The player sees the line, the stop, the attack marks, the orders left, and the formation's end position before committing.

## Look (Claude Design)

Accepted variant D in order_lines.html. Keep the TASK-092d styles: march dashed, advance solid, defend arc; rail, spear head and brackets only for attack (decision 2). Reuse the support-ghost look for the destination ghost. Compare screenshots with the mockup and state deviations.

## Acceptance criteria (testable)

Stage 1 – MVP

- [x] New pure class `StaffMapOrderGesture` (RefCounted, no nodes, tests in `tests/unit/test_staff_map_order_gesture.gd`) with states IDLE, ARMED, AIMING (sub-states SNAPPED / INVALID), CONFIRM, COMMITTED; it returns intents, never touches the simulation.
- [x] Transitions as in analysis section 4: LMB on an own counter IDLE → ARMED; cursor over a hex → AIMING; click on a valid hex → COMMITTED (or CONFIRM when the route has a border incident: Enter → COMMITTED, Esc → AIMING); click on an invalid hex stays in AIMING and exposes the reason; Esc or a second click on the counter → ARMED / IDLE; COMMITTED → IDLE after 120 ms.
- [x] Keys 1–3 change the posture in ARMED and AIMING; RMB still opens the order ring (no disarm on RMB); the ring path is unchanged.
- [x] Gesture disabled (stays IDLE) in strike mode, under a modal, during the counter slide and outside the viewer's turn; one test per case.
- [ ] LMB drag pans the camera when the press was not on an own counter; wheel zoom, WASD and edge pan work while armed. Drag-to-aim is not built (decision 3). The inline click logic in `StaffMap` is replaced by calls into the gesture class.
- [x] Line dashes flow in screen pixels (pitch independent of zoom): `staff_map_line.gdshader` gets the along-line length in `UV.y` and `px_per_unit` / `flow` uniforms; animated only while aiming. Path simplified (tolerance about 0.35 hex) before Chaikin.
- [ ] Attack line: hollow rail (core hollowed in the fragment shader with `across`), spear head at the target, four corner brackets on the target counter; no rail on march / advance / defend.
- [x] Cursor label shows "cost · turns · stop" plus "orders left n" (from `OperationalState.orders_left()`); at 0 left the label reads the `no_orders_left` reason and the click is refused without a command.
- [ ] Commit animation: the issued line settles to 82 % opacity over 120 ms.
- [x] Simulation untouched (`OperationalState.snapshot()` identical with and without the gesture); the command is the existing `IssueOrderCommand`.

Stage 2 – preview

- [x] Destination ghost at the target hex with "T+n" (turn of arrival from the forecast); hidden for an invalid target.
- [ ] Alternative-posture line: a thin faint second line for the other contact-relevant posture (march vs advance) when its route differs; second plan call debounced 60 ms; absent when the routes are equal.
- [ ] Goal-conflict mark: when another own formation already has an order to the same hex, a mark at the hex (view-only scan of `formation.order`); no rule change.
- [ ] Far-zoom stub: at Z0 an order shorter than a minimum screen length still draws a stub of at least 8 px with its head.
- [x] Alternative line, ghost and conflict mark each have a pure model function with a headless test (hand-made state).

## Playtest (for the human)

1. Click an own counter: it is armed, the unit strip shows the armed posture. Move over a hex: a dashed marching line with flowing dashes, a label "cost · turns · stop · orders left n", and a ghost with T+n at the end. Zoom in and out: the dash pitch stays constant on screen.
2. Press 2 over an enemy: rail, spear head and brackets appear; pressing 1 turns it back to a dashed line.
3. Click the hex: the order is issued, the line settles. Esc while armed cancels without spending an order.
4. Aim at water or a closed country: the label gives the reason and a click does nothing.
5. With 0 orders left the label says so and the click is refused. Pan with LMB on empty ground and RMB on a counter (ring) while armed.
6. Give two formations the same destination: the conflict mark appears. At Z0 a short order still shows a visible stub.

## Player manual

"Operational map" chapter, orders: the click–click flow (click the counter, move, click the hex), Esc to cancel, keys 1–3 for the posture, the attack line style, orders left in the label, ghost with T+n, the alternative line and the conflict mark. The ring stays on RMB.

## Out of scope

- Press–drag–release aiming (deferred, touchpad); editing an issued order by its head (TASK-157); the T+1 reach contour (TASK-155); the converging-attack tally ×n (waits for TASK-156); waypoints; multi-select; removing the order ring.

## Implementation notes

_Large task: split at the Stage 1 / Stage 2 boundary._

**Stage 1 (MVP) implemented.**

- `StaffMapOrderGesture` (src/presentation/operational/staff_map_order_gesture.gd): pure RefCounted machine IDLE / ARMED / AIMING (Aim SNAPPED / INVALID) / CONFIRM / COMMITTED. Inputs: `set_context(strike, modal, sliding, viewers_turn)`, `select(id)`, `click_own_counter(id)`, `hover(hex, verdict, orders_left)`, `click_hex(hex, verdict, orders_left)`, `confirm()`, `cancel()`, `pick_posture(p)`, `fail()`, `tick(dt)`. They return intents (`ARM`, `DISARM`, `ISSUE`, `CONFIRM_NEEDED`, `REJECT`, `POSTURE`, `NONE`); `verdict` = {valid, reason, incident}. Tests: tests/unit/test_staff_map_order_gesture.gd (pure) and test_staff_map_order_gesture_view.gd (wired into StaffMap).
- In the game "armed" = an own formation selected on its side's turn (the click-click flow already existed); `StaffMap.click_at` now routes through the gesture (`_gesture_click_hex`, `_disarm_by_click`, `_click_bare_map`), `_pick_posture` is replaced by the gesture's posture, Esc steps back (posture, aiming, arming). A second click on the armed counter deselects (behaviour change).
- Flowing dashes: `staff_map_line.gdshader` gets UV.y = length along the line, `dash_on_px` / `dash_off_px` / `px_per_unit` / `flow_px` / `hollow_px`; `StaffMapRouteRibbon` has three looks (SOLID, DASHED, RAIL) and flows only after `set_flowing(true)` (aiming). Dashes are no longer pre-cut in map units. `StaffMapRoute.simplify` (Douglas-Peucker, 0.35 hex) runs before Chaikin.
- Attack look: rail (hollow core) + spear head + four brackets (`StaffMapRouteMarks`) when `StaffMapRoute.is_attack` (enemy on the target hex and a posture that does not avoid contact).
- Cursor label: `StaffMapRoutePreview.cursor_label` = "cost · turns · stop · ORDERS LEFT n / m"; at 0 left it reads the `no_orders_left` text and the click sends no command.
- Commit settle: the new order is drawn on a separate fresh ribbon (`StaffMapOrders.mark_fresh / settle`), full opacity to 82 % in 120 ms.
- Not visually verified: the attack rail / spear / brackets (no enemy within reach in the screenshot scenario) and the flowing animation (a still image).

**Stage 2 (preview) implemented.**

- Pure model `StaffMapOrderExtras` (src/presentation/operational/staff_map_order_extras.gd, tests/unit/test_staff_map_order_extras.gd): `ghost(preview, verdict)` -> {hex, "T+n"} (n = forecast turns, {} for an invalid target), `alternative_posture` (march <-> advance, none for defend), `alternative(state, formation, hex, posture, main)` -> {posture, preview} only when the other posture's route or turn count differs, `conflict(state, formation, hex)` -> {formation_id, text} from a read-only scan of other own `formation.order`, `stub(from, to)` -> the far-zoom stub segment (below 28 px on screen: 20 px long, never under 8 px, starting at the counter edge).
- Drawing: `StaffMapOrderExtrasPaint` (ghost = dashed counter outline 1.3 px, 4/3 dashes, 85 %, "T+n" under it; conflict = `ui.amber` triangle with "!" plus a one-line plate; stub = line with casing and chevron head, alert colour for attack) called from `StaffMapRouteMarks._draw_route`; the entries gain `extras` (preview) and `start` (issued orders and preview, for the stub). Colours come from the marks' palette tokens (`colour`, `amber`, `alert`, `panel`, `ink`).
- Alternative line: second `StaffMapRouteRibbon` (`set_thin(1.3)`, 60 % opacity, same march-dashed / advance-solid kind) owned by `StaffMapRoutePreview.set_alt_ribbon`; its plan runs inside the debounced `rebuild` (60 ms), so hovering alone plans nothing (`alt_plans_made()`).
- View tests in test_staff_map_order_gesture_view.gd (ghost, no ghost on an occupied hex, conflict mark, identical snapshot, one alternative plan per rebuild).
- Seen in a screenshot: the ghost with "T+3" at the target. Not seen: the alternative line, the conflict mark and the stub (the screenshot scenario produced none of them in view; covered by unit tests only).
- Deviations: no "2 ADVANCE . n T . stop" plate on the alternative line (the mockup has one); the conflict text is one plate above the triangle, as in D5; the stub is applied to every route entry whose `start` is known, including issued orders.

**Review follow-ups (2026-11-15).**

- The conflict text now says what the rules do (`end_operational_turn_command.gd`: a destination held by an own formation interrupts the later order with `destination_occupied`): "%s IS ORDERED HERE – THE SECOND TO ARRIVE IS HALTED" (EN key, PL in strings.csv, MANUAL). This deviates from the accepted mockup D5 caption ("ONE HALTS SHORT") on purpose; the mockup was not edited.
- Added view test for RMB: the ring opens and the formation stays selected. **Not covered by a headless test**: LMB-drag pan (the `_input` path is unchanged), the 82 % settle opacity (only `has_fresh()` is asserted), drawing of the spear head / brackets / Z0 stub (only the pure `is_attack` / `stub` have tests). These go to the playtest.
- Known approximations: dash pitch uses one `px_per_unit` at the view centre, so under a steep tilt the pitch varies across the screen; while the gesture is blocked (strike mode, modal, slide, not the viewer's turn) a hex click still goes straight to `issue_order` so the command gives its rejection toast; a REJECT while aiming (invalid hex, no orders left) shows its reason in the cursor label and no toast. `StaffMapRouteRibbon._process` builds a small lambda per frame while aiming (3 kinds x 2 materials); negligible, worth caching if profiling ever asks.
