# TASK-127: Side flags in the UI – national / bloc flags next to side names, also in the battle result notice

- **Status**: idea
- **Layers**: presentation (+ data for the flag assets)
- **Depends on**: –  (soft: TASK-120 – the battle result notice with side tabs)
- **Model**: sonnet
- **Topic**: UI

## Goal

Show a flag (NATO / Russia, later per country or bloc) wherever a side is named, so sides are recognised at a glance: first in the battle result notice (`StaffMapBattleResult`: next to the "Victory: <side>" headline and on each side's tab, TASK-120 follow-up, requested by the human 2026-11-09), then the staff map top bar, the contact notice and other places that print a side name.

## Notes

- One shared flag component in `src/presentation/ui/` (a small texture by side id) so each place reuses it; flag textures as assets (free / own drawings only, no licence trouble).
- Follow the HUD v3 look (`docs/design/`): small flat flag with a thin frame in the side's colour.
- Acceptance criteria to be written when the task is picked up (game-designer pass).
