"""Pure logic of the unit catalog tool: ids, safe paths, validation, readiness, stable saving, images.

Python 3.8, stdlib only. No HTTP in here - server.py is a thin layer on top.
The data root defaults to docs/design/units and is always passed in explicitly (tests use a temp dir).
"""
from __future__ import annotations

import base64
import binascii
import json
import os
import re
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_ROOT = REPO_ROOT / "docs" / "design" / "units"
DEFAULT_SCREENSHOTS = REPO_ROOT / ".screenshots" / "units"

_WRITE_LOCK = threading.RLock()  # serialises every write operation (server is multi-threaded)

ID_RE = re.compile(r"[a-z0-9_]{2,48}")
HEX_RE = re.compile(r"#[0-9a-fA-F]{6}")
ISO_RE = re.compile(r"[A-Z]{2,3}")
IMAGE_FILE_RE = re.compile(r"([a-z_]+)_([0-9]+)\.(jpg|png|webp)")
MAX_IMAGE_BYTES = 15 * 1024 * 1024

MOBILITIES = ("tracked", "wheeled", "foot")
VIEWS = ("side", "front", "rear", "top", "three_quarter", "detail", "drawing")
STATUSES = ("draft", "ready_for_model", "modeled", "in_game")

UNIT_KEY_ORDER = [
    "id", "real_name", "variant_note", "class", "mobility", "operators", "in_service",
    "country_of_origin", "crew", "weight_t", "armament", "protection", "speed_road_kmh",
    "speed_offroad_kmh", "range_km", "fire_range_km", "notes", "dimensions",
    "silhouette_features", "details", "skip", "camo_note", "images", "image_candidates", "provenance", "status",
    "feedback", "updated", "revision",
]  # fmt: skip
ARMAMENT_KEYS = ["main", "secondary"]
DIMENSION_KEYS = ["hull_length", "overall_length", "width", "height", "sources"]
IMAGE_KEYS = ["file", "view", "source_url", "license", "note"]
CLASS_KEYS = ["id", "label", "mobility", "required_views"]
FACTION_KEY_ORDER = ["id", "name", "iso_code", "color", "camo", "vest_color", "notes"]

NUMERIC_FIELDS = ["weight_t", "speed_road_kmh", "speed_offroad_kmh", "range_km", "fire_range_km"]
STRING_FIELDS = [
    "real_name", "variant_note", "in_service", "country_of_origin", "protection", "notes",
    "camo_note", "feedback", "updated",
]  # fmt: skip
STRING_LIST_FIELDS = ["silhouette_features", "details", "skip"]

# Fields an AI research run may fill in (dotted paths into unit.json). `class`, `mobility`, images and status
# stay with the human. Each filled field gets a `provenance` entry until the human verifies it.
RESEARCH_FIELDS = [
    "variant_note", "in_service", "country_of_origin", "operators", "crew", "weight_t", "armament.main",
    "armament.secondary", "protection", "speed_road_kmh", "speed_offroad_kmh", "range_km", "fire_range_km", "notes",
    "dimensions.hull_length", "dimensions.overall_length", "dimensions.width", "dimensions.height",
    "silhouette_features", "details", "skip", "camo_note",
]  # fmt: skip
# Unverified AI values in these fields block `ready_for_model` - the model is built from them.
MODEL_CRITICAL_FIELDS = ["dimensions.hull_length", "dimensions.width", "dimensions.height", "silhouette_features"]
PROVENANCE_KEYS = ["source", "verified", "suggested"]
CANDIDATE_KEYS = ["url", "view", "license", "source_page", "note"]
RESEARCH_FILE = "research.json"


class CatalogError(Exception):
    """Raised for invalid input. `errors` is a list of {"field", "message"}; `status` an HTTP-like code."""

    def __init__(self, errors: List[Dict[str, Any]], status: int = 400) -> None:
        super().__init__("; ".join("%s: %s" % (e["field"], e["message"]) for e in errors))
        self.errors = errors
        self.status = status


def _err(field: str, message: str, status: int = 400, **extra: Any) -> CatalogError:
    item: Dict[str, Any] = {"field": field, "message": message}
    item.update(extra)
    return CatalogError([item], status)


# --------------------------------------------------------------------------- ids and paths


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", str(text).lower()).strip("_")
    return slug[:48].strip("_")


def is_valid_id(value: Any) -> bool:
    return isinstance(value, str) and ID_RE.fullmatch(value) is not None


def check_id(value: Any, field: str = "id") -> str:
    if not is_valid_id(value):
        raise _err(field, "must match [a-z0-9_]{2,48}")
    return value  # type: ignore[no-any-return]


