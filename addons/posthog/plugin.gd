@tool
extends EditorPlugin
## Editor plugin: registers the `PostHog` autoload and project settings when the
## addon is enabled, and cleans them up when disabled. The runtime lives entirely
## in `posthog.gd` — this file only wires it into the host project.

const AUTOLOAD_NAME := "PostHog"
const SINGLETON_PATH := "res://addons/posthog/posthog.gd"

## Project Settings exposed in Project > Project Settings > General > PostHog.
## (name, default, type, hint) — kept minimal and dev/QA-friendly.
const SETTINGS := [
	["posthog/config/enabled", true, TYPE_BOOL],
	["posthog/config/api_key", "", TYPE_STRING],
	["posthog/config/host", "https://us.i.posthog.com", TYPE_STRING],
	["posthog/config/flush_interval_sec", 10.0, TYPE_FLOAT],
	["posthog/config/max_batch", 50, TYPE_INT],
	["posthog/config/capture_app_lifecycle", true, TYPE_BOOL],
	# When true, events are recorded + the `event_captured` signal fires, but NOTHING
	# is sent over the network. Intended for headless test runs and CI.
	["posthog/config/test_mode", false, TYPE_BOOL],
]


func _enter_tree() -> void:
	for s in SETTINGS:
		var name: String = s[0]
		if not ProjectSettings.has_setting(name):
			ProjectSettings.set_setting(name, s[1])
		ProjectSettings.set_initial_value(name, s[1])
		ProjectSettings.add_property_info({
			"name": name,
			"type": s[2],
		})
	ProjectSettings.save()
	add_autoload_singleton(AUTOLOAD_NAME, SINGLETON_PATH)


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
