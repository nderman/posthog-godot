# Publishing to the Godot Asset Library

The repo is the package; the Asset Library is just an index that points at a specific
commit/tag of this repo. This file is the copy-paste cheat-sheet for the submission form.

## Prerequisites (done)
- [x] Public repo, addon at `addons/posthog/` with `plugin.cfg`
- [x] MIT `LICENSE`
- [x] `README.md` with install + usage
- [x] `icon.png` (128×128) for the listing
- [x] Tagged release `v0.1.0`

## Submit
1. Log in at https://godotengine.org/ (same account as the Asset Library).
2. Go to **Submit an Asset** → https://godotengine.org/asset-library/asset/edit?asset=new
3. Fill the form with the values below.
4. Submit → it enters a human moderation queue (approval can take days–weeks).
   Updates = submit a new commit/tag; re-reviewed.

## Form values
| Field | Value |
|---|---|
| Asset name | `PostHog for Godot` |
| Category | **Tools** (alt: Scripts) |
| Godot version | `4.6` (developed/tested on 4.6.3) |
| License | `MIT` |
| Repository host | `GitHub` |
| Repository URL | `https://github.com/nderman/posthog-godot` |
| Issues URL | `https://github.com/nderman/posthog-godot/issues` |
| Download commit | the commit that **`v0.1.0`** tags (use the SHA from `git rev-list -n1 v0.1.0`) |
| Icon URL | `https://raw.githubusercontent.com/nderman/posthog-godot/v0.1.0/icon.png` |

### Description (paste)
```
A dependency-free PostHog SDK for Godot 4 — product analytics and feature flags via
the PostHog capture API (there is no official Godot SDK).

- capture(), identify(), register(), flush() with batched, fire-and-forget sends
- Feature flags: is_feature_enabled() / get_feature_flag()
- Persistent anonymous distinct_id; opt-out; auto app-lifecycle events
- Per-event uuid so retries are deduped server-side
- Dev/QA-first: events are recorded locally + emitted as a signal even with no key,
  so you can assert on your telemetry in headless tests/CI

Set your project API key in Project Settings → PostHog (US or EU host supported).
MIT licensed. Not affiliated with PostHog, Inc.
```

## Notes
- The Asset Library downloads the whole repo zip at the chosen commit. Consumers can
  deselect `tests/`, `examples/`, `tools/`, and `project.godot` in the install dialog;
  only `addons/posthog/` is needed. (Keeping the demo project in-repo is normal and fine.)
- For each new release: bump `version` in `addons/posthog/plugin.cfg`, tag `vX.Y.Z`,
  cut a GitHub release, then submit the new commit in the Asset Library edit page.