def check_image_file_name(name: Any) -> str:
    """An image file name is `<view>_<n>.<jpg|png|webp>` - no separators, no dots tricks."""
    if not isinstance(name, str) or "/" in name or "\\" in name or ".." in name or os.path.isabs(name):
        raise _err("file", "invalid image file name")
    m = IMAGE_FILE_RE.fullmatch(name)
    if m is None or m.group(1) not in VIEWS:
        raise _err("file", "invalid image file name")
    return name


def unit_dir(root: Path, unit_id: str) -> Path:
    return Path(root) / "units" / check_id(unit_id)


def faction_path(root: Path, faction_id: str) -> Path:
    return Path(root) / "factions" / (check_id(faction_id) + ".json")


def resolve_inside(base: Path, rel: str) -> Optional[Path]:
    """Resolve `rel` under `base` for read-only serving. Returns None for anything suspicious."""
    if not rel or "\\" in rel or "\x00" in rel or rel.startswith("/") or os.path.isabs(rel):
        return None
    if ".." in rel.split("/"):
        return None
    base_real = Path(os.path.realpath(str(base)))
    target = Path(os.path.realpath(str(base_real / rel)))
    try:
        target.relative_to(base_real)
    except ValueError:
        return None
    return target


# --------------------------------------------------------------------------- stable JSON


def _empty(value: Any) -> bool:
    return value is None or value == "" or value == [] or value == {}


def _ordered(data: Dict[str, Any], order: List[str]) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    for key in order:
        if key in data:
            out[key] = data[key]
    for key in sorted(k for k in data if k not in order):
        out[key] = data[key]
    return out


def _prune(value: Any) -> Any:
    if isinstance(value, dict):
        pruned = {k: _prune(v) for k, v in value.items()}
        return {k: v for k, v in pruned.items() if not _empty(v)}
    if isinstance(value, list):
        return [_prune(v) for v in value]
    return value


def normalize_unit(unit: Dict[str, Any]) -> Dict[str, Any]:
    """Drop empty values and put keys in schema order (recursively). Used before every save."""
    u = _prune(unit)
    if "armament" in u:
        u["armament"] = _ordered(u["armament"], ARMAMENT_KEYS)
    if "dimensions" in u:
        u["dimensions"] = _ordered(u["dimensions"], DIMENSION_KEYS)
    if "images" in u:
        u["images"] = [_ordered(img, IMAGE_KEYS) for img in u["images"]]
    if "image_candidates" in u:
        u["image_candidates"] = [_ordered(c, CANDIDATE_KEYS) for c in u["image_candidates"]]
    if "provenance" in u:
        u["provenance"] = _ordered({k: _ordered(v, PROVENANCE_KEYS) for k, v in u["provenance"].items()}, RESEARCH_FIELDS)
    return _ordered(u, UNIT_KEY_ORDER)


def dumps(data: Any) -> str:
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def atomic_write(path: Path, content: bytes) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp_", suffix=path.suffix)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
        os.chmod(tmp, 0o644)
        os.replace(tmp, str(path))
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def _write_json(path: Path, data: Any) -> None:
    atomic_write(path, dumps(data).encode("utf-8"))


