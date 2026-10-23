extends TestCase


func test_screen_decor_ignores_mouse_and_uses_one_shader() -> void:
	var decor := ScreenDecor.new()
	assert_eq(decor.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var mat := decor.material as ShaderMaterial
	assert_true(mat != null and mat.shader != null)
	assert_eq(mat.get_shader_parameter(&"vignette_alpha"), UiPalette.VIGNETTE_EDGE.a)
	assert_eq(mat.get_shader_parameter(&"scanline_alpha"), UiPalette.SCANLINE.a)
	decor.free()


func test_screen_decor_does_not_change_layout() -> void:
	var parent := Control.new()
	var sibling := Control.new()
	sibling.custom_minimum_size = Vector2(40, 30)
	parent.add_child(sibling)
	var before_min := parent.get_combined_minimum_size()
	var before_rect := sibling.get_rect()
	var decor := ScreenDecor.new()
	parent.add_child(decor)
	assert_eq(parent.get_combined_minimum_size(), before_min)
	assert_eq(sibling.get_rect(), before_rect)
	assert_eq(decor.anchor_right, 1.0)
	assert_eq(decor.anchor_bottom, 1.0)
	parent.free()


func test_framed_panel_reserves_frame_padding_and_tab() -> void:
	var panel := FramedPanel.new()
	panel.padding = Vector2(12, 9)
	assert_eq(panel.get_theme_constant(&"margin_left"), 13)
	assert_eq(panel.get_theme_constant(&"margin_top"), 10)
	assert_eq(panel.tab_height(), 0.0)
	panel.tab_text = "TEREN"
	assert_true(panel.tab_height() > 12.0)
	assert_eq(panel.get_theme_constant(&"margin_top"), 10 + int(panel.tab_height()))
	panel.free()


func test_hatch_bar_builds_stripes_inside_its_size() -> void:
	var bar := HatchBar.new(UiPalette.AMBER, Vector2(150, 3), false)
	bar.size = Vector2(150, 3)
	bar._rebuild()
	assert_true(bar._stripes.size() > 10)
	bar.wide = true
	assert_true(bar._stripes.size() < 20)
	bar.free()


func test_bracketed_wraps_text_in_amber_brackets() -> void:
	var tag := Bracketed.new("TRACKED")
	assert_eq(tag.get_child_count(), 3)
	assert_eq((tag.get_child(0) as Label).text, "[")
	assert_eq((tag.get_child(1) as Label).text, "TRACKED")
	assert_eq((tag.get_child(2) as Label).text, "]")
	tag.text = "FOOT"
	assert_eq((tag.get_child(1) as Label).text, "FOOT")
	tag.free()
