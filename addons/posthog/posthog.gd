extends Node
## PostHog for Godot 4 — product analytics & feature flags.
##
## Registered as the `PostHog` autoload by the editor plugin (or add it manually).
## Fire-and-forget by design: capture() never blocks a frame and a network failure
## can never break your game. With no API key, or with `test_mode` on, it records
## events locally and emits `event_captured` but sends nothing — which is exactly
## the seam your headless tests assert against.
##
## Quick start:
##   PostHog.capture("level_started", {"level": 3})
##   if PostHog.is_feature_enabled("hard-mode"): ...
##
## Dev/QA / tests:
##   PostHog.test_mode = true
##   # ... drive gameplay ...
##   assert(PostHog.was_captured("player_died"))

const LIB_NAME := "posthog-godot"
const LIB_VERSION := "0.1.0"
const DISTINCT_ID_FILE := "user://posthog.cfg"
const CAPTURED_RING_MAX := 1000

## Emitted for EVERY captured event (live, no-key, or test mode), after enqueue.
## Connect from a QA overlay or a test to observe the stream without a network round-trip.
signal event_captured(event: String, properties: Dictionary)
## Emitted once feature flags have been (re)loaded from the server.
signal feature_flags_loaded(flags: Dictionary)
## Emitted after a batch POST resolves. `ok` is false on any transport/HTTP error.
signal flush_completed(ok: bool, event_count: int)

# --- Configuration (resolved from ProjectSettings in _ready, overridable at runtime) ---
var enabled := true
var api_key := ""
var host := "https://us.i.posthog.com"
var flush_interval_sec := 10.0
var max_batch := 50
var capture_app_lifecycle := true
## When true: record + emit signals, but never hit the network. For tests/CI.
var test_mode := false

# --- State ---
var distinct_id := ""
## Ring buffer of recently captured events: [{event, properties, timestamp}]. For QA + asserts.
var captured_events: Array[Dictionary] = []

var _opted_out := false
var _queue: Array[Dictionary] = []
var _flush_timer: Timer
var _feature_flags: Dictionary = {}      # key -> bool|String(variant)
var _flags_loaded := false
var _super_props: Dictionary = {}        # merged into every event's properties


func _ready() -> void:
	_load_config()
	distinct_id = _load_or_create_distinct_id()
	_super_props = _default_super_properties()

	_flush_timer = Timer.new()
	_flush_timer.wait_time = max(1.0, flush_interval_sec)
	_flush_timer.autostart = true
	_flush_timer.timeout.connect(flush)
	add_child(_flush_timer)

	if capture_app_lifecycle:
		capture("application_opened")
	# Try to pull feature flags on boot (no-ops cleanly when disabled / keyless).
	reload_feature_flags()


# --------------------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------------------

## Capture an event. `properties` are merged over the library + super properties.
## Always records locally and emits `event_captured`; only sends when active().
func capture(event: String, properties: Dictionary = {}) -> void:
	if event.is_empty():
		push_warning("[PostHog] capture() called with empty event name; ignored.")
		return

	var props := _super_props.duplicate(true)
	for k in properties:
		props[k] = properties[k]

	var payload := {
		"event": event,
		"distinct_id": distinct_id,
		"properties": props,
		"timestamp": _now_iso8601(),
	}

	# Local mirror first — tests/QA see every event regardless of network/key.
	_record(payload)
	event_captured.emit(event, props)

	if not _is_active():
		return

	_queue.append(payload)
	if _queue.size() >= max_batch:
		flush()


## Associate the current anonymous id with a known id (e.g. a playtester handle), and
## optionally set person properties. Dev/QA-friendly; no auth implied.
func identify(new_distinct_id: String, set_properties: Dictionary = {}) -> void:
	if new_distinct_id.is_empty():
		return
	var props := {"$set": set_properties} if not set_properties.is_empty() else {}
	props["$anon_distinct_id"] = distinct_id
	distinct_id = new_distinct_id
	_persist_distinct_id(distinct_id)
	capture("$identify", props)


## Set properties merged into every subsequent event (e.g. build number, platform).
func register(properties: Dictionary) -> void:
	for k in properties:
		_super_props[k] = properties[k]


func unregister(key: String) -> void:
	_super_props.erase(key)


## Opt the current install out of all sending (events still record locally + emit signals).
func opt_out() -> void:
	_opted_out = true


func opt_in() -> void:
	_opted_out = false


## Flush the queued events to PostHog's /batch/ endpoint. Safe to call anytime;
## no-ops when inactive or the queue is empty.
func flush() -> void:
	if not _is_active() or _queue.is_empty():
		return
	var batch := _queue
	_queue = []
	_send_batch(batch)


# --- Feature flags -------------------------------------------------------------------

## Returns true if the boolean (or any variant of a multivariate) flag is enabled.
## Reads the cached value; call reload_feature_flags() to refresh from the server.
func is_feature_enabled(key: String) -> bool:
	if not _feature_flags.has(key):
		return false
	var v = _feature_flags[key]
	return v if v is bool else v != null


## Returns the flag value: a bool for boolean flags, the variant String for
## multivariate flags, or `default` if the flag is unknown.
func get_feature_flag(key: String, default = false):
	return _feature_flags.get(key, default)


func feature_flags() -> Dictionary:
	return _feature_flags.duplicate(true)


func feature_flags_ready() -> bool:
	return _flags_loaded


## Fetch feature flags for the current distinct_id. Emits `feature_flags_loaded`.
func reload_feature_flags() -> void:
	if not _is_active():
		return
	var req := _new_request()
	req.request_completed.connect(
		func(_result, code, _headers, body): _on_flags_response(req, code, body)
	)
	var url := "%s/flags/?v=2" % _base()
	var data := JSON.stringify({"api_key": api_key, "distinct_id": distinct_id})
	var err := req.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, data)
	if err != OK:
		req.queue_free()


