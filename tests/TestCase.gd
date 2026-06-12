# TestCase.gd
# Tiny base class for the headless suite. A test extends this, sets `test_name`, and
# overrides `run()` with its assertions (run() MAY await frames/timers). The TestRunner
# instantiates each as a child (so autoloads like PostHog resolve), awaits run(), and
# tallies `fails`. Deliberately dependency-free — this is also the pattern a consumer can
# copy to assert on their own telemetry.
class_name TestCase
extends Node

var fails := 0
var test_name := "test"

func run() -> void:
	pass

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("    ✗ [%s] %s" % [test_name, msg])

func eq(a, b, msg: String) -> void:
	check(a == b, "%s — got %s, want %s" % [msg, a, b])

func ne(a, b, msg: String) -> void:
	check(a != b, "%s — got %s, did not want it" % [msg, a])

func truthy(v, msg: String) -> void:
	var ok := false
	match typeof(v):
		TYPE_NIL: ok = false
		TYPE_BOOL: ok = v
		TYPE_INT, TYPE_FLOAT: ok = v != 0
		TYPE_STRING, TYPE_STRING_NAME: ok = v != ""
		TYPE_OBJECT: ok = v != null
		_: ok = true
	check(ok, msg)
