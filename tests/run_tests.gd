extends SceneTree

## Headless test runner.
##
##   godot --headless --path . --script tests/run_tests.gd
##
## Exits non-zero when anything fails, so it can gate a commit or a CI job.


func _initialize() -> void:
	var suites: Array[PPTestCase] = [
		PPTestCore.run(),
		PPTestTools.run(),
		PPTestIO.run(),
		PPTestSync.run(),
	]

	var total_assertions: int = 0
	var total_failures: int = 0

	print("")
	for suite: PPTestCase in suites:
		total_assertions += suite.assertions
		total_failures += suite.failures.size()
		var status: String = "PASS" if suite.failures.is_empty() else "FAIL"
		print(
			"[%s] %-8s %3d assertions, %d failures"
			% [status, suite.suite_name, suite.assertions, suite.failures.size()]
		)
		for failure: String in suite.failures:
			print("   x  ", failure)

	print("")
	print("%d assertions, %d failures" % [total_assertions, total_failures])
	if total_failures > 0:
		quit(1)
		return
	quit(0)
