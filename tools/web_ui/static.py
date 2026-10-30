"""Shared static files of the local dev web tools: the theme stylesheet and the repository's fonts."""
from __future__ import annotations

import re
from pathlib import Path
from typing import Optional

HERE = Path(__file__).resolve().parent
THEME = HERE / "theme.css"
FONTS_ROOT = HERE.parent.parent / "assets" / "fonts"
FONT_NAME = re.compile(r"^[A-Za-z0-9_-]+\.ttf$")


def font(name: str) -> Optional[Path]:
    """assets/fonts/<family>/<name>, or None for anything that is not a font file there."""
    if not FONT_NAME.match(name):
        return None
    return next((p for p in sorted(FONTS_ROOT.glob("*/" + name)) if p.is_file()), None)
