extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")

const TOLERANCE := 0.002


func _assert_color(actual: Color, expected: Color) -> void:
	assert_true(actual.is_equal_approx(expected), "expected %s, got %s" % [expected, actual])


func test_hp_color_thresholds() -> void:
	assert_eq(UiPalette.hp_color(10, 10), UiPalette.HP_HIGH)
	assert_eq(UiPalette.hp_color(7, 10), UiPalette.HP_HIGH)
	assert_eq(UiPalette.hp_color(6, 10), UiPalette.HP_MID)
	assert_eq(UiPalette.hp_color(4, 10), UiPalette.HP_MID)
	assert_eq(UiPalette.hp_color(3, 10), UiPalette.HP_LOW)
	assert_eq(UiPalette.hp_color(0, 10), UiPalette.HP_LOW)
	assert_eq(UiPalette.hp_color(5, 0), UiPalette.HP_LOW)


func test_palette_values() -> void:
	# Independent of the palette's own formula: #11130f is (17, 19, 15).
	var expected := Color.html("#11130f")
	expected.a = 0.84
	assert_true(absf(UiPalette.PANEL_BG.r - expected.r) < TOLERANCE)
	assert_true(absf(UiPalette.PANEL_BG.g - expected.g) < TOLERANCE)
	assert_true(absf(UiPalette.PANEL_BG.b - expected.b) < TOLERANCE)
	assert_true(absf(UiPalette.PANEL_BG.a - expected.a) < TOLERANCE)
	_assert_color(FactionRegistry.get_faction(&"poland").color, Color.html("#5b93d6"))


func test_default_font_is_plex_condensed() -> void:
	var theme := HudTheme.build()
	assert_true(theme.default_font != null)
	assert_true(theme.default_font.get_font_name().contains("IBM Plex Sans Condensed"))
	assert_eq(theme.default_font_size, 14)
	_assert_color(theme.get_color(&"font_color", &"Label"), UiPalette.TEXT)


func test_panel_style() -> void:
	var theme := HudTheme.build()
	var box := theme.get_stylebox(&"panel", &"PanelContainer") as StyleBoxFlat
	assert_true(box != null)
	assert_eq(box.bg_color, UiPalette.PANEL_BG)
	assert_eq(box.border_color, UiPalette.PANEL_BORDER)
	assert_eq(box.border_width_left, 1)
	assert_eq(box.border_width_top, 1)
	assert_eq(box.border_width_right, 1)
	assert_eq(box.border_width_bottom, 1)
	assert_eq(box.corner_radius_top_left, 0)
	assert_eq(box.corner_radius_bottom_right, 0)
	assert_eq(box.content_margin_left, 12.0)
	assert_eq(box.content_margin_right, 12.0)
	assert_eq(box.content_margin_top, 9.0)
	assert_eq(box.content_margin_bottom, 9.0)


func test_type_variations_exist() -> void:
	var theme := HudTheme.build()
	for variation: StringName in [&"TitleLabel", &"CaptionLabel", &"ValueLabel", &"MonoLabel"]:
		assert_eq(theme.get_type_variation_base(variation), &"Label", str(variation))
	assert_eq(theme.get_font_size(&"font_size", &"TitleLabel"), 20)
	assert_eq(theme.get_font_size(&"font_size", &"CaptionLabel"), 10)
	assert_eq(theme.get_font_size(&"font_size", &"ValueLabel"), 13)
	assert_eq(theme.get_font_size(&"font_size", &"MonoLabel"), 11)
	_assert_color(theme.get_color(&"font_color", &"CaptionLabel"), UiPalette.TEXT_SECONDARY)
	_assert_color(theme.get_color(&"font_color", &"MonoLabel"), UiPalette.TEXT_MUTED)
	var caption := theme.get_font(&"font", &"CaptionLabel") as FontVariation
	assert_true(caption != null)
	assert_eq(caption.spacing_glyph, 2)


func test_fonts_are_cached_between_builds() -> void:
	var a := HudTheme.build()
	var b := HudTheme.build()
	assert_true(a.default_font == b.default_font)
	assert_true(a.get_font(&"font", &"CaptionLabel") == b.get_font(&"font", &"CaptionLabel"))