def _read_json(path: Path, default: Any) -> Any:
    try:
        with open(str(path), "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return default


# --------------------------------------------------------------------------- classes and factions


def validate_classes(classes: Any) -> List[Dict[str, Any]]:
    errors: List[Dict[str, Any]] = []
    if not isinstance(classes, list) or not classes:
        raise _err("classes", "must be a non-empty list")
    seen = set()
    out = []
    for i, c in enumerate(classes):
        f = "classes[%d]" % i
        if not isinstance(c, dict):
            errors.append({"field": f, "message": "must be an object"})
            continue
        if not is_valid_id(c.get("id")):
            errors.append({"field": f + ".id", "message": "invalid id"})
        elif c["id"] in seen:
            errors.append({"field": f + ".id", "message": "duplicate id"})
        else:
            seen.add(c["id"])
        if not isinstance(c.get("label"), str) or not c["label"].strip():
            errors.append({"field": f + ".label", "message": "required"})
        if c.get("mobility") not in MOBILITIES:
            errors.append({"field": f + ".mobility", "message": "must be one of %s" % ", ".join(MOBILITIES)})
        views = c.get("required_views", [])
        if not isinstance(views, list) or any(v not in VIEWS for v in views):
            errors.append({"field": f + ".required_views", "message": "unknown view"})
        out.append(_ordered({k: c.get(k) for k in CLASS_KEYS if k in c}, CLASS_KEYS))
    if errors:
        raise CatalogError(errors)
    return out


def load_classes(root: Path) -> List[Dict[str, Any]]:
    return _read_json(Path(root) / "classes.json", [])  # type: ignore[no-any-return]


def save_classes(root: Path, classes: Any) -> List[Dict[str, Any]]:
    clean = validate_classes(classes)
    with _WRITE_LOCK:
        keep = {c["id"] for c in clean}
        used: Dict[str, List[str]] = {}
        for uid in list_unit_ids(root):
            cls = _read_json(unit_dir(root, uid) / "unit.json", {}).get("class")
            if cls not in keep:
                used.setdefault(str(cls), []).append(uid)
        if used:
            errors = [{"field": "classes", "message": "class %r is still used by: %s" % (c, ", ".join(ids))}
                      for c, ids in sorted(used.items())]  # fmt: skip
            raise CatalogError(errors, 409)
        _write_json(Path(root) / "classes.json", clean)
    return clean


def validate_faction(faction: Any, faction_id: Optional[str] = None) -> Dict[str, Any]:
    if not isinstance(faction, dict):
        raise _err("faction", "must be an object")
    errors: List[Dict[str, Any]] = []
    fid = faction.get("id", faction_id)
    if not is_valid_id(fid):
        errors.append({"field": "id", "message": "invalid id"})
    elif faction_id is not None and fid != faction_id:
        errors.append({"field": "id", "message": "does not match the URL"})
    if not isinstance(faction.get("name"), str) or not faction["name"].strip():
        errors.append({"field": "name", "message": "required"})
    iso = faction.get("iso_code", "")
    if not isinstance(iso, str) or not ISO_RE.fullmatch(iso):
        errors.append({"field": "iso_code", "message": "must be 2-3 capital letters"})
    for key in ("color", "vest_color"):
        if not isinstance(faction.get(key), str) or not HEX_RE.fullmatch(faction[key]):
            errors.append({"field": key, "message": "must be a #rrggbb colour"})
    camo = faction.get("camo")
    if not isinstance(camo, list) or len(camo) != 3 or any(not isinstance(c, str) or not HEX_RE.fullmatch(c) for c in camo):
        errors.append({"field": "camo", "message": "must be three #rrggbb colours"})
    if "notes" in faction and not isinstance(faction["notes"], str):
        errors.append({"field": "notes", "message": "must be a string"})
    if errors:
        raise CatalogError(errors)
    clean = {k: faction[k] for k in FACTION_KEY_ORDER if k in faction}
    clean["id"] = fid
    clean["camo"] = [c.lower() for c in camo]
    clean["color"] = clean["color"].lower()
    clean["vest_color"] = clean["vest_color"].lower()
    clean.setdefault("notes", "")
    return _ordered(clean, FACTION_KEY_ORDER)


def load_factions(root: Path) -> List[Dict[str, Any]]:
    out = []
    fdir = Path(root) / "factions"
    if fdir.is_dir():
        for p in sorted(fdir.glob("*.json")):
            data = _read_json(p, None)
            if isinstance(data, dict):
                out.append(data)
    return out


def create_faction(root: Path, faction: Any) -> Dict[str, Any]:
    """Create a new faction (id taken from the body); 409 if it already exists."""
    fid = faction.get("id") if isinstance(faction, dict) else None
    check_id(fid)
    clean = validate_faction(faction, fid)
    with _WRITE_LOCK:
        if faction_path(root, fid).exists():
            raise _err("id", "faction %r already exists" % fid, 409)
        _write_json(faction_path(root, fid), clean)
    return clean


def save_faction(root: Path, faction_id: str, faction: Any) -> Dict[str, Any]:
    """Edit an existing faction; 404 if it does not exist (use create_faction for new ones)."""
    check_id(faction_id)
    clean = validate_faction(faction, faction_id)
    with _WRITE_LOCK:
        if not faction_path(root, faction_id).exists():
            raise _err("id", "faction %r not found" % faction_id, 404)
        _write_json(faction_path(root, faction_id), clean)
    return clean


# --------------------------------------------------------------------------- units


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def validate_unit(unit: Any, classes: List[Dict[str, Any]], faction_ids: List[str]) -> List[Dict[str, Any]]:
    """Return a list of {"field", "message"} errors (empty if valid)."""
    errors: List[Dict[str, Any]] = []
    if not isinstance(unit, dict):
        return [{"field": "unit", "message": "must be an object"}]

    def add(field: str, message: str) -> None:
        errors.append({"field": field, "message": message})

    for key in unit:
        if key not in UNIT_KEY_ORDER:
            add(str(key), "unknown field")
    if not is_valid_id(unit.get("id")):
        add("id", "must match [a-z0-9_]{2,48}")
    for key in STRING_FIELDS:
        if key in unit and unit[key] is not None and not isinstance(unit[key], str):
            add(key, "must be a string")
    if not isinstance(unit.get("real_name"), str) or not unit.get("real_name", "").strip():
        add("real_name", "required")
    class_ids = [c.get("id") for c in classes]
    if unit.get("class") not in class_ids:
        add("class", "unknown class %r" % (unit.get("class"),))
    if unit.get("mobility") not in MOBILITIES:
        add("mobility", "must be one of %s" % ", ".join(MOBILITIES))
    ops = unit.get("operators", [])
    if not isinstance(ops, list):
        add("operators", "must be a list of faction ids")
    else:
        for op in ops:
            if op not in faction_ids:
                add("operators", "unknown faction %r" % (op,))
    crew = unit.get("crew")
    if crew is not None and crew != "" and not isinstance(crew, str) and not _is_number(crew):
        add("crew", "must be text or a number")
    for key in NUMERIC_FIELDS:
        v = unit.get(key)
        if v is None or v == "":
            continue
        if not _is_number(v) or v < 0:
            add(key, "must be a non-negative number")
    arm = unit.get("armament", {})
    if isinstance(arm, dict):
        for key in arm:
            if key not in ARMAMENT_KEYS:
                add("armament." + str(key), "unknown field")
    if not isinstance(arm, dict) or any(not isinstance(v, str) for v in arm.values()):
        add("armament", "must be an object with text values (main, secondary)")
    dims = unit.get("dimensions", {})
    if not isinstance(dims, dict):
        add("dimensions", "must be an object")
    else:
        for key in dims:
            if key not in DIMENSION_KEYS:
                add("dimensions." + str(key), "unknown field")
        for key in DIMENSION_KEYS[:4]:
            v = dims.get(key)
            if v is None or v == "":
                continue
            if not _is_number(v) or v < 0:
                add("dimensions." + key, "must be a non-negative number")
        srcs = dims.get("sources", [])
        if not isinstance(srcs, list) or any(not isinstance(s, str) for s in srcs):
            add("dimensions.sources", "must be a list of URLs")
    for key in STRING_LIST_FIELDS:
        v = unit.get(key, [])
        if not isinstance(v, list) or any(not isinstance(s, str) for s in v):
            add(key, "must be a list of strings")
    images = unit.get("images", [])
    if not isinstance(images, list):
        add("images", "must be a list")
    else:
        for i, img in enumerate(images):
            if not isinstance(img, dict):
                add("images[%d]" % i, "must be an object")
                continue
            for key in img:
                if key not in IMAGE_KEYS:
                    add("images[%d].%s" % (i, key), "unknown field")
            try:
                check_image_file_name(img.get("file"))
            except CatalogError:
                add("images[%d].file" % i, "invalid file name")
            if img.get("view") not in VIEWS:
                add("images[%d].view" % i, "must be one of %s" % ", ".join(VIEWS))
            for k in ("source_url", "license", "note"):
                if not isinstance(img.get(k, ""), str):
                    add("images[%d].%s" % (i, k), "must be a string")
    errors.extend(_validate_candidates(unit.get("image_candidates", [])))
    errors.extend(_validate_provenance(unit.get("provenance", {})))
    rev = unit.get("revision", 0)
    if not isinstance(rev, int) or isinstance(rev, bool) or rev < 0:
        add("revision", "must be a non-negative integer")
    if unit.get("status") not in STATUSES:
        add("status", "must be one of %s" % ", ".join(STATUSES))
    return errors


def _validate_candidates(cands: Any) -> List[Dict[str, Any]]:
    if not isinstance(cands, list):
        return [{"field": "image_candidates", "message": "must be a list"}]
    errors = []
    for i, c in enumerate(cands):
        f = "image_candidates[%d]" % i
        if not isinstance(c, dict):
            errors.append({"field": f, "message": "must be an object"})
            continue
        for key in c:
            if key not in CANDIDATE_KEYS:
                errors.append({"field": "%s.%s" % (f, key), "message": "unknown field"})
        if not isinstance(c.get("url"), str) or not c["url"].startswith("https://"):
            errors.append({"field": f + ".url", "message": "must be an https:// URL"})
        if c.get("view") not in VIEWS:
            errors.append({"field": f + ".view", "message": "must be one of %s" % ", ".join(VIEWS)})
        for key in ("license", "source_page", "note"):
            if not isinstance(c.get(key, ""), str):
                errors.append({"field": "%s.%s" % (f, key), "message": "must be a string"})
    return errors


def _validate_provenance(prov: Any) -> List[Dict[str, Any]]:
    if not isinstance(prov, dict):
        return [{"field": "provenance", "message": "must be an object"}]
    errors = []
    for path, entry in prov.items():
        f = "provenance.%s" % path
        if path not in RESEARCH_FIELDS:
            errors.append({"field": f, "message": "not a researchable field"})
            continue
        if not isinstance(entry, dict) or any(k not in PROVENANCE_KEYS for k in entry):
            errors.append({"field": f, "message": "must be an object with source, verified, suggested"})
            continue
        if not isinstance(entry.get("source", ""), str):
            errors.append({"field": f + ".source", "message": "must be a string"})
        if not isinstance(entry.get("verified", False), bool):
            errors.append({"field": f + ".verified", "message": "must be true or false"})
    return errors


def unverified_fields(unit: Dict[str, Any]) -> List[str]:
    """Dotted paths whose current value came from AI research and was not verified by the human yet."""
    prov = unit.get("provenance") or {}
    return [p for p in RESEARCH_FIELDS if isinstance(prov.get(p), dict) and prov[p].get("verified") is False]


def readiness_missing(unit: Dict[str, Any]) -> List[str]:
    """Items still missing before the unit may be `ready_for_model` (empty list = ready)."""
    missing = []
    if not str(unit.get("real_name") or "").strip():
        missing.append("real_name")
    if not unit.get("class"):
        missing.append("class")
    if not unit.get("operators"):
        missing.append("operators")
    dims = unit.get("dimensions") or {}
    for key in ("height", "width", "hull_length"):
        v = dims.get(key)
        if not _is_number(v) or v <= 0:
            missing.append(key)
    feats = [f for f in (unit.get("silhouette_features") or []) if str(f).strip()]
    if len(feats) < 3:
        missing.append("silhouette_features (at least 3)")
    if not any(i.get("view") in ("side", "drawing") for i in (unit.get("images") or [])):
        missing.append("side or drawing image")
    unverified = unverified_fields(unit)
    for path in MODEL_CRITICAL_FIELDS:
        if path in unverified:
            missing.append("verify %s (AI)" % path)
    return missing


def completeness(unit: Dict[str, Any]) -> float:
    """Fraction (0..1) of the useful fields that are filled in. Only used for the overview bar."""
    dims = unit.get("dimensions") or {}
    arm = unit.get("armament") or {}
    images = unit.get("images") or []
    checks = [
        bool(unit.get("real_name")), bool(unit.get("class")), bool(unit.get("operators")),
        bool(unit.get("in_service")), bool(unit.get("country_of_origin")), bool(unit.get("crew")),
        bool(unit.get("weight_t")), bool(arm.get("main")), bool(unit.get("protection")),
        bool(unit.get("speed_road_kmh")), bool(dims.get("hull_length")), bool(dims.get("width")),
        bool(dims.get("height")), bool(dims.get("sources")),
        len(unit.get("silhouette_features") or []) >= 3,
        any(i.get("view") in ("side", "drawing") for i in images),
        len(images) >= 3,
    ]  # fmt: skip
    return sum(1 for c in checks if c) / float(len(checks))


def load_unit(root: Path, unit_id: str) -> Dict[str, Any]:
    path = unit_dir(root, unit_id) / "unit.json"
    data = _read_json(path, None)
    if data is None:
        raise _err("id", "unit %r not found" % unit_id, 404)
    return data  # type: ignore[no-any-return]


def list_unit_ids(root: Path) -> List[str]:
    udir = Path(root) / "units"
    if not udir.is_dir():
        return []
    return sorted(p.name for p in udir.iterdir() if (p / "unit.json").is_file() and is_valid_id(p.name))


def _today() -> str:
    return time.strftime("%Y-%m-%d")


def _stored_revision(unit: Optional[Dict[str, Any]]) -> int:
    rev = (unit or {}).get("revision", 0)
    return rev if isinstance(rev, int) and not isinstance(rev, bool) else 0


def _content(unit: Dict[str, Any]) -> Dict[str, Any]:
    return {k: v for k, v in unit.items() if k not in ("updated", "revision")}


def save_unit(root: Path, unit: Dict[str, Any], today: Optional[str] = None) -> Dict[str, Any]:
    """Validate and save a unit. Enforces the readiness gate for `ready_for_model`.

    The file is rewritten only when the content changed; then `revision` is incremented.
    """
    root = Path(root)
    if not isinstance(unit, dict):
        raise _err("unit", "must be an object")
    unit_id = check_id(unit.get("id"))
    errors = validate_unit(unit, load_classes(root), [f["id"] for f in load_factions(root)])
    if errors:
        raise CatalogError(errors)
    if unit["status"] == "ready_for_model":
        missing = readiness_missing(unit)
        if missing:
            raise _err("status", "not ready for model, missing: " + ", ".join(missing), 400, missing=missing)
    clean = normalize_unit(unit)
    with _WRITE_LOCK:
        path = unit_dir(root, unit_id) / "unit.json"
        stored = _read_json(path, None)
        if stored is not None and _content(stored) == _content(clean):
            return stored  # type: ignore[no-any-return]
        clean["updated"] = today or _today()
        clean["revision"] = _stored_revision(stored) + 1
        clean = normalize_unit(clean)
        _write_json(path, clean)
    return clean


def create_unit(root: Path, real_name: str, unit_id: Optional[str] = None, **fields: Any) -> Dict[str, Any]:
    root = Path(root)
    if not isinstance(real_name, str) or not real_name.strip():
        raise _err("real_name", "required")
    unit_id = unit_id or slugify(real_name)
    check_id(unit_id)
    with _WRITE_LOCK:
        if (unit_dir(root, unit_id) / "unit.json").exists():
            raise _err("id", "unit %r already exists" % unit_id, 409)
        classes = load_classes(root)
        cls = fields.get("class") or (classes[0]["id"] if classes else "")
        mobility = fields.get("mobility") or next((c["mobility"] for c in classes if c["id"] == cls), "tracked")
        unit = {"id": unit_id, "real_name": real_name.strip(), "class": cls, "mobility": mobility,
                "operators": fields.get("operators", []), "status": "draft"}  # fmt: skip
        return save_unit(root, unit)


def update_unit(root: Path, unit_id: str, incoming: Dict[str, Any]) -> Dict[str, Any]:
    """PUT semantics: replace everything except the image list, which only accepts metadata edits.

    If `incoming` carries a `revision` that differs from the stored one, nothing is written (409).
    """
    check_id(unit_id)
    if not isinstance(incoming, dict):
        raise _err("unit", "must be an object")
    if incoming.get("id", unit_id) != unit_id:
        raise _err("id", "does not match the URL")
    with _WRITE_LOCK:
        stored = load_unit(root, unit_id)
        if "revision" in incoming and incoming["revision"] != _stored_revision(stored):
            raise _err("revision", "the unit was changed elsewhere (stored revision %d)" % _stored_revision(stored), 409)
        new = dict(incoming)
        new["id"] = unit_id
        stored_images = {i["file"]: i for i in stored.get("images", []) if isinstance(i, dict) and "file" in i}
        meta = {i.get("file"): i for i in (incoming.get("images") or []) if isinstance(i, dict)}
        merged = []
        for file, img in stored_images.items():
            m = meta.get(file, {})
            merged.append({
                "file": file,
                "view": m.get("view", img.get("view")),
                "source_url": m.get("source_url", img.get("source_url", "")),
                "license": m.get("license", img.get("license", "")),
                "note": m.get("note", img.get("note", "")),
            })  # fmt: skip
        new["images"] = merged
        return save_unit(root, new)


# --------------------------------------------------------------------------- images


def sniff_image(data: bytes) -> Optional[str]:
    """Return the extension for jpg/png/webp by magic bytes, else None."""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:3] == b"\xff\xd8\xff":
        return "jpg"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


