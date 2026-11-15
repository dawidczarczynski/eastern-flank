# Order lines v2 – analysis of variants A / B / C and variant D

**ACCEPTED 2026-11-15** (variant D "Armed line") · visuals: `order_lines.html` · decisions in section 7

## 1. Facts from the code (checked)

| # | Fact | Where |
|---|---|---|
| F1 | A left click on a hex **already issues** MARCH / ATTACK and deselects; the ring (RMB) is the optional path. Keys 1-3 arm a posture for the next click. So today's flow *is* variant B without the visuals. | `StaffMap.click_at`, `_pick_posture_key` |
| F2 | LMB and MMB drag pan the camera; a click is a release within 5 px (`CLICK_SLOP`). A press on a counter also pans. | `StaffMap._on_mouse_button` |
| F3 | No touchpad gestures are handled (no pan / magnify events); no `StaffMapInput` class exists – input lives in `StaffMap` (95 KB). | grep, CODEMAP |
| F4 | An order is **destination + posture only**; the route is re-planned every turn. No waypoints, no road-junction graph (roads are per-hex link masks). | `FormationOrder`, `OperationalRoutes`, GDD "Orders and postures" |
| F5 | Every `IssueOrderCommand` costs one of the turn's orders (C2 limit), also when it replaces an order; cancel refunds nothing. No undo. | `IssueOrderCommand.apply`, `CancelOrderCommand` |
| F6 | `destination == formation.coord` is rejected; "defend here" is `SetPostureCommand`. Two orders may target the same free hex (the later one halts short at execution). | `IssueOrderCommand.validate`, GDD |
| F7 | The line shader has `across` (px from the centre) but **no along-line coordinate**; dashes are cut on the CPU in map units (they scale with zoom). HDR glow exists (`set_glow`). | `staff_map_line.gdshader`, `StaffMapRoute.dashes`, `StaffMapRouteRibbon` |
| F8 | Accepted style (TASK-092d): march dashed, advance solid, defend arc; cursor label "cost · turns · stop" and border gate marks already drawn live. | `StaffMapRoute.style`, `StaffMapRouteMarks` |
| F9 | An unreachable target yields an empty route (cross + reason at the hex); a partial line exists only for a closed country. | `StaffMapRoutePreview.rebuild` |
| F10 | Single selection only; fog is not implemented (TASK-100, idea). | `StaffMapCounters`, BACKLOG |

Not checked (assumptions): number of formations per operation, whether issued orders are hidden at Z0, bloom look of a rail line, behaviour on a real touchpad.

## 2. Critique of A / B / C

| Item | Verdict | Why |
|---|---|---|
| "Today = 3 steps through the ring" | wrong premise | F1. The pain is feel and safety, not the step count. |
| A: release = commit | risky | F5: a slipped release burns a scarce order. Needs cancel-by-return and the free re-aim rule. |
| A: drag from the counter | workable, not alone | Conflicts with pan only on a counter press (F2); dense counters at Z0 leave little to grab for panning; hold-drag is poor on a touchpad (F3). Must coexist with click–click. |
| A: pull handle (r 5 px) | drop | Tiny target, clutter; the counter is the handle. |
| A: drop on own hex = DEFEND | drop | F6, and release on the own counter is the natural cancel. |
| A / B: waypoints, road nodes | not presentation work | F4: new rules, command, codec, save, forecast, AI. |
| A5: line to the "last reachable point" | not available | F9: the planner returns nothing for an unreachable target. |
| B: posture rail under the counter | drop | Duplicates keys 1-3 and the armed chip in the unit strip (F1). |
| B: RMB disarms | conflict | RMB opens the ring while a formation is selected. |
| Order chip (A, B) | drop for MVP | Duplicates the existing cursor label (F8); `ui.panel` is not a README token. "3 vs 4" odds will not survive fog (F10). |
| C | closest to the code | It is F8 plus the drag. |
| Line language swap (march solid, attack rail) | needs a decision | Re-styles an accepted spec (F8). Keep march dashed, add the rail only to attack. |
| "Rail = two meshes" | simpler | One mesh: hollow the core in the fragment shader with `across` (F7). |
| Flow dots | feasible | Add cumulative length in `UV.y` + a `px_per_unit` uniform + `TIME`; pitch foreshortens N–S dashes slightly. Animate only while aiming. |
| "Catmull-Rom through hex centres" | backwards | An interpolating spline keeps the staircase. Simplify the path (tolerance ≈ 0.35 hex), then Chaikin. |
| "Follows the roads" | overclaim | The line runs through hex centres, beside the drawn OSM road. |
| Own line `#5b93d6` vs rivers `#5384a0` | weak contrast | Keep the dark casing and the lightened colour; rail and dashes carry the meaning. |
| Missing everywhere | – | Orders left (F5), editing issued orders, same-destination conflict (F6), posture alternative (march vs advance route), Z0 legibility, disabled states (strike mode, modal, slide, not own turn). |

## 3. Further options