# --- Test / QA helpers ---------------------------------------------------------------

## True if an event with this name has been captured since the last clear.
func was_captured(event: String) -> bool:
	for e in captured_events:
		if e["event"] == event:
			return true
	return false


## All captured events with this name (each: {event, properties, timestamp}).
func captured(event: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in captured_events:
		if e["event"] == event:
			out.append(e)
	return out


## The most recent captured event with this name, or {} if none.
func last_captured(event: String) -> Dictionary:
	for i in range(captured_events.size() - 1, -1, -1):
		if captured_events[i]["event"] == event:
			return captured_events[i]
	return {}


## Clear the local event mirror (call between tests).
func clear_captured() -> void:
	captured_events.clear()


## Seed feature flags directly — handy for deterministic tests of flag-gated code.
func set_feature_flags_for_test(flags: Dictionary) -> void:
	_feature_flags = flags.duplicate(true)
	_flags_loaded = true
	feature_flags_loaded.emit(_feature_flags.duplicate(true))


# --------------------------------------------------------------------------------------
# Internals
# --------------------------------------------------------------------------------------

func _is_active() -> bool:
	return enabled and not test_mode and not _opted_out and not api_key.is_empty()


func _base() -> String:
	return host.rstrip("/")


func _record(payload: Dictionary) -> void:
	captured_events.append(payload)
	if captured_events.size() > CAPTURED_RING_MAX:
		captured_events.pop_front()


func _send_batch(batch: Array) -> void:
	var req := _new_request()
	req.request_completed.connect(
		func(result, code, _headers, _body):
			var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
			if not ok:
				# Re-queue on failure so events aren't lost (best-effort, bounded by max_batch growth).
				for e in batch:
					if _queue.size() < max_batch * 4:
						_queue.append(e)
			flush_completed.emit(ok, batch.size())
			req.queue_free()
	)
	var body := JSON.stringify({
		"api_key": api_key,
		"historical_migration": false,
		"batch": batch,
	})
	var err := req.request("%s/batch/" % _base(), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		flush_completed.emit(false, batch.size())


func _on_flags_response(req: HTTPRequest, code: int, body: PackedByteArray) -> void:
	req.queue_free()
	if code < 200 or code >= 300:
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var flags: Dictionary = {}
	# /flags v2 shape: {"flags": {key: {"enabled": bool, "variant": String|null}}}
	if parsed.has("flags") and parsed["flags"] is Dictionary:
		for key in parsed["flags"]:
			var f = parsed["flags"][key]
			if f is Dictionary:
				flags[key] = f.get("variant") if f.get("variant") != null else f.get("enabled", false)
			else:
				flags[key] = f
	# /decide legacy shape: {"featureFlags": {key: bool|String}}
	elif parsed.has("featureFlags") and parsed["featureFlags"] is Dictionary:
		flags = parsed["featureFlags"]
	_feature_flags = flags
	_flags_loaded = true
	feature_flags_loaded.emit(_feature_flags.duplicate(true))


func _new_request() -> HTTPRequest:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	return req


func _load_config() -> void:
	enabled = _setting("posthog/config/enabled", enabled)
	api_key = _setting("posthog/config/api_key", api_key)
	host = _setting("posthog/config/host", host)
	flush_interval_sec = _setting("posthog/config/flush_interval_sec", flush_interval_sec)
	max_batch = _setting("posthog/config/max_batch", max_batch)
	capture_app_lifecycle = _setting("posthog/config/capture_app_lifecycle", capture_app_lifecycle)
	test_mode = _setting("posthog/config/test_mode", test_mode)
	# Env override is handy in CI: POSTHOG_API_KEY / POSTHOG_HOST.
	if OS.has_environment("POSTHOG_API_KEY"):
		api_key = OS.get_environment("POSTHOG_API_KEY")
	if OS.has_environment("POSTHOG_HOST"):
		host = OS.get_environment("POSTHOG_HOST")


func _setting(name: String, fallback):
	return ProjectSettings.get_setting(name, fallback) if ProjectSettings.has_setting(name) else fallback


func _default_super_properties() -> Dictionary:
	return {
		"$lib": LIB_NAME,
		"$lib_version": LIB_VERSION,
		"$os": OS.get_name(),
		"$app_version": ProjectSettings.get_setting("application/config/version", ""),
		"engine_version": Engine.get_version_info().get("string", ""),
	}


func _now_iso8601() -> String:
	return "%sZ" % Time.get_datetime_string_from_system(true)


func _load_or_create_distinct_id() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(DISTINCT_ID_FILE) == OK:
		var existing := str(cfg.get_value("identity", "distinct_id", ""))
		if not existing.is_empty():
			return existing
	var id := _uuid_v4()
	_persist_distinct_id(id)
	return id


func _persist_distinct_id(id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("identity", "distinct_id", id)
	cfg.save(DISTINCT_ID_FILE)


func _uuid_v4() -> String:
	# RFC-4122-ish v4 from the engine RNG. Good enough for an anonymous analytics id.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var b := PackedByteArray()
	for i in 16:
		b.append(rng.randi() % 256)
	b[6] = (b[6] & 0x0f) | 0x40   # version 4
	b[8] = (b[8] & 0x3f) | 0x80   # variant 10
	var hex := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


func _notification(what: int) -> void:
	# Best-effort flush when the app is backgrounded or closing.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if capture_app_lifecycle:
			capture("application_backgrounded")
		flush()
