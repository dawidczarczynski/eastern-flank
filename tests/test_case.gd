class_name TestCase
extends RefCounted
## Minimal test base class (no external addons).
## Every method starting with `test_` runs on a fresh instance of the class.
## before_all/after_all run once per file on a separate instance; state shared between the tests
## of a file (e.g. one built MapView the tests only read) lives in `static var`s.

var failures: Array[String] = []


func before_all() -> void:
	pass


func after_all() -> void:
	pass


func before_each() -> void:
	pass


func after_each() -> void:
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
