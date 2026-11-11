# TASK-129: Staff map – order ring card overlaps the formation card

- **Status**: done
- **Layers**: presentation
- **Depends on**: –
- **Sections**: docs/design/operational_map (cards, order ring), docs/design/hud_v3/README.md §04
- **Model**: sonnet

## Goal

With a formation selected and the order ring open, the ORDER detail card (`RingDetailCard`, right of the ring) no longer covers the FORMATION card; the player can read both. Seen in `docs/images/staff_map.png` (Russian 4th Motor Rifle Battalion selected, ring open on hex 40·46): the order card hides the formation name, type and stat rows.

## Acceptance criteria (testable)

- [ ] Order ring card and formation card never overlap at 1280×720 and 1920×1080, wherever the ring hex is (incl. near the right edge).
- [ ] Fix follows the mockup in docs/design/ (state any deviation); a layout test covers the non-overlap rule (pure model if possible, see `StaffMapOrderRingModel`).
- [ ] `tools/readme_screenshot.sh` staff map shot shows both cards readable; regenerate and commit `docs/images/staff_map.png`.

## Playtest (for the human)

1. Staff map, select a formation, right click a hex near the right side of the screen.
2. Expect: ring + order card and the formation card are both fully readable.

## Player manual

none

## Out of scope

- Redesign of the cards.

## Implementation notes

`RadialRingGeometry.card_position_avoiding` (pure, tested in test_radial_ring_geometry.gd at 1280×720 and 1920×1080, ring at many positions incl. right edge) keeps the order card off a given rect: right side, then left, then above/below the rect. `StaffMapOrderRing` takes an optional `avoid` callable; `StaffMap._panel_rect()` supplies the docked formation panel rect. No visual redesign, no mockup deviation. `docs/images/staff_map.png` regenerated: the order card now sits left of the ring, both cards readable.
