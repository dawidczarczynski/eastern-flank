# TASK-103a: Operation simulation tool – operational AI-vs-AI matches with a report

- **Status**: done
- **Layers**: ai / tools (+ core only for the provisional score, if it lives in `src/core/operational`)
- **Depends on**: TASK-102c (hard), TASK-120 (hard), TASK-102a (soft: AI goals data), TASK-121 / TASK-122 (soft: outside-support figures)
- **Topic**: Two-layer game
- **Tags**: mvp
- **Sections**: GDD "Operational AI", "Escalation ladder", "Battle hand-off and auto-resolve"; ARCHITECTURE: none (grep docs/CODEMAP.md for `MatchRunner`, `OperationalAiTurn`, `AutoResolve`; docs/TOOLS.md simulate entry)
- **Model**: sonnet

## Goal

`tools/simulate.sh` can play whole operations AI-vs-AI (every contact auto-resolved, or played as headless tactical battles) and report per-side win shares, endings and politics, so the operation can be balanced (TASK-103b). First part of TASK-103 (split 2026-11-11).

## Decisions (human interview, 2026-11-11)

- A "decided operation" ends by a rule that exists today (collapse, nuclear use, escalation threshold) or, at the turn cap, by a PROVISIONAL winner by objectives held; the provisional score is replaced by TASK-107's real victory through the same report API.
- Tool: `tools/simulate.sh N --mode=operation [--seed=S] [--max-rounds=R] [--scenario=<operation id>] [--battles=auto|played] [--out=file.csv] [--verbose]`; the default mode stays the existing tactical one, unchanged.
- Battles are auto-resolved by default (speed); `--battles=played` plays each contact as a headless tactical AI-vs-AI battle and compares it with the auto result (calibration, gaps like TASK-128's).
- **[ASSUMPTION]** the turn cap is a data value on the operation (default 30 rounds), overridden by `--max-rounds`; the default operation is `suwalki_gap`.
- **[ASSUMPTION]** how an operation ends today (collapse / threshold / nuclear) is read from the existing code (grep `collapse_rules.gd`, `nuclear_strike_command.gd`, `operation_over`); this task adds no new ending.

## Acceptance criteria (testable)

- [ ] `ProvisionalScore` (pure, `src/ai/` or `src/core/operational/`) sums, per side, the weights of the AI goals (TASK-102a: hexes / installations, role take or hold) currently held by that side; held = a friendly formation on the hex / the installation is friendly-controlled.
- [ ] Hand-made state: side 0 holds goals of weight 3 + 2, side 1 holds weight 4 → totals 5 vs 4; with a data threshold 2 the difference 1 is a draw, with threshold 0 side 0 wins; equal totals are a draw.
- [ ] `ProvisionalScore` returns the same result shape (winner `-1` / `0` / `1`, reason `&"provisional"`) that TASK-107 will feed, so 107 can swap it; the turn-cap value and the draw threshold are data (not literals in code).
- [ ] An operation match runner (in `MatchRunner` or a sibling in `src/ai/`) plays both sides with `OperationalAiTurn.play` until an ending rule fires or the round cap is reached; no `Node`, `await` or autoload in `src/core` / `src/ai`.
- [ ] Every contact battle is auto-resolved (`resolution` `&"auto"`) by default; each match result lists winner (0 / 1 / -1), ending (`collapse` / `threshold` / `nuclear` / `turn_cap`), rounds, max escalation level, battle counts per resolution.
- [ ] `--battles=played`: each contact is played as a headless tactical AI-vs-AI battle (`resolution` `&"played"`) and the report adds, per contact, played winner vs. auto-resolve winner for the same setup and the agreement share (agreed / compared, e.g. 7 / 10 = 70 %).
- [ ] Determinism: `tools/simulate.sh 3 --mode=operation --seed=5` twice gives identical report text; matches with seeds 5 and 6 differ in at least one per-match field over a 10-match run.
- [ ] Report per run: NATO and Russia win shares of decided operations, undecided share, draws, average length in rounds, endings by type (collapse / threshold / nuclear / turn cap provisional) – shares sum to 100 % (±0.1).
- [ ] Report politics and strikes: average max escalation level, decisions that caused escalation per side, strikes fired / intercepted / installations destroyed, battles fought split by resolution; outside support requested per side only when TASK-121 exists (otherwise the line is omitted, no error).
- [ ] `--out=file.csv` writes one row per match with header exactly `seed,winner,ending,rounds,max_level,battles`; N rows + 1 header.
- [ ] Options parser: `--mode=operation|tactical` (default `tactical`), `--max-rounds=R` (int ≥ 1), `--battles=auto|played`, `--out=<path>`; an unknown value or `--max-rounds=0` / `abc` → exit 2 with the usage text, like the existing parser; a runtime error (missing operation id, unwritable `--out`) → exit 1.
- [ ] The options that belong to the other mode (`--max-turns`, `--factions` with `--mode=operation`; `--max-rounds`, `--battles` with `--mode=tactical`) are rejected with exit 2.
- [ ] Smoke test: a 3-match run on `suwalki_gap` with `--max-rounds=5` finishes within 60 s and prints the report without an error.
- [ ] Regression: `tools/simulate.sh 3 --seed=1` (no `--mode`) prints the same output as before this task (existing tactical tests unchanged and passing).
- [ ] A match whose operation is already over after planning yields no further commands and ends with the correct ending type; a hand-made state at the round cap with no ending uses `ProvisionalScore` and reports `turn_cap`.
- [ ] docs/TOOLS.md simulate entry lists the new options, the report lines and the CSV header.

## Playtest (for the human)

None – everything can be checked from the tool output (`tools/simulate.sh 20 --mode=operation --seed=1`). `--battles=played` is slow; run it with a small N (e.g. 3).

## Player manual

none

## Out of scope

- Balancing data (TASK-103b); the real operation victory (TASK-107); fog (TASK-100); any UI.
- New endings or rule changes; human-vs-AI feel.

## Implementation notes

Done 2026-11-12. `tools/simulate.sh N --mode=operation` plays whole operations AI-vs-AI and prints the report / CSV (docs/TOOLS.md).

- New: `ProvisionalScore` (src/core/operational/, goal weights held per side, draw threshold), `OperationMatchRunner` (src/ai/, sibling of `MatchRunner`); `turn_cap` (30) and `provisional_draw_threshold` (0) are data on `OperationDefinition` / `OperationalState`. Options in `tools/simulate_options.gd`, branch in `tools/simulate.gd`; tactical mode output unchanged.
- Endings: the only rule that ends an operation today is nuclear use (`nuclear_use`, winner -1); `collapse` / `threshold` endings read 0 % until a rule produces them (TASK-140 removed the threshold ending). An unknown result reason is reported as `error` (push_error) rather than a turn cap. At the cap the winner is provisional, so NATO / Russia wins are mostly provisional – the report splits "by a rule" from "provisional".
- `--battles=played` prints one `contact: played winner X, auto winner Y` line per contact and the agreement share (sample: 6 / 9 on seed 1, 6 rounds). A contact that cannot be prepared falls back to auto-resolve and is not compared.
- Outside support line omitted (TASK-121 not done).
- Limits: a 5-round match takes ~5–8 s, so N=20 at the default 30-round cap takes minutes. No end-to-end test of `simulate.sh` itself (smoke run done by hand); runner tests cover the logic.
