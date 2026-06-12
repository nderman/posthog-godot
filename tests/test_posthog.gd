# test_posthog.gd
# Exercises the SDK in test_mode (no network): event recording, the event_captured signal,
# super properties, feature-flag seeding, identify(), and opt-out. This doubles as the
# reference for how a consumer asserts on their own telemetry in CI.
extends TestCase

func run() -> void:
	test_name = "posthog_core"
	PostHog.test_mode = true        # belt-and-suspenders: never touch the network in tests
	PostHog.clear_captured()

	# --- capture() records locally + fires the signal, even with no API key ---
	var seen := {"hit": false, "props": {}}
	var cb := func(event: String, props: Dictionary):
		if event == "level_started":
			seen["hit"] = true
			seen["props"] = props
	PostHog.event_captured.connect(cb)

	PostHog.capture("level_started", {"level": 3, "class": "pyromancer"})

	check(seen["hit"], "event_captured signal fired for level_started")
	check(PostHog.was_captured("level_started"), "was_captured() finds the event")
	eq(PostHog.last_captured("level_started")["properties"]["level"], 3, "property round-trips")
	# Library super-properties are merged in automatically.
	eq(seen["props"].get("$lib"), "posthog-godot", "$lib super-property present")
	truthy(seen["props"].get("$os"), "$os super-property present")
	PostHog.event_captured.disconnect(cb)

	# --- register() adds a sticky super-property to subsequent events ---
	PostHog.register({"build": "qa-42"})
	PostHog.capture("thing_happened")
	eq(PostHog.last_captured("thing_happened")["properties"].get("build"), "qa-42", "registered super-prop sticks")
	PostHog.unregister("build")

	# --- feature flags can be seeded deterministically for flag-gated code ---
	PostHog.set_feature_flags_for_test({"hard-mode": true, "boss-hp-tuning": "plus15"})
	check(PostHog.is_feature_enabled("hard-mode"), "boolean flag enabled")
	check(PostHog.is_feature_enabled("boss-hp-tuning"), "multivariate flag counts as enabled")
	eq(PostHog.get_feature_flag("boss-hp-tuning"), "plus15", "variant returned")
	check(not PostHog.is_feature_enabled("nope"), "unknown flag is disabled")
	eq(PostHog.get_feature_flag("nope", "default"), "default", "unknown flag returns default")

	# --- identify() re-points the distinct_id and emits $identify ---
	# Normalize to a known starting id first: identify() persists to user://, so relying on
	# the boot id would make this run-order dependent (and leak between runs).
	PostHog.clear_captured()
	PostHog.distinct_id = "anon-before-identify"
	var before := PostHog.distinct_id
	PostHog.identify("tester@example.com", {"cohort": "internal"})
	eq(PostHog.distinct_id, "tester@example.com", "distinct_id updated")
	ne(PostHog.distinct_id, before, "distinct_id actually changed")
	check(PostHog.was_captured("$identify"), "$identify event captured")

	# --- opt_out() stops sending but still records locally ---
	PostHog.opt_out()
	PostHog.clear_captured()
	PostHog.capture("after_opt_out")
	check(PostHog.was_captured("after_opt_out"), "events still recorded after opt_out (local mirror)")
	PostHog.opt_in()