| Option | Player value | Cost | Verdict |
|---|---|---|---|
| Destination ghost (+ T+n) | high – shows positions, not only routes | low (support-ghost look exists) | **stage 2** |
| Posture alternative line (advance vs march) | high – the route differs by posture | low (second plan call, debounced) | **stage 2** |
| Same-destination conflict mark | medium, prevents wasted orders | low (view-only scan) | **stage 2** |
| Far-zoom stub for short orders | medium (hex = 8 px at Z0) | low | **stage 2** |
| Orders left in the cursor label | high | trivial | **MVP** |
| T+1 reach contour (isochrone) | high – aim before hovering | medium: new pure reach query in `OperationalRoutes` + smoothed contour | **stage 3** |
| Edit by dragging the line head | high | medium + rule change (F5) | **stage 4** |
| Converging-attack tally ×n | medium | low | **stage 2**, view only |
| True undo / redo | medium | high (command log, replay) | rejected – free re-aim + refund on cancel covers it |
| Box / multi-select, group orders | low-medium at this scale | high (F10, pan conflict, one formation per hex, n orders spent) | rejected for now |
| Keyboard-only ordering | low | medium (WASD = camera, Enter = end turn) | rejected; keep Tab, 1-3, Esc, ⌫ |
| Delay / wait order | – | new rules (GDD parks `delay` behind TASK-095) | out of scope |
| Front-crossing tick | low (stop reason already says "contact") | low | rejected |
| Enemy zone ring | medium – explains the detour | low | optional, stage 2 |
| Fog-safe target marks | future | – | note for TASK-100: dashed brackets on estimated contacts, no odds |

## 4. Recommended direction: D – "Armed line"

One gesture machine for click–move–click **and** press–drag–release; no handle, chip or rail; the ring stays on RMB.

| State | Enter | Exit |
|---|---|---|
| IDLE | start, commit, cancel | LMB on own counter → ARMED; LMB drag elsewhere pans |
| ARMED | click or press on own counter | cursor on a hex → AIMING; Esc / click the counter again → IDLE |
| AIMING (hover or drag) | button up: cursor over a hex; button down: travel > 5 px | click / release on a valid hex → COMMITTED (or CONFIRM); invalid hex → stays, label gives the reason; Esc, RMB while dragging, release on own counter → ARMED |
| SNAPPED / INVALID | sub-states of AIMING: target hex planned (60 ms debounce) with / without a route | – |
| CONFIRM | border incident on the route | existing prompt: Enter → COMMITTED, Esc → AIMING |
| COMMITTED | command accepted | 120 ms settle to 82 % → IDLE |
| EDITING (stage 4) | press the head grip of an issued line | as AIMING; Esc restores |

Camera while aiming: wheel zoom, WASD and edge pan stay active; MMB drag pans; LMB drag pans only when the press was not on an own counter. Gesture disabled in strike mode, under a modal, during the slide and outside the viewer's turn. Keys 1-3 force the posture in ARMED / AIMING (existing `_pick_posture`).

## 5. Stages and class changes

| Stage | Content | Classes |
|---|---|---|
| 1 MVP | gesture machine; flowing screen-px dashes; attack rail + spear + brackets; label with orders left; commit settle | new pure `StaffMapOrderGesture` (states, tested headless); `StaffMap` (route mouse events to it, drop inline click logic); `StaffMapLines` + `staff_map_line.gdshader` (`UV.y` length, `rail`, `dash`, `flow` uniforms); `StaffMapRouteRibbon` (style setters); `StaffMapRoute.style` (rail, head kind; path simplification); `StaffMapRouteMarks` (heads, brackets, label); `StaffMapRoutePreview` (pass orders left) |
| 2 | ghost, alternative line, conflict mark, tally, far-zoom stub | `StaffMapRoutePreview`, `StaffMapRouteMarks`, `StaffMapOrders` |
| 3 | reach contour | core: `OperationalRoutes` reach query (+ tests); new `StaffMapReachLayer` (pattern of `StaffMapControlLayer`) |
| 4 | head-grip editing | GDD + `IssueOrderCommand` (free re-aim this turn) via game-designer; `StaffMapOrderGesture`, `StaffMapOrders` (head hit-test) |
| Later | demote or remove `StaffMapOrderRing` once D is proven | `StaffMapOrderRing`, `StaffMapOrderRingModel` |

Docs to touch on acceptance: operational_map README "Orders", ARCHITECTURE (no new events expected), MANUAL.

## 6. Open questions

1. Rule: is re-aiming (or cancelling) an order given this turn free? Without it, editing and release-to-commit stay costly.
2. Line language: keep march dashed / advance solid (accepted) and add the rail only to attack, or adopt v1's swap?
3. Is the drag the primary gesture, or is click–click enough with the new visuals (touchpad use)?
4. Keep the ring on RMB long-term, or reduce it to INFO + cancel?
5. Reach contour: T+1 for march only, or follow the armed posture?
6. Is the converge tally wanted while the rules give no multi-attacker effect?

## 7. Decisions (human, 2026-11-15)

1. Re-aiming or cancelling an order issued **this turn is free** (rule change, stage 4 + GDD via game-designer).
2. Line language: **keep the accepted styles** (march dashed, advance solid, defend arc); the rail, spear and brackets only for attack – as in `order_lines.html`.
3. **Click–click is the primary gesture**; press-drag-release is deferred (touchpad).
4. The **order ring stays** on right click.
5. Reach contour (stage 3): **march only**, T+1.
6. Converging-attack tally ×n: **not now** – first a separate rules question (several attackers on one target), see its own task.
