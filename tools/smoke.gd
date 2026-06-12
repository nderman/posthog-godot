extends Node
## Live smoke test: send a real event to PostHog and report whether it was accepted.
## Run via tools/smoke.sh with POSTHOG_API_KEY set. Quits 0 on a 2xx from /batch/, else non-zero.
## After a green run, look for `godot_smoke_test` in your PostHog Activity feed (a few seconds delay).

func _ready() -> void:
	if PostHog.api_key.is_empty():
		push_error("[smoke] No API key. Set POSTHOG_API_KEY (a phc_... project key).")
		get_tree().quit(2)
		return

	print("[smoke] host=", PostHog.host)
	print("[smoke] distinct_id=", PostHog.distinct_id)

	PostHog.flush_completed.connect(_on_flush)

	PostHog.capture("godot_smoke_test", {
		"source": "tools/smoke.sh",
		"engine": Engine.get_version_info().get("string", ""),
		"unix": Time.get_unix_time_from_system(),
	})
	print("[smoke] captured 'godot_smoke_test', flushing…")
	PostHog.flush()

	# Safety net so the harness never hangs in CI / on a network stall.
	await get_tree().create_timer(20.0).timeout
	push_error("[smoke] timed out waiting for the flush to complete")
	get_tree().quit(1)


func _on_flush(ok: bool, count: int) -> void:
	if ok:
		print("[smoke] ✓ PostHog accepted the batch (%d event(s)). Check your Activity feed." % count)
	else:
		push_error("[smoke] ✗ flush failed (transport or non-2xx). Check key/host/network.")
	get_tree().quit(0 if ok else 1)