def next_image_name(directory: Path, view: str, ext: str) -> str:
    highest = 0
    if Path(directory).is_dir():
        for p in Path(directory).iterdir():
            m = IMAGE_FILE_RE.fullmatch(p.name)
            if m and m.group(1) == view:
                highest = max(highest, int(m.group(2)))
    return "%s_%d.%s" % (view, highest + 1, ext)


def add_image(root: Path, unit_id: str, view: str, data_b64: str, source_url: str = "",
              license: str = "", note: str = "") -> Dict[str, Any]:  # fmt: skip
    if view not in VIEWS:
        raise _err("view", "must be one of %s" % ", ".join(VIEWS))
    if not isinstance(data_b64, str):
        raise _err("data", "base64 string required")
    if data_b64.startswith("data:") and "," in data_b64[:100]:
        data_b64 = data_b64.split(",", 1)[1]
    if len(data_b64) > MAX_IMAGE_BYTES * 4 // 3 + 16:
        raise _err("data", "image larger than 15 MB", 413)
    try:
        data = base64.b64decode(data_b64, validate=True)
    except (binascii.Error, ValueError):
        raise _err("data", "invalid base64")
    return add_image_bytes(root, unit_id, view, data, source_url, license, note)


def add_image_bytes(root: Path, unit_id: str, view: str, data: bytes, source_url: str = "",
                    license: str = "", note: str = "", drop_candidate: str = "") -> Dict[str, Any]:  # fmt: skip
    """Store image bytes as the next `<view>_<n>` file; optionally remove the image candidate with that URL."""
    udir = unit_dir(root, unit_id)
    if view not in VIEWS:
        raise _err("view", "must be one of %s" % ", ".join(VIEWS))
    if len(data) > MAX_IMAGE_BYTES:
        raise _err("data", "image larger than 15 MB", 413)
    ext = sniff_image(data)
    if ext is None:
        raise _err("data", "not a jpg, png or webp image")
    with _WRITE_LOCK:
        unit = load_unit(root, unit_id)
        name = next_image_name(udir, view, ext)
        path = udir / name
        atomic_write(path, data)
        entry = {"file": name, "view": view, "source_url": str(source_url or ""),
                 "license": str(license or ""), "note": str(note or "")}  # fmt: skip
        unit.setdefault("images", []).append(entry)
        if drop_candidate:
            unit["image_candidates"] = [c for c in unit.get("image_candidates", []) if c.get("url") != drop_candidate]
        try:
            save_unit(root, unit)
        except BaseException:
            if path.exists():
                path.unlink()
            raise
    return entry