func test_button_style() -> void:
	var theme := HudTheme.build()
	var font := theme.get_font(&"font", &"Button")
	assert_true(font.get_font_name().contains("IBM Plex Sans Condensed"))
	assert_eq(theme.get_font_size(&"font_size", &"Button"), 15)
	var box := theme.get_stylebox(&"normal", &"Button") as StyleBoxFlat
	assert_true(box != null)
	assert_eq(box.corner_radius_top_left, 0)
	assert_eq(box.corner_radius_bottom_right, 0)


func test_faction_helpers_fall_back_to_neutral() -> void:
	var state := GameState.new(Fixtures.plains_grid(1), 2, 1)
	assert_eq(UiPalette.faction_color(state, 1), state.faction_of(1).color)
	assert_eq(UiPalette.faction_color(state, 5), UiPalette.NEUTRAL_FACTION)
	assert_eq(UiPalette.faction_ink(state, -1), UiPalette.NEUTRAL_INK)
	assert_eq(UiPalette.faction_name(state, 5), "Player 6")
	assert_eq(UiPalette.faction_short(state, 5), "P6")
	assert_eq(UiPalette.color_of(null), UiPalette.NEUTRAL_FACTION)


func test_v3_tokens_match_the_design_readme() -> void:
	_assert_color(UiPalette.BG_APP, Color.html("#0a0c09"))
	_assert_color(UiPalette.AMBER, Color.html("#e8b04a"))
	_assert_color(UiPalette.HUD_TEXT, Color.html("#dfe5d6"))
	_assert_color(UiPalette.HUD_MUTED, Color.html("#8d9585"))
	_assert_color(UiPalette.HUD_DESC, Color.html("#b7bfae"))
	_assert_color(UiPalette.DISABLED, Color.html("#e07c5e"))
	_assert_color(UiPalette.NOTE_TEXT, Color.html("#f0c66e"))
	_assert_color(UiPalette.LINE, Color(232 / 255.0, 176 / 255.0, 74 / 255.0, 0.34))
	_assert_color(UiPalette.PANEL, Color(8 / 255.0, 11 / 255.0, 8 / 255.0, 0.86))
	_assert_color(UiPalette.PANEL_STRONG, Color(8 / 255.0, 11 / 255.0, 8 / 255.0, 0.93))
	_assert_color(UiPalette.NOTE_BG, Color(232 / 255.0, 176 / 255.0, 74 / 255.0, 0.10))
	_assert_color(UiPalette.HP_HIGH, Color.html("#b9d38a"))
	_assert_color(UiPalette.HP_MID, Color.html("#e2c069"))
	_assert_color(UiPalette.HP_LOW, Color.html("#e07c5e"))


func test_faction_data_matches_the_design_samples() -> void:
	_assert_color(FactionRegistry.get_faction(&"poland").ink_color, Color.html("#0f1a26"))
	_assert_color(FactionRegistry.get_faction(&"russia").color, Color.html("#d76a52"))
	_assert_color(FactionRegistry.get_faction(&"russia").ink_color, Color.html("#2a110b"))


func test_v3_fonts_load_with_the_needed_glyphs() -> void:
	var fonts: Array[Font] = []
	for weight in HudTheme.DISPLAY_WEIGHTS:
		fonts.append(HudTheme.display(weight))
	for weight in [400, 500, 600, 700]:
		fonts.append(HudTheme.mono(weight))
	for font in fonts:
		assert_true(font != null, "font missing")
		# Polish letters are mandatory in every face.
		for ch in "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ":
			assert_true(font.has_char(ch.unicode_at(0)), "%s lacks %s" % [font.get_font_name(), ch])
		# Symbols: own glyph or fallback, unless listed as a known gap (drawn as a shape).
		for ch in "▸◆■↵":
			if not HudTheme.GLYPH_GAPS.has(ch):
				assert_true(
					HudTheme.has_glyph(font, ch), "%s lacks %s" % [font.get_font_name(), ch]
				)


func test_v3_font_spacing_is_cached() -> void:
	var a := HudTheme.display(700, 2)
	var b := HudTheme.display(700, 2)
	assert_true(a == b)
	var c := HudTheme.mono(600, 1)
	var d := HudTheme.mono(600, 1)
	assert_true(c == d)
	assert_true(HudTheme.mono(400) != HudTheme.mono(700))
