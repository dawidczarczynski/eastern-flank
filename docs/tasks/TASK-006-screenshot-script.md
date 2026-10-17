# TASK-006: Screenshot script for agents

- **Status**: done
- **Layers**: tools (+ a tiny pure helper tested in `tests/unit/`)
- **Depends on**: nothing. Makes all later visual tasks (TASK-008, -009, -004, -003, -002) verifiable by agents.

## Goal

Agents can "see" the game: one command starts the battle scene in a window, saves a PNG of the viewport and quits, so an agent can read the image after a visual change instead of guessing.

## Acceptance criteria (testable)

- [x] New script `tools/screenshot.sh [out.png] [--frames=N]`. With no arguments it writes `.screenshots/battle.png` (relative to the project root); a relative `out.png` is resolved against the caller's current directory and passed to Godot as an absolute path.
- [x] The script runs Godot **windowed** (not `--headless` – the dummy renderer can't draw), with a fixed window size of `--resolution 1280x720`, loads `res://scenes/battle/battle.tscn`, waits `N` rendered frames (default `10`), saves `get_viewport().get_texture().get_image()` as PNG and quits with exit code `0`. Suggested mechanism: a `SceneTree` script `tools/screenshot.gd` run with `--script` that instantiates the battle scene under `root` (no changes to `battle.tscn` or `BattleController` needed).
- [x] The resulting PNG is exactly 1280×720.
- [x] Comparable screenshots: two consecutive runs with the same arguments produce images of the scene in the same state – same map (fixed `MAP_SEED`), same units, default camera (CameraRig at map center, default distance and yaw). No input is simulated.
- [x] Sanity check: if every pixel in a 16×16 sample grid of the image has the same colour (black/blank frame), the script prints `ERROR: blank screenshot` to stderr and exits with code `1`.
- [x] On success the last line of stdout is `Screenshot saved: <absolute path>`.
- [x] Fails fast with exit code `2` and a one-line message when neither `DISPLAY` nor `WAYLAND_DISPLAY` is set (no graphical environment).
- [x] The whole run is wrapped in `timeout 60`; a hang ends with a non-zero exit code instead of blocking the agent.
- [x] Godot is located the same way as in `tools/run.sh` (`GODOT` variable, fallback `~/.local/bin/godot`) and `--import` is run first. The renderer is left to Godot's default (Vulkan, with Godot's automatic fallback to OpenGL); the `GODOT_RENDERING_DRIVER` variable, if set, is passed as `--rendering-driver`.
- [x] `.screenshots/` contains a `.gdignore` file (Godot must not import the PNGs, no `*.import` files appear) and is listed in `.gitignore`.
- [x] Argument parsing lives in a pure helper `tools/screenshot_options.gd` (`extends RefCounted`, `static func parse(args: PackedStringArray) -> Dictionary` returning `{"output": String, "frames": int, "error": String}`), covered by `tests/unit/test_screenshot_options.gd`:
  - `[]` → `frames == 10`, `output == ""` (the shell script fills in the default), `error == ""`.
  - `["/tmp/a.png", "--frames=30"]` → `output == "/tmp/a.png"`, `frames == 30`.
  - `["--frames=0"]` and `["--frames=601"]` and `["--frames=abc"]` → `error == "invalid_frames"` (valid range 1–600).
  - `["--zoom=3"]` → `error == "unknown_option"`.
  - two positional paths → `error == "too_many_arguments"`.
- [x] `docs/AGENTIC_WORKFLOW.md` ("Next steps") updated to describe the real command; the implementation notes propose to the human a one-line addition to the "Commands" list in `CLAUDE.md` (the agent does not edit `CLAUDE.md` itself).

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

- `tools/screenshot.sh` checks for `DISPLAY`/`WAYLAND_DISPLAY` (exit 2), finds Godot like `tools/run.sh`, makes positional paths absolute against the caller's cwd (default `<project>/.screenshots/battle.png`), creates `.screenshots/.gdignore`, runs `--import`, then `timeout 60 godot --path . --resolution 1280x720 [--rendering-driver $GODOT_RENDERING_DRIVER] --script res://tools/screenshot.gd -- <args>`. Options are passed through untouched; validation is in GDScript.
- `tools/screenshot.gd` (SceneTree script): parses args, instantiates `battle.tscn` under `root`, counts N `_process` frames, then `await RenderingServer.frame_post_draw` and reads `root.get_texture().get_image()`. Checks size == 1280×720 and the blank grid, saves the PNG and prints `Screenshot saved: <path>`. Exit codes: 0 ok, 1 blank / wrong size / unreadable texture / save error, 2 invalid arguments. Godot's own log lines are printed to stdout before the result, so the result is always the last stdout line.
- Input is disabled on the root viewport (`set_disable_input(true)`, `gui_disable_input`), and after `_ready` the battle scene's `process_mode` is set to `DISABLED`, so neither input events nor polled input (`Input.is_physical_key_pressed` in `CameraRig`, `get_mouse_position()` in `BattleController._process`) can change the scene. No changes to `battle.tscn` or `BattleController`.
- Pure helpers, preloaded (no `class_name`, to keep tooling out of the global class list): `tools/screenshot_options.gd` (`parse()`, tested in `tests/unit/test_screenshot_options.gd`) and `tools/screenshot_image.gd` (`is_blank()` over a 16×16 sample grid, tested in `tests/unit/test_screenshot_image.gd`). Putting the blank check in a helper means it is tested without debug options.
- `tools/lint.sh` now also covers `tools/`. `.screenshots/` is in `.gitignore`.
- Verified on WSL2/WSLg (Vulkan fails there, so Godot falls back to OpenGL 3 / llvmpipe): about 13 s per run, PNG 1280×720, two runs and `--frames=60` all give byte-identical files; `GODOT_RENDERING_DRIVER=opengl3` works; with no display it exits 2; invalid arguments exit 2; an empty scene gives `ERROR: blank screenshot` and exit 1.
- After review: the scene's processing is disabled (fixes polled keyboard/mouse input leaking into the image); one 60 s budget for import + capture; script errors in the log fail the run with exit 1; a scene that fails to load reports that instead of "blank screenshot"; the output path is normalised; exit code 127 (Godot not found) documented.
- **Proposed addition to the "Commands" list in `CLAUDE.md`** (for the human to add):
  `- `tools/screenshot.sh [out.png] [--frames=N]` – render the battle scene to a 1280×720 PNG (default `.screenshots/battle.png`) and read it with the Read tool to check visual changes (needs WSLg/a display)`
