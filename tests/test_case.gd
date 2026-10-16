class_name TestCase
extends RefCounted
## Minimal test base class (no external addons).
## Every method starting with `test_` runs on a fresh instance of the class.

var failures: Array[String] = []


func before_each() -> void:
	pass


func assert_true(condition: bool, message := "") -> void:
	if not condition:
		_fail("expected true. " + message)


func assert_false(condition: bool, message := "") -> void:
	if condition:
		_fail("expected false. " + message)


func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("expected %s, got %s. %s" % [str(expected), str(actual), message])


func _fail(message: String) -> void:
	failures.append(message)
