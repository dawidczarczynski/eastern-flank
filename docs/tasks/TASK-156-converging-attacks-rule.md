# TASK-156: Several attackers on one target – should the rules reward it?

- **Status**: idea
- **Layers**: core (maybe) / design
- **Depends on**: –
- **Sections**: GDD "Orders and postures", GDD "Battle hand-off and auto-resolve"
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Decide whether several formations attacking the same enemy formation should give an effect (for example a bonus for a converging attack or a flank), so that the staff map has something meaningful to show.

## Why it is open

Today two attacks on one target are only two separate contact battles in sequence; nothing rewards coordination. The order-lines design (decision 6, 2026-11-15) therefore drops the converging-attack counter "x n" from the order UI until this is decided. **The tally x n in the UI waits for this decision.**

## Open questions (not decided here)

1. Should converging attacks change anything at all, or stay as they are (the counter is then never built)?
2. If yes: a flat bonus per extra attacker, a flank bonus by the direction of approach, a combined battle (several attackers in one battle), or a defender penalty after the first battle of the turn?
3. Does it apply to played battles, to auto-resolve, or both (both resolvers must change together)?
4. Does the order of execution matter (order-of-battle order), and would the AI have to plan convergence (TASK-102)?
5. Does it need a cap (for example at 3 attackers, one per free adjacent hex) and how does it interact with the one-formation-per-hex rule?
6. How would it be shown in the UI (tally on the target, per-line badge) and which numbers does the player see before committing?

## Acceptance criteria (testable)

To be written when the rule is decided (record the decision in the GDD "Open questions" first).

## Player manual

Depends on the decision.

## Out of scope

- The UI tally (a follow-up task once the rule exists).

## Implementation notes

_Idea only._
