extends Node
## Minimal usage demo. Run the project (F5) and watch the output / your PostHog Activity
## feed (set an API key in Project Settings > PostHog, or POSTHOG_API_KEY env var).
##
## This mirrors how you'd wire a game: capture lifecycle + gameplay events, and gate a
## branch on a feature flag.

func _ready() -> void:
	print("[demo] distinct_id =", PostHog.distinct_id)

	# Observe the stream locally (great for a QA overlay).
	PostHog.event_captured.connect(func(e, p): print("[demo] captured:", e, p))

	# A couple of gameplay-ish events.
	PostHog.capture("run_started", {"class": "pyromancer", "seed": 12345})
	PostHog.capture("floor_changed", {"floor": 1})

	# Flag-gated behaviour. In test/CI you'd seed this; live it comes from the server.
	if PostHog.is_feature_enabled("hard-mode"):
		print("[demo] hard-mode ON")

	# Force a send so the demo doesn't wait for the flush timer.
	PostHog.flush()
