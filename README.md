# posthog-godot

[![tests](https://github.com/nderman/posthog-godot/actions/workflows/tests.yml/badge.svg)](https://github.com/nderman/posthog-godot/actions/workflows/tests.yml)

A small, dependency-free **[PostHog](https://posthog.com) SDK for Godot 4** — product
analytics & feature flags, built for the engine via the PostHog capture API (there is no
official Godot SDK). **Dev/QA-first:** events are observable in headless tests so you can
*assert on your telemetry* in CI, then point the same events at PostHog Cloud for real
playtest funnels, retention, and remote feature flags.

> Status: **v0.1, dev/QA focus.** Production-shipped concerns (consent UX, durable offline
> queue, console-cert telemetry rules) are intentionally out of scope for now — see
> [Roadmap](#roadmap).

## Why
- **No official PostHog SDK for Godot.** This talks to the documented capture + flags
  endpoints directly — nothing to compile, pure GDScript.
- **Telemetry you can test.** `capture()` always records locally and emits a signal, even
  with no API key, so your test suite can assert events fired with the right properties.
- **Zero gameplay coupling.** Recommended pattern: one autoload that *listens* to your
  signal bus and forwards — gameplay code never imports analytics.
- **Safe by construction.** Fire-and-forget; a network failure or missing key can never
  block a frame or break a run.

## Install
1. Copy `addons/posthog/` into your project's `addons/` folder
   (or install from the Godot Asset Library once published).
2. **Project → Project Settings → Plugins →** enable **PostHog**. This registers the
   `PostHog` autoload and a `posthog/config/*` settings group.
3. Set your project API key in **Project Settings → PostHog → Api Key** (a `phc_...` key —
   publishable, safe to ship in a client), or via the `POSTHOG_API_KEY` env var.

## Usage
```gdscript
# Capture an event anywhere.
PostHog.capture("run_started", {"class": "pyromancer", "seed": 12345})

# Sticky properties merged into every later event.
PostHog.register({"build": "1.4.2"})

# Feature flags (fetched on boot; call reload_feature_flags() to refresh).
if PostHog.is_feature_enabled("hard-mode"):
    spawn_extra_enemies()

var variant = PostHog.get_feature_flag("boss-hp-tuning", "control")  # "control" | "plus15" | ...
```

### Recommended: forward your signal bus (no gameplay coupling)
```gdscript
# Telemetry.gd (autoload). Gameplay emits on SignalBus; this is the only listener that knows
# PostHog exists.
extends Node

func _ready() -> void:
    SignalBus.run_started.connect(func(): PostHog.capture("run_started"))
    SignalBus.leveled_up.connect(func(level, _pts): PostHog.capture("leveled_up", {"level": level}))
    GameManager.floor_changed.connect(func(floor): PostHog.capture("floor_changed", {"floor": floor}))
```

## Assert on telemetry in tests (the dev/QA bit)
With `test_mode = true` (or simply no API key), nothing is sent — events are recorded and
the `event_captured` signal fires, so you can assert on them headlessly:

```gdscript
func test_death_is_tracked() -> void:
    PostHog.test_mode = true
    PostHog.clear_captured()

    kill_player()  # drives your normal gameplay → SignalBus → Telemetry → PostHog.capture(...)

    assert(PostHog.was_captured("player_died"))
    assert(PostHog.last_captured("player_died")["properties"]["floor"] == 3)
```

Seed flags deterministically to test flag-gated branches:
```gdscript
PostHog.set_feature_flags_for_test({"hard-mode": true, "boss-hp-tuning": "plus15"})
```

Run the bundled suite headlessly:
```bash
GODOT=/path/to/Godot ./tests/run_tests.sh
```

## Try it live (smoke test)
Send one real event and confirm PostHog accepted it — no game required:
```bash
POSTHOG_API_KEY=phc_xxx GODOT=/path/to/Godot ./tools/smoke.sh
# EU project? add: POSTHOG_HOST=https://eu.i.posthog.com
```
Grab the key from **Project Settings → Project API Key** (`phc_...`). A green run prints
`✓ PostHog accepted the batch`; the `godot_smoke_test` event shows up in your Activity feed
within a few seconds.

## API reference
| Method | Purpose |
|---|---|
| `capture(event, properties={})` | Record + queue an event. Always records locally + emits `event_captured`. |
| `identify(distinct_id, set_properties={})` | Re-point the anonymous id to a known one (e.g. a playtester). |
| `register(properties)` / `unregister(key)` | Add/remove sticky super-properties. |
| `flush()` | Send queued events now (also auto-flushes on a timer / at `max_batch`). |
| `opt_out()` / `opt_in()` | Stop/resume sending (still records locally). |
| `reload_feature_flags()` | Fetch flags for the current id; emits `feature_flags_loaded`. |
| `is_feature_enabled(key)` / `get_feature_flag(key, default=false)` | Read cached flags. |
| `was_captured(event)` / `captured(event)` / `last_captured(event)` / `clear_captured()` | Test/QA assertions over the local mirror. |
| `set_feature_flags_for_test(flags)` | Seed flags deterministically in tests. |

**Signals:** `event_captured(event, properties)`, `feature_flags_loaded(flags)`,
`flush_completed(ok, event_count)`.

## Configuration (Project Settings → PostHog)
| Setting | Default | Notes |
|---|---|---|
| `enabled` | `true` | Master switch. |
| `api_key` | `""` | `phc_...` project key. Empty ⇒ records locally, sends nothing. |
| `host` | `https://us.i.posthog.com` | Use `https://eu.i.posthog.com` for EU. |
| `flush_interval_sec` | `10` | Timer-based batch flush. |
| `max_batch` | `50` | Flush early once this many events are queued. |
| `capture_app_lifecycle` | `true` | Auto `application_opened` / `application_backgrounded`. |
| `test_mode` | `false` | Record + signal, never send. For tests/CI. |

Env overrides (handy in CI): `POSTHOG_API_KEY`, `POSTHOG_HOST`.

## Roadmap
- [ ] Durable on-disk offline queue with retry/backoff (survive crashes & offline sessions).
- [ ] Consent / opt-in flow helpers for shipped (esp. EU/mobile/console) builds.
- [ ] Session-replay-style aggregate session events.
- [ ] Asset Library submission.
- [ ] Optional CI sink: pipe headless test results into PostHog as engineering-metrics events.

## License
MIT — see [LICENSE](LICENSE).

Not affiliated with PostHog, Inc. "PostHog" is a trademark of its owner.
