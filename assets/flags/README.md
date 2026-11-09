# Flags

- `nato.svg` – NATO flag, public domain, from Wikimedia Commons (https://commons.wikimedia.org/wiki/File:NATO_flag.svg, https://pl.wikipedia.org/wiki/Plik:NATO_flag.svg).
- `russia.svg` – own simple tricolour drawing.

The NATO file's width / height were reduced to 192 x 144 (viewBox unchanged) so Godot rasterises it near the display size; at its native 1024 x 768 the thin lines alias when scaled down.

The viewBox is also cropped to the central 560 x 420 part (the compass star) on purpose: the full flag is unreadable at flag size in the UI.
The four long tick lines at the edges (the first four sub-paths) were removed, the compass star is untouched.