def missing_image_files(root: Path, unit: Dict[str, Any]) -> List[str]:
    """Images listed in unit.json whose file is not on disk (image files are not in git - see README)."""
    udir = unit_dir(root, unit["id"])
    return [i["file"] for i in unit.get("images", []) if isinstance(i, dict) and not (udir / str(i.get("file"))).is_file()]


def restore_image(root: Path, unit_id: str, file: str, data: bytes) -> None:
    """Write the downloaded bytes of a listed-but-missing image under its recorded name."""
    check_image_file_name(file)
    if len(data) > MAX_IMAGE_BYTES:
        raise _err("data", "image larger than 15 MB", 413)
    ext = sniff_image(data)
    if ext is None:
        raise _err("data", "not a jpg, png or webp image")
    if IMAGE_FILE_RE.fullmatch(file).group(3) != ext:  # type: ignore[union-attr]
        raise _err("data", "the source is a %s now, the catalog expects %s" % (ext, file))
    with _WRITE_LOCK:
        unit = load_unit(root, unit_id)
        if file not in missing_image_files(root, unit):
            raise _err("file", "not a missing image of this unit", 409)
        atomic_write(unit_dir(root, unit_id) / file, data)


def find_candidate(root: Path, unit_id: str, url: Any) -> Dict[str, Any]:
    for c in load_unit(root, unit_id).get("image_candidates", []):
        if c.get("url") == url:
            return c  # type: ignore[no-any-return]
    raise _err("url", "image candidate not found", 404)


