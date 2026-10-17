# TASK-023: Localization setup (English + Polish)

- **Status**: ready
- **Layers**: presentation (+ translation data, project settings; checks in `tests/unit/`)
- **Depends on**: nothing hard. Recommended right after TASK-014 and **before** the HUD tasks (TASK-015, -020, -024, -021), so they add their strings through `tr()` from the start instead of retrofitting.

## Goal

The game can be played in Polish (the language of the mock-up) while all strings in code stay English. One CSV file holds every UI string with an English and a Polish column.

## Design decisions

- **Keys are the English source strings** (gettext style: `tr("Your turn")`), not symbolic IDs. Reasons: CLAUDE.md keeps UI strings in code English and readable; a missing key falls back to the English text automatically; pure formatter tests (e.g. `test_unit_info.gd`) keep asserting English text under the default locale. Format strings are keys too (`"Turn %d"`), the values are substituted after translation: `tr("Turn %d") % turn`.
- Static/pure helpers (no `Object.tr()`) call `TranslationServer.translate(key)`.
- Labels whose text is composed in code set `auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED` so already-translated text is not translated a second time.
- Unit names from `data/units/*.tres` (`display_name`) are translated at display time with the English name as key (`"Infantry"`, `"Cavalry"`); the data files stay English.
- Locale: Godot picks the OS locale; fallback `en`. For testing Polish use the project setting `internationalization/locale/test = "pl"` (do not commit it set). A language switch in a settings screen is out of scope.

## Acceptance criteria (testable)

- [ ] `assets/i18n/strings.csv` (UTF-8, comma-separated, header exactly `keys,en,pl`) with one row per UI string that exists at the time of implementation. At minimum (Polish proposals – the human may correct them):

  | keys | en | pl |
  |---|---|---|
  | `Turn %d · %s` | Turn %d · %s | Tura %d · %s |
  | `Your turn` | Your turn | Twoja tura |
  | `AI turn` | AI turn | Tura przeciwnika |
  | `Victory!` | Victory! | Zwycięstwo! |
  | `Defeat!` | Defeat! | Porażka! |
  | current controls hint (`LMB – select/move/attack · Enter – end turn · WASD/QE/wheel – camera`) | (same) | LPM – wybór/ruch/atak · Enter – koniec tury · WASD/QE/kółko – kamera |
  | `HP %d/%d` | HP %d/%d | PŻ %d/%d |
  | `Moves %d/%d` | Moves %d/%d | Ruch %d/%d |
  | `Attack %d · Defense %d · Range %d` | (same) | Atak %d · Obrona %d · Zasięg %d |
  | `Ready to attack` | Ready to attack | Gotowa do ataku |
  | `Already attacked` | Already attacked | Już atakowała |
  | `Infantry` | Infantry | Piechota |
  | `Cavalry` | Cavalry | Kawaleria |

- [ ] The CSV is imported by Godot (`--import`) into `strings.en.translation` / `strings.pl.translation`; `project.godot` has `internationalization/locale/translations` listing both and `internationalization/locale/fallback = "en"`. (Whether the generated `.translation` files are committed follows what `--import` produces; don't hand-edit `*.import`.)
- [ ] All HUD strings in `src/presentation/` go through `tr()` / `TranslationServer.translate()`: `BattleController._update_status`, `UnitInfo.lines()` (all 5 lines, including the translated `display_name`; the fallback to `String(definition.id)` for an empty name stays untranslated).
- [ ] Tests `tests/unit/test_localization.gd`:
  - CSV integrity: header `keys,en,pl`; every row has 3 non-empty fields; no duplicate keys; for every row the `printf` placeholders (`%d`, `%s`, `%%`) in `en` and `pl` are the same multiset as in the key.
  - Coverage: every string literal `X` in `tr("X")` / `TranslationServer.translate("X")` in `src/**/*.gd` (scan files with `RegEx`) is a key in the CSV.
  - With `TranslationServer.set_locale("pl")`: `TranslationServer.translate("Your turn") == "Twoja tura"`; `UnitInfo.lines(<fresh infantry>)[0] == "Piechota"` and `[2] == "Ruch 3/3"`. With `"en"`: the existing `test_unit_info.gd` expectations hold. The test restores the previous locale afterwards (also on failure paths – restore in the test's cleanup).
  - Unknown key `"__missing__"` translates to itself.
- [ ] `docs/ARCHITECTURE.md` gets a short "Localization" paragraph (where the CSV is, key convention, `AUTO_TRANSLATE_MODE_DISABLED` for composed labels, "every new UI string = a CSV row with en + pl").
- [ ] Agent visual check: take a screenshot with `tools/screenshot.sh` (English) – identical to before. Then temporarily set `internationalization/locale/test="pl"`, take another screenshot and check the status text is Polish with correct diacritics (`ę`, `ż`, `ł` rendered by IBM Plex, no tofu boxes); revert the setting.

## Playtest (for the human)

1. `tools/run.sh` – everything is in English as before.
2. Set *Project Settings → Internationalization → Locale → Test* to `pl`, run – the status line reads `Tura 1 · Twoja tura`, the selected unit panel shows `Piechota`, `PŻ 10/10`, `Ruch 3/3`, `Atak 4 · Obrona 3 · Zasięg 1`, `Gotowa do ataku`.
3. Check the Polish wording and correct the CSV if needed (the agent's Polish is a proposal). Reset the test locale.

## Out of scope

- A language selector / settings screen, live locale switching.
- Plural forms (`%d units`) – add with the first string that needs them (Godot `tr_n`).
- Translating log/debug output (`print`) and command rejection codes.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._
