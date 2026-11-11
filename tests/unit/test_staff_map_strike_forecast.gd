extends TestCase
## The text model of the strike forecast rows (TASK-101).


func before_all() -> void:
	TranslationServer.set_locale("en")


func test_percent_rounding_clamps() -> void:
	assert_eq(StaffMapStrikeText.forecast_percent(0.0), 0)
	assert_eq(StaffMapStrikeText.forecast_percent(1.0), 100)
	assert_eq(StaffMapStrikeText.forecast_percent(0.0001), 1)
	assert_eq(StaffMapStrikeText.forecast_percent(0.9999), 99)
	assert_eq(StaffMapStrikeText.forecast_percent(0.9375), 94)


func test_installation_rows() -> void:
	var rows := (
		StaffMapStrikeText
		. forecast_rows(
			{
				"count": 4,
				"expected_hits": 2.0,
				"p_at_least_one": 0.9375,
				"kind": &"installation",
				"integrity_before": 100,
				"expected_integrity_after": 41.2,
				"p_destroyed": 0.12,
			}
		)
	)
	assert_eq(rows[0], "Expected hits 2.0 of 4 – at least one hit 94%")
	assert_eq(rows[1], "Expected integrity 100 → 41, destroyed ~12%")
	rows = (
		StaffMapStrikeText
		. forecast_rows(
			{
				"count": 1,
				"expected_hits": 0.5,
				"p_at_least_one": 0.5,
				"kind": &"installation",
				"integrity_before": 100,
				"expected_integrity_after": 80.0,
				"p_destroyed": 0.0,
			}
		)
	)
	assert_eq(rows[1], "Expected integrity 100 → 80", "no tail without a chance to destroy")


func test_formation_rows() -> void:
	var forecast := {
		"count": 2,
		"expected_hits": 1.0,
		"p_at_least_one": 0.75,
		"kind": &"formation",
		"expected_strength_lost": 2.6,
		"p_destroyed": 0.0,
	}
	assert_eq(StaffMapStrikeText.forecast_rows(forecast)[1], "Expected loss ~3 strength")
	forecast["p_destroyed"] = 0.04
	assert_eq(
		StaffMapStrikeText.forecast_rows(forecast)[1], "Expected loss ~3 strength, destroyed ~4%"
	)
	assert_true(StaffMapStrikeText.forecast_rows({}).is_empty())