def dismiss_candidate(root: Path, unit_id: str, url: Any) -> None:
    with _WRITE_LOCK:
        find_candidate(root, unit_id, url)
        unit = load_unit(root, unit_id)
        unit["image_candidates"] = [c for c in unit.get("image_candidates", []) if c.get("url") != url]
        save_unit(root, unit)


def delete_image(root: Path, unit_id: str, file: str) -> None:
    udir = unit_dir(root, unit_id)
    check_image_file_name(file)
    with _WRITE_LOCK:
        unit = load_unit(root, unit_id)
        images = unit.get("images", [])
        if not any(i.get("file") == file for i in images):
            raise _err("file", "image not found", 404)
        remaining = [i for i in images if i.get("file") != file]
        if unit.get("status") == "ready_for_model" and not any(i.get("view") in ("side", "drawing") for i in remaining):
            raise _err("file", "this is the only side or drawing image of a ready_for_model unit - "
                       "set the status back to draft first", 409)  # fmt: skip
        unit["images"] = remaining
        save_unit(root, unit)  # unit.json first, so a failure leaves the file in place
        path = udir / file
        if path.exists():
            path.unlink()


# --------------------------------------------------------------------------- AI research


def get_path(data: Dict[str, Any], path: str) -> Any:
    for part in path.split("."):
        if not isinstance(data, dict):
            return None
        data = data.get(part)  # type: ignore[assignment]
    return data


