# AGM-158B JASSM-ER – model blueprint

Model: `src/presentation/models/weapons/jassm_er.gd` (TASK-144), registered in `WeaponModels`.
Render: `render.png` (sheet from `tools/render_unit.sh --weapon jassm_er`: side, front, top, three-quarter).
No reference image is stored yet; shapes follow published photographs (Commons category "AGM-158 JASSM").

## Scale and frame

1 unit = 1 m (weapon contract, not the unit models' 1 unit = 10 m). Nose along +X, origin at the
centre of mass, assumed at 47 % of the length from the nose (seeker and warhead forward, engine aft):
nose tip x = +2.01, tail x = −2.26. Body centre y = 0.

| Part | Size (m) | Position | Material |
|---|---|---|---|
| Body (`MeshKit.stack`, 5 stations of a 6-point section) | 4.27 long, 0.55 wide (chines), 0.45 high | x −2.26 … +2.01 | `BODY` olive grey #5d6157, roughness 0.78 |
| Section | flat belly 0.42 wide at y −0.225, chines ±0.275 at y −0.10, flat top 0.26 wide at y +0.225 | | |
| Nose (stations 0–2) | tip 0.165 × 0.07 at y −0.16, 0.85 long | x +1.16 … +2.01 | body |
| Boat tail (stations 3–4) | tapers to 62 % over 0.75 | x −2.26 … −1.51 | body |
| Wing (2 × `plate`) | span 2.4, root chord 0.42, tip chord 0.20, LE sweep 30°, 0.035 thick | on the body top, root centre x −0.05 | body |
| Vertical fin (`plate`) | 0.28 high, root chord 0.55, tip chord 0.20, LE sweep 45°, 0.03 thick | tail top | body |
| Ventral intake scoop (`stack`) | 0.26 wide, 0.07 deep, ramps into the belly | x −1.50 … −0.55 | body, mouth `DARK` |
| Exhaust | 70 % of the tail section | x −2.26 | `DARK` |
| Seeker window | 70 % of the upper nose facet | nose top | `GLASS` |

## Silhouette features

1. Faceted box-like body: the trapezoid section with hard chines (flat-shaded facets).
2. Flat chined nose: the top slopes down to a low, flattened tip; dark seeker window on top.
3. Small swept wing on top just aft of the centre of mass (deployed).
4. Single swept vertical fin on the tail top.
5. Intake scoop under the rear half; tapered boat tail with a dark exhaust.

## Budget

112 triangles, 3 mesh instances (body, dark, glass), limit 400 (`WeaponModels.MAX_TRIANGLES`).
Bounding box 4.27 × 2.40 (span) × 0.76 m (catalog 4.27 × 2.4 × 0.75; height = body + fin, estimated).

## Known differences

- The task brief described a V-tail and a dorsal intake; the sources found (Wikipedia, Air & Space
  Forces) describe a **single vertical tail**, and photographs show the intake **under** the body,
  so the model follows those. Wikipedia's infobox also lists "2 tailplanes" – not modelled (unclear).
- Span: 2.4 m as in the task; Wikipedia and CSIS give 2.7 m for the deployed JASSM-ER wing.
- The real wing pivots on one point and its planform is slightly curved at the root; modelled as two
  straight tapered panels.
