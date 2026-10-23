# Handoff: Tactical HUD — Eastern Flank

## Overview
HUD for a turn-based hex strategy game (3D map rendered separately). Military C2 / fire-control aesthetic: chamfered panels, thin amber frames, angled header tabs, hatched stripes, monospace data. Covers: turn bar, unit card, terrain card, radial orders menu, end-turn module, key hints, targeting bar, toast, turn banner, loading screen.

## About the Design Files
`hud-elementy.html` is a **design reference built in HTML** (self-contained, open in a browser) — not production code. Recreate these components in the target codebase's environment (React/Vue/game-engine UI etc.) using its patterns. All visuals are CSS (clip-path, gradients) + inline SVG — no bitmap assets except the unit portrait (supplied by the game).

## Fidelity
**High-fidelity.** Colors, type, spacing and shapes are final. Reproduce pixel-accurately.

## Design Tokens
Colors
- `--bg-app` #0a0c09
- `--panel` rgba(8,11,8,.86) (popups/cards: rgba(8,11,8,.93)); backdrop-filter: blur(10px)
- `--line` rgba(232,176,74,.34) — all 1px frames, dividers, tick marks
- `--amber` #e8b04a — system accent (tabs, brackets, keycaps, bullets)
- `--text` #dfe5d6 · `--muted` #8d9585 · `--desc` #b7bfae
- Faction A (Sojusz Północny) #5b93d6, badge text #0f1a26
- Faction B (Pakt Wschodni) #d76a52, badge text #2a110b
- Ink on colored fills #0a0c09
- HP good #b9d38a · mid #e2c069 · low #e07c5e · empty rgba(233,231,223,.12)
- Disabled / error #e07c5e · note bg rgba(232,176,74,.1), note text #f0c66e

Type (Google Fonts)
- Display: **Chakra Petch** 600/700, uppercase, letter-spacing .03–.14em
  - Panel title 20–21px/1.1 · faction name 15px/1 ls .06em · button 15px 700 ls .14em · banner 40px 700 ls .1em
- Data: **JetBrains Mono** 400–700
  - Body data 11–11.5px · labels 9.5–10.5px ls .1–.3em uppercase · turn number 32px 700
- Description body: Chakra Petch 400 12px/1.45

Shapes
- Chamfer clip-path (c = 8–16px), e.g. top-right + bottom-left:
  `polygon(0 0, calc(100% - 12px) 0, 100% 12px, 100% 100%, 12px 100%, 0 calc(100% - 12px))`
- **Framed panel = 2 nested elements**: outer `padding:1px; background:var(--line); clip-path:X` → inner `background:var(--panel); clip-path:X`. (CSS borders get cut by clip-path.)
- Header tab: `padding:4px 18px 4px 10px; clip-path: polygon(0 0, calc(100% - 10px) 0, 100% 100%, 0 100%)`, fill = amber or faction color, text #0a0c09 mono 10.5px 600 ls .12em.
- Hatch thin: `repeating-linear-gradient(135deg, C 0 2px, transparent 2px 6px)`; hatch wide (active bars): `… C 0 6px, transparent 6px 9px)`.
- Hex badge: `clip-path: polygon(25% 0,75% 0,100% 50%,75% 100%,25% 100%,0 50%)`, 40×36.
- Corner bracket: 9×9, 2px amber border on two sides, offset −1px.
- Brackets for tags: `[` `]` in amber around mono text.
- No border-radius anywhere (except crosshair circle).

## Components

### 01 Turn bar (top center, top:0)
Trapezoid hanging from top edge: `clip-path: polygon(0 0,100% 0,calc(100% - 26px) 100%,26px 100%)`, framed (outer padding `0 1px 1px`). Inner padding 12px 44px, gap 18px.
- Faction block 236px: hex badge + name + meta (`AKTYWNA|OCZEKUJE · N JEDN.`). Beneath: 4px wide-hatch bar in faction color when active, transparent otherwise. Inactive block opacity .6 (transition .3s).
- Center: `TURA` (9.5px ls .3em muted), number `03` (32px mono 700), `▸ FACTION NAME` in active color 9.5px. 1px line dividers left/right, padding 0 18px.
- Under the bar: 300×10 tick ruler (61 ticks every 5px; heights 8/5/3 for every 10th/5th/other), stroke `--line`.