def set_path(data: Dict[str, Any], path: str, value: Any) -> None:
    *parents, last = path.split(".")
    for part in parents:
        data = data.setdefault(part, {})
    data[last] = value


def merge_research(unit: Dict[str, Any], research: Any, classes: List[Dict[str, Any]],
                   faction_ids: List[str]) -> Dict[str, Any]:  # fmt: skip
    """Merge an AI research result into `unit` (in place). Returns a report.

    `research` is `{"fields": {path: {"value", "source"}}, "image_candidates": [...], "summary": str}`.
    Empty fields are filled and marked unverified; a different value in a field the human already filled
    becomes a `suggested` value instead. Values that would make the unit invalid are rejected.
    """
    report: Dict[str, Any] = {"filled": [], "suggested": [], "rejected": [], "candidates": 0, "summary": ""}
    if not isinstance(research, dict):
        raise _err("research", "must be an object")
    fields = research.get("fields", {})
    if not isinstance(fields, dict):
        raise _err("research.fields", "must be an object")
    prov = unit.setdefault("provenance", {})

    def reject(path: str, message: str) -> None:
        report["rejected"].append({"field": path, "message": message})

    for path, item in fields.items():
        if path not in RESEARCH_FIELDS:
            reject(str(path), "not a researchable field")
            continue
        if not isinstance(item, dict) or "value" not in item:
            reject(path, "must be an object with a value")
            continue
        value, source = item["value"], item.get("source", "")
        if not isinstance(source, str):
            reject(path, "source must be a string")
            continue
        if _empty(value):
            continue
        trial = json.loads(json.dumps(unit))
        set_path(trial, path, value)
        problems = validate_unit(trial, classes, faction_ids)
        if problems:
            reject(path, "; ".join(e["message"] for e in problems))
            continue
        current = get_path(unit, path)
        if _empty(current):
            set_path(unit, path, value)
            prov[path] = {"source": source, "verified": False}
            report["filled"].append(path)
            if path.startswith("dimensions.") and source.strip():
                srcs = unit["dimensions"].setdefault("sources", [])
                if source.strip() not in srcs:
                    srcs.append(source.strip())
        elif current != value:
            old = prov.get(path) or {}
            prov[path] = {"source": source, "verified": old.get("verified", True), "suggested": value}
            report["suggested"].append(path)

    cands = research.get("image_candidates", [])
    if not isinstance(cands, list):
        reject("image_candidates", "must be a list")
        cands = []
    known = {c.get("url") for c in unit.get("image_candidates", []) if isinstance(c, dict)}
    known |= {i.get("source_url") for i in unit.get("images", []) if isinstance(i, dict)}
    for i, c in enumerate(cands):
        clean = {k: c[k] for k in CANDIDATE_KEYS if k in c} if isinstance(c, dict) else c
        problems = _validate_candidates([clean])
        if problems:
            reject("image_candidates[%d]" % i, "; ".join(e["message"] for e in problems))
        elif clean["url"] not in known:
            known.add(clean["url"])
            unit.setdefault("image_candidates", []).append(clean)
            report["candidates"] += 1
    summary = research.get("summary", "")
    report["summary"] = summary if isinstance(summary, str) else ""
    return report


