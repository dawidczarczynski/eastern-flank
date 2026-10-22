<p align="center">
  <img src="assets/branding/logo.png#gh-light-mode-only" alt="Eastern Flank" width="520">
  <img src="assets/branding/logo_light.png#gh-dark-mode-only" alt="Eastern Flank" width="520">
</p>

Turn-based tactical 3D strategy on hexes – Godot 4 (GDScript), developed with the help of AI agents (Claude Code).

![Gameplay: the Polish force with the tank selected – reach and move path on the hex map](docs/images/gameplay.png)

## Getting started

```bash
tools/install_godot.sh            # or your own Godot 4.5+ as `godot` on PATH
pipx install "gdtoolkit==4.*"     # gdformat + gdlint (optional, recommended)
tools/check.sh                    # lint + headless tests
tools/run.sh                      # game   (tools/run.sh --editor – editor)
```

Prototype controls: LMB – select unit / move, Enter – end turn, WASD/arrows – camera, Q/E – rotate, mouse wheel – zoom.

## Documentation

- [docs/GDD.md](docs/GDD.md) – game design
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) – architecture and directory layout
- [docs/AGENTIC_WORKFLOW.md](docs/AGENTIC_WORKFLOW.md) – how we work with agents
- [docs/tasks/BACKLOG.md](docs/tasks/BACKLOG.md) – tasks
- [CLAUDE.md](CLAUDE.md) – instructions for agents

## Credits

Downloaded assets are public domain (CC0) only, from [Poly Haven](https://polyhaven.com) and [ambientCG](https://ambientcg.com). Each file, with its author and source, is listed in [assets/third_party/credits.json](assets/third_party/credits.json) (rules: [ADR 0011](docs/adr/0011-third-party-assets.md)).
