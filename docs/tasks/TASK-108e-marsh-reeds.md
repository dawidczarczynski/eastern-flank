# TASK-108e: Real-terrain look v2 – reeds on marshes and river banks

- **Status**: ready
- **Layers**: presentation (`GrassPlanner` new kind, `GrassTexture` reed card, `grass.gdshader` colour, `LookPreset` meadow keys) + docs (ARCHITECTURE, MANUAL)
- **Depends on**: TASK-108 (done) (soft: TASK-108c – real river width and banks; TASK-110 – real grass scale; priority: after the operational core loop 092 → 094 → 095)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Marsh hexes (move 2, no cover – the worst ground to fight on) and river banks are recognisable at a glance: dense stands of tall reeds with brown seed heads instead of the meadow grass. Uses the existing lazy grass chunks, so it costs nothing far from the camera and nothing on LOW.

## Design

**Scale (decided 2026-10-31: real size).** Distances here are in metres, converted with `MapScale.metres_per_unit` (TASK-108b "Scale"; introduce it here if 108b has not landed). The **reed height is not** set in metres by this task: reeds are a grass kind, so their size follows the grass clump size, which is not at real scale yet (a clump is ~0.1 units ≈ 14 m on Suwałki). TASK-110 moves grass to real metres; reeds then become **2.0–2.5 m** tall (1.5 × a ~1.5 m tall-grass clump), still the tallest grass kind. Until then: 1.5 × the clump height, as below.

- `GrassPlanner.Kind` gets **`REED`** appended (`SHORT, TALL, DRY_STALK, NETTLE, REED`). The kind is chosen from world-space noise and position hashes like the TASK-070 kinds – **no new RNG draws**, so clump positions do not move (only kinds and densities change where reeds apply).
- **Marsh tiles**: density × **1.3** of the plains density (was × 1); a clump is REED where `GroundNoise.patch_k`-style noise (own offset) exceeds 0.35 → about **60–75 %** of marsh clumps; the rest stays TALL / SHORT as today. The tile-centre short-grass radius (units stay readable) still applies.
- **River banks** (any land terrain except URBAN): a clump whose `FeatureRibbonPlanner.edge_distance(grid, RIVER, x, z)` lies in **(0, 10 m]** (Suwałki: 0.069 units) becomes REED with probability 0.7 (position hash). Clumps closer than the ribbon clearance are already removed (TASK-108).
- **Lake shores** stay as they are (out of scope; the shore band is mud).
- **Look**: height multiplier **1.5** (the existing maximum, `LookPreset` key `reed_height`; `GrassField.max_clump_height()` and so `GroundOverlay.depth_pull()` do not change), card `GrassTexture.reed_card` – 5–7 thin vertical blades with a darker brown seed head on 2–3 of them, procedural like the other cards (no CC0 texture). Colour via `GrassPlanner.kind_color`: blade green-olive `#6f7a45` towards dry `#a39466` by the macro dry noise; seed heads `#5a4433` (in the card, not tinted). Wind: same as tall grass (shared include).
- `LookPreset`: `MEADOW_OFF` has reeds off (`reed_share` 0, `bank_reeds` 0) so the `current` preset reproduces its old output; the active presets enable them.
- **LOW**: no grass, so no reeds (`grass_density` 0). No new quality switch.
- **Budget**: marsh × 1.3 adds few clumps (Suwałki: 9 marsh hexes); `GrassPlanner.INSTANCE_BUDGET` (120 000) unchanged – the existing density cut-back applies. Frame budget (Windows D3D12, HIGH, `SCREENSHOT_MEASURE_FRAMES=240`, median of 3, default camera and a close-up on a marsh with `SCREENSHOT_FOCUS`): **≤ +0.3 ms** on Suwałki; default battle identical (no marsh, no rivers: no reeds).

## Acceptance criteria (testable)

Grass planner tests (`test_grass_planner*.gd`), `test_look_preset.gd`, `test_grass_texture.gd` (or wherever the cards are tested):
- [ ] `GrassPlanner.Kind.REED` exists; `REED`'s height multiplier = 1.5 and `GrassField.max_clump_height()` is the same value as before the task.
- [ ] Marsh-only hand-made chunk (no centre within the chunk, or excluding the centre radius): REED share of clumps 0.55–0.80; clump count 1.2–1.4 × the count of the same chunk planned as plains (same seed).
- [ ] Plains chunk with a river ribbon: every clump with edge distance in (0, 10 m] is REED in 0.6–0.8 of cases; no clump farther than 10 m from the river edge is REED (at 144.34 m / unit; halving `metres_per_unit` doubles the band in world units); on an URBAN tile next to the river no clump is REED.
- [ ] Positions unchanged: for a plains/forest/hills chunk without rivers and for the default battle's chunks, `plan_chunk` returns the same positions and kinds as before the task (compare against a recorded list or a run with reeds disabled via `MEADOW_OFF`).
- [ ] `MEADOW_OFF` (`current` preset) produces no REED anywhere, also on marsh and banks.
- [ ] `GrassTexture.reed_card` is deterministic (same image twice), has alpha 0 and 1 only, covers 8–30 % of its pixels, and covered pixels exist in the top 10 % of rows (the blades reach the top) – a sparse vertical card, not a blob.
- [ ] Frame times before/after recorded in the notes; within budget or explained.
- [ ] Screenshots Read by the agent: a close-up on a Suwałki marsh hex and on the river bank (`SCREENSHOT_FOCUS`), HIGH: reeds read as tall, upright, brown-tipped stands, distinct from meadow grass; `docs/images/gameplay.png` unchanged in content.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle`. Hover hexes until the terrain panel says Marsh (there are about nine). Zoom in: dense tall reeds with brown heads, swaying in the wind; the centre of the hex is kept low so a unit there stays visible.
2. Follow the river: patchy reeds along its banks (not in villages).
3. Units and their rings / outlines are still visible over the reeds.
4. `--quality=low`: no reeds (like no grass). Frame rate on HIGH: no visible drop near marshes.

## Player manual

§10 "Screen" → "Roads and rivers" / terrain look: marshes show tall reeds with brown seed heads, and reeds grow in patches along river banks – they are only decoration (marsh rules: move 2, no defense bonus). Note that grass and reeds are not drawn on LOW graphics, if the manual lists what LOW leaves out.

## Out of scope

- Open water pools inside marshes, lake-shore reed belts, cattail models, seasonal colours.
- Any rule effect of reeds (concealment belongs to fog of war, TASK-007).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