def apply_research(root: Path, unit_id: str) -> Dict[str, Any]:
    """Merge the unit's pending `research.json` (written by /research-unit) into unit.json, then delete it."""
    path = unit_dir(root, unit_id) / RESEARCH_FILE
    with _WRITE_LOCK:
        try:
            research = _read_json(path, None)
        except ValueError:
            raise _err("research", "%s is not valid JSON" % RESEARCH_FILE)
        if research is None:
            raise _err("research", "no pending %s" % RESEARCH_FILE, 404)
        unit = load_unit(root, unit_id)
        report = merge_research(unit, research, load_classes(root), [f["id"] for f in load_factions(root)])
        save_unit(root, unit)
        path.unlink()
    return report


# --------------------------------------------------------------------------- catalog / review


def read_blueprint(root: Path, unit_id: str) -> Optional[str]:
    path = unit_dir(root, unit_id) / "blueprint.md"
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None


def latest_sheet(screenshots_dir: Path, unit_id: str) -> Optional[str]:
    """File name of the newest `<unit_id>_*_sheet.png` render sheet, or None."""
    check_id(unit_id)
    d = Path(screenshots_dir)
    if not d.is_dir():
        return None
    found = [p for p in d.glob(unit_id + "_*_sheet.png") if p.is_file()]
    if not found:
        return None
    return max(found, key=lambda p: (p.stat().st_mtime, p.name)).name


def unit_summary(unit: Dict[str, Any], root: Optional[Path] = None) -> Dict[str, Any]:
    return {
        "id": unit.get("id"),
        "real_name": unit.get("real_name", ""),
        "class": unit.get("class", ""),
        "mobility": unit.get("mobility", ""),
        "operators": unit.get("operators", []),
        "image_count": len(unit.get("images", [])),
        "completeness": round(completeness(unit), 3),
        "status": unit.get("status", "draft"),
        "missing_images": len(missing_image_files(root, unit)) if root is not None else 0,
    }


def catalog_summary(root: Path) -> Dict[str, Any]:
    units = []
    for uid in list_unit_ids(root):
        try:
            units.append(unit_summary(load_unit(root, uid), root))
        except (CatalogError, ValueError):
            continue
    return {"classes": load_classes(root), "factions": load_factions(root), "units": units,
            "views": list(VIEWS), "statuses": list(STATUSES), "mobilities": list(MOBILITIES)}  # fmt: skip


def unit_detail(root: Path, unit_id: str, screenshots_dir: Path) -> Dict[str, Any]:
    unit = load_unit(root, unit_id)
    return {
        "unit": unit,
        "missing": readiness_missing(unit),
        "completeness": round(completeness(unit), 3),
        "review": {"blueprint": read_blueprint(root, unit_id), "sheet": latest_sheet(screenshots_dir, unit_id)},
        "pending_research": (unit_dir(root, unit_id) / RESEARCH_FILE).is_file(),
        "missing_images": missing_image_files(root, unit),
    }
