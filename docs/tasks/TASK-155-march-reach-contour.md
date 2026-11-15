# TASK-155: Staff map – T+1 reach contour for the march posture (stage 3)

- **Status**: ready
- **Layers**: core (pure query) + presentation
- **Depends on**: TASK-153
- **Sections**: GDD "Orders and postures", GDD "Movement costs"; order_lines_analysis.md sections 3, 5, 7 (decision 5); `StaffMapControlLayer` as the pattern
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

While a formation is armed the player sees how far it can get in one turn on a march, and can aim before hovering (decision 5: march only, T+1, not the armed posture).

## Acceptance criteria (testable)

- [ ] New pure query in `OperationalRoutes`, e.g. `reach(state, formation, budget, avoids_contact) -> Dictionary` (hex → cost spent): all hexes the formation can end a turn on with the march budget, using the same step costs, zone-of-control avoidance and "first step is always made" rule as `forecast`; own hexes are passable but not ending hexes. Tests on a hand-made state: all road (8 points = 8 hexes), open ground (4 hexes), forest, an enemy zone of control blocking, water impassable, a stuck formation (first step only), deterministic.
- [ ] Consistency test: for any hex in the reach set, `forecast` with the same budget finishes there in one turn; for a hex outside, it needs more than one.
- [ ] New `StaffMapReachLayer` draws the contour of the reach set (outer boundary only, simplified and smoothed like the control contour, thin, below the counters); visible only in ARMED and AIMING, not for the other postures.
- [ ] Rebuilt only when the armed formation or the state signature changes, never per frame; the simulation is untouched.
- [ ] A formation with the defend / advance posture armed still shows the march contour (decision 5).

## Playtest (for the human)

1. Arm a formation: a thin contour appears around the hexes it can reach in one march turn; along a road it stretches out.
2. Arm one next to an enemy: the contour avoids the enemy's zone of control. Press Esc: it disappears. Pan and zoom: it stays 1-2 px wide.

## Player manual

Orders: while a formation is armed a contour shows how far it gets on a march in one turn.

## Out of scope

- Contours per posture, multi-turn isochrones, fog-aware reach (TASK-100).

## Implementation notes

_Filled in by the agent when done._
