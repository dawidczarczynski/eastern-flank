# TASK-006: Screenshot script for agents

- **Status**: ready
- **Layers**: tools (+ a tiny pure helper tested in `tests/unit/`)
- **Depends on**: nothing. Makes all later visual tasks (TASK-008, -009, -004, -003, -002) verifiable by agents.

## Goal

Agents can "see" the game: one command starts the battle scene in a window, saves a PNG of the viewport and quits, so an agent can read the image after a visual change instead of guessing.

## Acceptance criteria (testable)

- [ ] New script `tools/screenshot.sh [out.png] [--frames=N]`. With no arguments it writes `.screenshots/battle.png` (relative to the project root); a relative `out.png` is resolved against the caller's current directory and passed to Godot as an absolute path.
- [ ] The script runs Godot **windowed** (not `--headless` – the dummy renderer can't draw), with a fixed window size of `--resolution 1280x720`, loads `res://scenes/battle/battle.tscn`, waits `N` rendered frames (default `10`), saves `get_viewport().get_texture().get_image()` as PNG and quits with exit code `0`. Suggested mechanism: a `SceneTree` script `tools/screenshot.gd` run with `--script` that instantiates the battle scene under `root` (no changes to `battle.tscn` or `BattleController` needed).
- [ ] The resulting PNG is exactly 1280×720.
- [ ] Comparable screenshots: two consecutive runs with the same arguments produce images of the scene in the same state – same map (fixed `MAP_SEED`), same units, default camera (CameraRig at map center, default distance and yaw). No input is simulated.
- [ ] Sanity check: if every pixel in a 16×16 sample grid of the image has the same colour (black/blank frame), the script prints `ERROR: blank screenshot` to stderr and exits with code `1`.
- [ ] On success the last line of stdout is `Screenshot saved: <absolute path>`.
- [ ] Fails fast with exit code `2` and a one-line message when neither `DISPLAY` nor `WAYLAND_DISPLAY` is set (no graphical environment).
- [ ] The whole run is wrapped in `timeout 60`; a hang ends with a non-zero exit code instead of blocking the agent.
- [ ] Godot is located the same way as in `tools/run.sh` (`GODOT` variable, fallback `~/.local/bin/godot`) and `--import` is run first. The renderer is left to Godot's default (Vulkan, with Godot's automatic fallback to OpenGL); the `GODOT_RENDERING_DRIVER` variable, if set, is passed as `--rendering-driver`.
- [ ] `.screenshots/` contains a `.gdignore` file (Godot must not import the PNGs, no `*.import` files appear) and is listed in `.gitignore`.
- [ ] Argument parsing lives in a pure helper `tools/screenshot_options.gd` (`extends RefCounted`, `static func parse(args: PackedStringArray) -> Dictionary` returning `{"output": String, "frames": int, "error": String}`), covered by `tests/unit/test_screenshot_options.gd`:
  - `[]` → `frames == 10`, `output == ""` (the shell script fills in the default), `error == ""`.
  - `["/tmp/a.png", "--frames=30"]` → `output == "/tmp/a.png"`, `frames == 30`.
  - `["--frames=0"]` and `["--frames=601"]` and `["--frames=abc"]` → `error == "invalid_frames"` (valid range 1–600).
  - `["--zoom=3"]` → `error == "unknown_option"`.
  - two positional paths → `error == "too_many_arguments"`.
- [ ] `docs/AGENTIC_WORKFLOW.md` ("Next steps") updated to describe the real command; the implementation notes propose to the human a one-line addition to the "Commands" list in `CLAUDE.md` (the agent does not edit `CLAUDE.md` itself).

## Playtest (for the human)

1. In WSL run `tools/screenshot.sh` – a Godot window briefly appears and closes on its own within a few seconds.
2. Open `.screenshots/battle.png` – it shows the hex map with blue units on the left and red units on the right, and the HUD text at the top-left, exactly like the first frame of `tools/run.sh`.
3. Run it again – the second image looks identical.
4. Run `tools/screenshot.sh /tmp/x.png --frames=60` – `/tmp/x.png` exists.

## Out of scope

- Custom camera position/zoom/yaw via arguments (follow-up if agents need close-ups).
- Capturing a scripted game situation (e.g. after N commands) – possible later on top of TASK-005 replays.
- Image diffing / golden-image tests in CI.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