### 02 Unit card (hover popup, 320px)
Position: cursor x+24 (flip to x−344 if overflows), y clamped to [110, H−620]. `pointer-events:none`. Frame chamfer 16 (tr bl).
1. Tab row: type label tab (faction color) + faction name right (faction color, 10px mono, padding-right 20px).
2. Name 21px Chakra uppercase; designation 11px mono muted. Padding 9/12/8.
3. Portrait 296×160 (margin 0 12px, bg #1b1f1a): scanlines `repeating-linear-gradient(rgba(0,0,0,0) 0 2px, rgba(0,0,0,.12) 2px 3px)`; centered crosshair (46px circle 1px rgba(232,176,74,.55) + 68px cross lines .4); 4 corner brackets; rank chip bottom-left (3 diamond pips 6px rotated 45°, gold #e2c069 / rgba(233,231,223,.18)).
4. HP: label `SIŁA` + `8/10`; segmented bar, one segment per HP, 8px tall, gap 2px, each skewed `clip-path: polygon(3px 0,100% 0,calc(100% - 3px) 100%,0 100%)`.
5. Stats grid 2 cols gap 8×14: label muted / value 600, bar 4px (track rgba(141,149,133,.15), fill --text) with tick overlay `repeating-linear-gradient(90deg, transparent 0 9px, rgba(8,11,8,.95) 9px 10px)`.
6. Tags in brackets (10.5px mono, gap 3×8). Active effects (Okopana, Zamaskowana…) appended as tags.
7. Optional note: border-left 3px amber, bg amber .1.
8. Status footer: border-top 1px line; 8px hex dot (green ready / grey moved / faction color for enemy) + uppercase status.

### 03 Terrain card (bottom-left, 262px)
Stacked column (gap 10) at left:24 bottom:24: operation label (`■ OP. ŻELAZNY BRZEG` amber 10.5px ls .18em + 150×3 thin hatch) then the card. Frame chamfer 12 (tr bl). Tab `TEREN` + `HEKS 07·04` right. Title 20px; city `◆ Name` amber 12px mono. Rows with dotted leaders (`KOSZT RUCHU`, `MOD. OBRONY`, `WYSOKOŚĆ`). Tags in brackets. Path row (only when hovering a reachable hex): 1px border + text in active faction color, `TRASA · 3 / 5 PR`.

### 04 Radial orders menu (right-click on own unit)
Screen-space overlay centered on the unit's projected position, follows camera each frame. 400×400 SVG, origin center.
- Six trapezoid segments forming a pointy-top hex ring, inner vertex radius 84, outer 160, 3px gaps. Points (clockwise from NE):
  - 1 NE `3,-84 3,-160 137.1,-82.6 71.2,-44.6`
  - 2 E `74.2,-39.4 140.1,-77.4 140.1,77.4 74.2,39.4`
  - 3 SE `71.2,44.6 137.1,82.6 3,160 3,84`
  - 4 SW `-3,84 -3,160 -137.1,82.6 -71.2,44.6`
  - 5 W `-74.2,39.4 -140.1,77.4 -140.1,-77.4 -74.2,-39.4`
  - 6 NW `-71.2,-44.6 -137.1,-82.6 -3,-160 -3,-84`
  - Label centers: (52.8,−91.5) (105.7,0) (52.8,91.5) (−52.8,91.5) (−105.7,0) (−52.8,−91.5). Icon 20px above center, 2-line label below (mono 10.5px 600 ls .05em).
- Segment states: normal fill rgba(8,11,8,.88) stroke rgba(232,176,74,.4) ink #dfe5d6 · hover fill+stroke = faction color, ink #0a0c09 · disabled fill rgba(8,11,8,.62) ink rgba(223,229,214,.3), cursor not-allowed · hover-disabled fill rgba(58,26,20,.94) stroke #e07c5e.
- Inner dashed hex (vertex r 75, faction color, dash 6 4). Outer tick ring r 168→172 every 5°, →178 every 30°. Key numbers 1–6 at r 190 (amber mono 10px).
- Drop shadow 0 10px 22px rgba(0,0,0,.5).
- Detail card 272px beside ring (x+206, flips left), shows hovered action: tab `ROZKAZ` (faction color; #e07c5e if disabled) + `[n]`, title, description, `▸` effect list, footer `KOSZT` / cost — or `NIEDOSTĘPNE` / reason in #e07c5e. With no hover: unit summary + "Wybierz rozkaz…".
- Slots: 1 Ruch · 2 Ostrzał na oślep · 3 unit-specific (tank: Zasłona dymna, infantry: Zasadzka, MLRS: Zmiana stanowiska) · 4 Uzupełnienie · 5 Okopanie · 6 Maskowanie. Icons in `icons.svg` (ids move, blind, smoke, ambush, scoot, supply, dig, camo).

### 05 End-turn module (bottom-right, right:24 bottom:24)
- Ready counter (frame chamfer 10 tl): `GOTOWE` + `2 / 3`, one 14×8 block per unit (filled = faction color, empty = 1px inset outline rgba(141,149,133,.45)).
- Button: min-height 52, fill = active faction color, chamfer 14 bottom-right, Chakra 15px 700 ls .14em uppercase `Zakończ turę`, left 10×26 dark hatch, `↵` hint. Hover brightness 1.12, active .9.
- Key hints above (bottom:92): panel rgba(8,11,8,.82) + 1px line border, chamfer 8 tl; keycaps = 1px line border, amber mono 10px.

### 06 Notices
- Targeting bar (top:118 center): 16px amber hatch | amber block `OSTRZAŁ NA OŚLEP` | unit · instruction · keycaps. Border 1px rgba(232,176,74,.6).
- Toast (bottom:130 center, auto-hide 2.8s): chamfer 8 tl/br, `>>` in faction color + mono 11.5px message.
- Turn banner (top 36%, 1.5s): full-width horizontal fade band rgba(8,11,8,.88), wide hatch bars 420px above/below, `TURA 03 // RUCH`, faction name 40px in faction color.
- Loading: centered `OPERACJA` amber / `ŻELAZNY BRZEG` 34px / 220×6 hatch / status mono.

### Screen-level decoration
Vignette `radial-gradient(ellipse 110% 85% at 50% 50%, transparent 62%, rgba(0,0,0,.42))` + scanlines `repeating-linear-gradient(transparent 0 3px, rgba(0,0,0,.05) 3px 4px)` over the map; 22px corner brackets (1.5px line) at 10px inset in all four screen corners. All overlays pointer-events:none.

## Interactions & State
- Hover unit → unit card; hover hex → terrain card (+ path row if reachable).
- RMB click (no drag) on own unit → radial menu; RMB drag = rotate camera. Keys 1–6 trigger slots; Esc / LMB elsewhere closes. Hovered card popup is hidden while menu open.
- Ostrzał na oślep → targeting mode: highlight hexes in range (tank/inf 1–2, MLRS 3–6) in #e2c069 (fill .16, ring .6); LMB fires, RMB/Esc cancels.
- Order effects stored per unit (`camo, dug, smoke, ambush, scoot, suppressed`); movement clears camo/dug/ambush; smoke/scoot/suppressed clear at owner's next turn.
- State: turn, active faction, per-faction units/ready, hovered unit, hovered hex, menu {unit, actions[], hoveredIndex, screenPos}, target mode, toast, banner.

## Files
- `hud-elementy.html` — all components with sample data (self-contained, offline).
- `icons.svg` — order icons (24×24 stroke).
