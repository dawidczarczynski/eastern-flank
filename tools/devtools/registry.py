"""What the devtools hub offers: the web tools it supervises and the command-line tools it can run.

Every command is a fixed template: the browser picks the command and fills its declared parameters,
each checked against a type, a pattern or a list of choices – never any other part of the command line.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
PYTHON = "python3"


class ParamError(ValueError):
    pass


# ---- web tools (long-running servers, started as child processes unless already running)

SERVICES: List[Dict[str, Any]] = [
    {
        "id": "backlog",
        "label": "Backlog",
        "description": "docs/tasks/BACKLOG.md – sort, filter, task files, live updates",
        "port": 8766,
        "probe": "/api/version",
        "argv": [PYTHON, "tools/backlog_view/server.py", "--port=8766"],
    },
    {
        "id": "unit_catalog",
        "label": "Unit catalog",
        "description": "Real-unit references, research and model jobs (docs/design/units/)",
        "port": 8765,
        "probe": "/api/catalog",
        "argv": [PYTHON, "tools/unit_catalog/server.py", "--port=8765"],
    },
]


# ---- choices read from the repository

def factions(root: Path = REPO_ROOT) -> List[str]:
    return sorted(p.stem for p in (root / "data" / "factions").glob("*.tres"))


def scenarios(root: Path = REPO_ROOT) -> List[str]:
    return ["default_battle"] + sorted(p.stem for p in (root / "data" / "scenarios").glob("*.tres"))


def units(root: Path = REPO_ROOT) -> List[str]:
    return sorted(p.name for p in (root / "docs" / "design" / "units" / "units").iterdir() if p.is_dir())


# ---- command-line tools

def _param(name: str, kind: str, label: str, default: Any = "", **extra: Any) -> Dict[str, Any]:
    return dict({"name": name, "type": kind, "label": label, "default": default}, **extra)


TEST_FILTER = r"[A-Za-z0-9_]*"
SHOTS = r"([a-z_]+(:\d+)?(,[a-z_]+(:\d+)?)*)?"


def _test(p: Dict[str, Any]) -> List[str]:
    return ["tools/test.sh"] + (["--verbose"] if p["verbose"] else []) + ([p["filter"]] if p["filter"] else [])


def _simulate(p: Dict[str, Any]) -> List[str]:
    argv = ["tools/simulate.sh", str(p["count"]), "--factions=%s,%s" % (p["player0"], p["player1"]), "--scenario=" + p["scenario"]]
    if p["seed"] != "":
        argv.append("--seed=%d" % p["seed"])
    if p["max_turns"] != "":
        argv.append("--max-turns=%d" % p["max_turns"])
    return argv


def _render_unit(p: Dict[str, Any]) -> List[str]:
    return ["tools/render_unit.sh", p["unit"]] + (["--faction=" + p["faction"]] if p["faction"] else [])


def _game(editor: bool) -> Callable[[Dict[str, Any]], List[str]]:
    def build(p: Dict[str, Any]) -> List[str]:
        script = "tools/run_windows.sh" if p.get("build", "windows") == "windows" else "tools/run.sh"
        if editor:
            return [script, "--editor"]
        argv = [script, "--scenario=" + p["scenario"]]
        if p["quality"] != "auto":
            argv.append("--quality=" + p["quality"])
        return argv
    return build


BUILD = _param("build", "choice", "Godot", "windows", choices=lambda: ["windows", "linux"])

COMMANDS: List[Dict[str, Any]] = [
    {
        "id": "check", "group": "Verify", "label": "Check", "description": "tools/check.sh – lint + all tests + backlog statuses",
        "params": [], "argv": lambda p: ["tools/check.sh"],
    },
    {
        "id": "test", "group": "Verify", "label": "Tests", "description": "tools/test.sh – headless tests, optional file filter",
        "params": [_param("filter", "text", "filter", "", pattern=TEST_FILTER, placeholder="test_commands"),
                   _param("verbose", "bool", "verbose", False)],
        "argv": _test,
    },
    {
        "id": "lint_fix", "group": "Verify", "label": "Lint --fix", "description": "tools/lint.sh --fix – gdformat + gdlint",
        "params": [], "argv": lambda p: ["tools/lint.sh", "--fix"],
    },
    {
        "id": "backlog_fix", "group": "Verify", "label": "Backlog --fix", "description": "tools/backlog.py --fix – status icons, blocked ↔ ready",
        "params": [], "argv": lambda p: [PYTHON, "tools/backlog.py", "--fix"], "exclusive": False,
    },
    {
        "id": "simulate", "group": "Balance", "label": "Simulate", "description": "tools/simulate.sh – headless AI-vs-AI matches",
        "params": [_param("count", "int", "matches", 20, min=1, max=1000),
                   _param("player0", "choice", "player 0", "poland", choices=factions),
                   _param("player1", "choice", "player 1", "russia", choices=factions),
                   _param("scenario", "choice", "scenario", "default_battle", choices=scenarios),
                   _param("seed", "int", "seed", "", min=0, max=2**31 - 1, optional=True),
                   _param("max_turns", "int", "max turns", "", min=1, max=1000, optional=True)],
        "argv": _simulate,
    },
    {
        "id": "screenshot", "group": "Visual", "label": "Battle screenshot",
        "description": "tools/screenshot.sh – battle scene to .screenshots/battle.png, optional HUD states",
        "params": [_param("shots", "text", "HUD states", "", pattern=SHOTS, placeholder="hover:2,select:2,toast")],
        "argv": lambda p: ["tools/screenshot.sh", ".screenshots/battle.png"],
        "env": lambda p: {"SCREENSHOT_SHOTS": p["shots"]} if p["shots"] else {},
        "images": lambda p: [".screenshots/battle.png"] if not p["shots"] else [".screenshots/battle_%s.png" % s.split(":")[0] for s in p["shots"].split(",")],
    },
    {
        "id": "readme_screenshot", "group": "Visual", "label": "README screenshot",
        "description": "tools/readme_screenshot.sh – re-render docs/images/gameplay.png",
        "params": [], "argv": lambda p: ["tools/readme_screenshot.sh"], "images": lambda p: ["docs/images/gameplay.png"],
    },
    {
        "id": "render_unit", "group": "Visual", "label": "Render unit",
        "description": "tools/render_unit.sh – one unit model on a 1 m grid (side / front / top / three-quarter)",
        "params": [_param("unit", "choice", "unit", "", choices=units),
                   _param("faction", "choice", "faction", "", choices=lambda: [""] + factions())],
        "argv": _render_unit,
        "images": lambda p: [".screenshots/units/%s_*_sheet.png" % p["unit"]],
    },
    {
        "id": "play", "group": "Game", "label": "Play", "description": "tools/run_windows.sh / tools/run.sh – start the game window",
        "exclusive": False,
        "params": [BUILD,
                   _param("scenario", "choice", "scenario", "default_battle", choices=scenarios),
                   _param("quality", "choice", "quality", "auto", choices=lambda: ["auto", "high", "low"])],
        "argv": _game(editor=False),
    },
    {
        "id": "editor", "group": "Game", "label": "Editor", "description": "Open the Godot editor",
        "params": [BUILD], "argv": _game(editor=True), "exclusive": False,
    },
]


def find(command_id: str) -> Optional[Dict[str, Any]]:
    return next((c for c in COMMANDS if c["id"] == command_id), None)


def _choices(param: Dict[str, Any]) -> List[str]:
    return list(param["choices"]())


def validate(command: Dict[str, Any], given: Dict[str, Any]) -> Dict[str, Any]:
    """The command's parameters from the request, typed and checked; raises ParamError."""
    if not isinstance(given, dict):
        raise ParamError("params must be an object")
    unknown = set(given) - {p["name"] for p in command["params"]}
    if unknown:
        raise ParamError("unknown parameters: " + ", ".join(sorted(unknown)))
    values: Dict[str, Any] = {}
    for param in command["params"]:
        name, value = param["name"], given.get(param["name"], param["default"])
        kind = param["type"]
        if kind == "bool":
            if not isinstance(value, bool):
                raise ParamError("%s: expected true / false" % name)
        elif kind == "int":
            if value in ("", None) and param.get("optional"):
                value = ""
            else:
                if isinstance(value, str) and re.fullmatch(r"\d+", value.strip()):
                    value = int(value)
                if not isinstance(value, int) or isinstance(value, bool) or not param["min"] <= value <= param["max"]:
                    raise ParamError("%s: expected a whole number %d–%d" % (name, param["min"], param["max"]))
        elif kind == "choice":
            if value not in _choices(param):
                raise ParamError("%s: unknown value %r" % (name, value))
        elif kind == "text":
            if not isinstance(value, str) or not re.fullmatch(param["pattern"], value):
                raise ParamError("%s: invalid value %r" % (name, value))
        values[name] = value
    return values


def describe() -> List[Dict[str, Any]]:
    """Commands for the page (choices resolved, no callables)."""
    out = []
    for command in COMMANDS:
        params = []
        for param in command["params"]:
            item = {k: v for k, v in param.items() if k != "choices"}
            if "choices" in param:
                item["choices"] = _choices(param)
            params.append(item)
        item = {k: command[k] for k in ("id", "group", "label", "description")}
        item.update(params=params, exclusive=command.get("exclusive", True))
        out.append(item)
    return out
