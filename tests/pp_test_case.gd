class_name PPTestCase
extends RefCounted

## Minimal assertion harness for the headless test runner.
##
## Deliberately tiny: this project has no addons, and the tests need to run in
## CI-style headless mode with `godot --headless --script tests/run_tests.gd`.

var suite_name: String = "suite"
var failures: PackedStringArray = PackedStringArray()
var assertions: int = 0


func _init(name: String) -> void:
	suite_name = name


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append("%s: %s" % [suite_name, message])


func equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if not _same(actual, expected):
		failures.append(
			"%s: %s\n      expected: %s\n      actual:   %s"
			% [suite_name, message, str(expected), str(actual)]
		)


func near(actual: float, expected: float, message: String, tolerance: float = 0.001) -> void:
	assertions += 1
	if absf(actual - expected) > tolerance:
		failures.append(
			"%s: %s (expected ~%f, got %f)" % [suite_name, message, expected, actual]
		)


## Compares a pixel of an image against an expected colour, per channel, with a
## tolerance of one 8-bit step to absorb rounding in the blend maths.
func pixel(image: Image, x: int, y: int, expected: Color, message: String) -> void:
	assertions += 1
	var actual: Color = image.get_pixel(x, y)
	var ok: bool = (
		absi(actual.r8 - expected.r8) <= 1
		and absi(actual.g8 - expected.g8) <= 1
		and absi(actual.b8 - expected.b8) <= 1
		and absi(actual.a8 - expected.a8) <= 1
	)
	if not ok:
		failures.append(
			"%s: %s at (%d,%d)\n      expected: %s\n      actual:   %s"
			% [
				suite_name,
				message,
				x,
				y,
				"(%d,%d,%d,%d)" % [expected.r8, expected.g8, expected.b8, expected.a8],
				"(%d,%d,%d,%d)" % [actual.r8, actual.g8, actual.b8, actual.a8],
			]
		)


func _same(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return absf(float(a) - float(b)) < 0.0001
	return a == b
