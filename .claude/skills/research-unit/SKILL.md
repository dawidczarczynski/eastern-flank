---
name: research-unit
description: Researches one real unit on the web (facts, dimensions, silhouette features, reference image candidates) and writes a research.json proposal next to its unit catalog entry; the human verifies it in tools/unit_catalog.sh. Usage: /research-unit homar_k
---

You are researching the real unit `$ARGUMENTS` (a unit id from the catalog) so the human only has to **verify and correct** the data in the unit catalog tool instead of typing it in.

## Inputs

- `docs/design/units/units/<id>/unit.json` – at least `real_name` (and maybe `variant_note`, `class`, `operators`). Fields the human already filled are the human's: you may still report a different value you found, the tool shows it as a suggestion.
- `docs/design/units/classes.json` (what the class is) and `docs/design/units/factions/*.json` (the only valid `operators` ids).
- `docs/design/units/README.md` – what each field is for.

## Rules

1. **The exact variant.** Data for "M1A2 SEPv3" is not data for "M1A1"; "Homar-K" is the Polish K239 variant on a Jelcz chassis, not the Korean original. If a source mixes variants, say so in `summary` and skip the value rather than guess. If `real_name` is ambiguous, pick the variant the operators actually field and explain it in `summary` (and `variant_note`).
2. **Every value has a source** – the URL of the page you read it on (manufacturer, army, Army Recognition, Wikipedia in any language, …). No source → leave the field out. Never estimate or average numbers; never invent.
3. **Units:** dimensions in **metres** (`hull_length` = hull without gun/barrel, `overall_length` = with the gun forward), `weight_t` in tonnes, speeds in km/h, ranges in km. Numbers as JSON numbers, not strings.
4. **Silhouette features** (3–6, most recognisable from a distance first) describe the *shape* a modeler needs: e.g. "wedge-shaped turret front with spaced armour", "8 road wheels, no return rollers", "launcher pod box behind a 4-door cab". Source: the page with the best photo or description.
5. **Image candidates** (3–8): direct image file URLs (`https://`), best first – a side-view line drawing or a clean side photo, then top / front, then three-quarter. Prefer **Wikimedia Commons** (`https://upload.wikimedia.org/...` original file, not a thumbnail page) and give the licence from the file page (`CC BY-SA 4.0`, `Public domain`, …) plus the file page URL as `source_page`. Never download images yourself.
6. **Write only** `docs/design/units/units/<id>/research.json`. Do not edit `unit.json` or anything else – the tool merges the file, validates it and marks every value as unverified.

## Output: `research.json`

```json
{
  "fields": {
    "in_service": {"value": "2023-present", "source": "https://..."},
    "operators": {"value": ["poland"], "source": "https://..."},
    "crew": {"value": 3, "source": "https://..."},
    "weight_t": {"value": 32.5, "source": "https://..."},
    "armament.main": {"value": "2 × launch pod: 239 mm CGR-080 guided rockets or 600 mm KTSSM", "source": "https://..."},
    "dimensions.hull_length": {"value": 11.0, "source": "https://..."},
    "dimensions.width": {"value": 2.55, "source": "https://..."},
    "dimensions.height": {"value": 3.5, "source": "https://..."},
    "silhouette_features": {"value": ["…", "…", "…"], "source": "https://..."}
  },
  "image_candidates": [
    {"url": "https://upload.wikimedia.org/...jpg", "view": "side", "license": "CC BY-SA 4.0",
     "source_page": "https://commons.wikimedia.org/wiki/File:...", "note": "Polish army, 2024 parade"}
  ],
  "summary": "Variant chosen and why; values that differ between sources; what could not be found."
}
```

Allowed `fields` keys: `variant_note`, `in_service`, `country_of_origin`, `operators`, `crew`, `weight_t`, `armament.main`, `armament.secondary`, `protection`, `speed_road_kmh`, `speed_offroad_kmh`, `range_km`, `fire_range_km`, `notes`, `dimensions.hull_length`, `dimensions.overall_length`, `dimensions.width`, `dimensions.height`, `silhouette_features`, `details`, `skip`, `camo_note`. Image views: `side`, `front`, `rear`, `top`, `three_quarter`, `detail`, `drawing`.

Finish with a short summary for the human: what was filled, what is uncertain and should be checked first (dimensions!), and that the result is applied in the unit catalog tool (it applies `research.json` automatically when it started the run, otherwise the unit screen shows an "Apply research" button).
