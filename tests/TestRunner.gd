# TestRunner.gd
# Runs the suite in ONE headless process so autoloads load once. Each test in TESTS is
# instantiated as a child, its run() awaited, and its fail-count tallied. Exits non-zero
# if anything failed so run_tests.sh / CI can gate.
# Add a test: write tests/test_foo.gd (extends TestCase), then preload it into TESTS.
extends Node

const TESTS := [
	preload("res://tests/test_posthog.gd"),
]

func _ready() -> void:
	print("\n=== posthog-godot — test suite ===")
	# Let autoloads finish their _ready() (PostHog sets up its timer + distinct_id).
	await get_tree().process_frame
	var total_fails := 0
	var failed_files := 0
	for T in TESTS:
		var t: TestCase = T.new()
		add_child(t)
		await t.run()
		if t.fails == 0:
			print("  ✓ %s" % t.test_name)
		else:
			print("  ✗ %s (%d failed)" % [t.test_name, t.fails])
			failed_files += 1
		total_fails += t.fails
		t.queue_free()
	print("=== %d test file(s), %d assertion failure(s) ===\n" % [TESTS.size(), total_fails])
	if total_fails == 0:
		print("SUITE: PASS")
	else:
		print("SUITE: FAIL — %d file(s) with failures" % failed_files)
	get_tree().quit(1 if total_fails > 0 else 0)
